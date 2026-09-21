import BeamModels
import Dispatch
import Foundation

/// Beam's one SQLite file: sources, items, pins, judgments, articles, spend and settings.
///
/// An actor because SQLite wants one writer at a time and the engine calls from many tasks.
/// Every operation is synchronous inside the actor (no `await` between its statements), so operations
/// never interleave and a transaction can never be left open across a suspension.
///
/// The operations themselves live in extensions, one file per table family
/// (`Sources`, `ItemUpsert`, `ItemQueries`, `ReadState`, `Pins`, `Judgments`, `Articles`, `Spend`, `Meta`, `Housekeeping`).
public actor Database {
    let connection: Connection
    private let queue: DispatchSerialQueue

    /// Database calls block on disk I/O. They run on their own serial queue so they never occupy a thread of
    /// Swift's cooperative pool, which the judge's 64 in-flight requests and the feed refresher share.
    public nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    /// Opens (creating it and its folder if needed) the database at `fileURL`, migrates it to the current schema,
    /// and deletes for good whatever was removed in the previous session: Undo lasts until Beam quits.
    /// For the same reason, open a file once per process: a second `Database` on it would end the first one's Undo.
    public init(fileURL: URL) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try self.init(path: fileURL.path)
    }

    /// A private, empty database that vanishes with the instance. For checks and fixtures.
    public static func inMemory() throws -> Database {
        try Database(path: ":memory:")
    }

    private init(path: String) throws {
        let connection = try Connection(path: path)
        try Schema.migrate(connection)
        try Housekeeping.purgeRemoved(connection)
        self.connection = connection
        // `.workItem`: a private queue never drains its autorelease pool by itself, and every call here bridges
        // Foundation objects (URLs, dates, JSON). Without it a long-lived database would only ever grow.
        self.queue = DispatchSerialQueue(label: "dev.beam.store", qos: .userInitiated, autoreleaseFrequency: .workItem)
    }

    /// Runs several store operations as one atomic unit: all of them happen, or none.
    /// The closure runs on the actor, so it calls the store synchronously: `try db.transaction { db in try db.addPin(…) }`.
    /// Store operations that open their own transaction nest inside it as savepoints.
    public func transaction<T: Sendable>(_ body: @Sendable (isolated Database) throws -> T) throws -> T {
        try connection.transaction { try body(self) }
    }

    /// Finalizes every prepared statement and closes the file. Later calls throw `StoreError.closed`.
    /// Dropping the last reference closes the database too; call this when a failure to close cleanly should be heard.
    public func close() throws {
        try connection.close()
    }

    /// How the connection is actually configured, read back from SQLite rather than assumed.
    public func diagnostics() throws -> StoreDiagnostics {
        StoreDiagnostics(
            schemaVersion: try Schema.version(of: connection),
            journalMode: try connection.scalar("PRAGMA journal_mode") { $0.string(0) },
            foreignKeysEnabled: try connection.scalar("PRAGMA foreign_keys") { $0.bool(0) },
            busyTimeoutMilliseconds: try connection.scalar("PRAGMA busy_timeout") { $0.int(0) },
            cachedStatements: connection.cachedStatementCount)
    }
}

public struct StoreDiagnostics: Hashable, Sendable {
    public var schemaVersion: Int
    /// "wal" for a file; "memory" for an in-memory database.
    public var journalMode: String
    public var foreignKeysEnabled: Bool
    public var busyTimeoutMilliseconds: Int
    /// Distinct statements prepared so far. It stops growing once every operation has run once.
    public var cachedStatements: Int
}
