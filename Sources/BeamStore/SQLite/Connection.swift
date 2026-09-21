import Foundation
import SQLite3

/// One SQLite connection with a prepared-statement cache and nestable transactions.
///
/// Not thread-safe by itself: `Database` (an actor) is its only user and serialises every call,
/// which is also why the connection is opened without SQLite's own mutexes.
final class Connection {
    /// How long a statement waits for another process holding the file (a second Beam, the sqlite3 shell) before failing.
    static let busyTimeoutMilliseconds: Int32 = 5_000

    private var handle: OpaquePointer?
    /// Keyed by SQL text. Every statement the store runs is one of a few dozen constant strings,
    /// so the cache is bounded by construction and nothing is ever prepared twice.
    private var statements: [String: Statement] = [:]
    private var transactionDepth = 0

    init(path: String) throws {
        var opened: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(path, &opened, flags, nil) == SQLITE_OK, let opened else {
            let error = StoreError.current(opened, context: "open \(path)")
            sqlite3_close_v2(opened)
            throw error
        }
        handle = opened
        do {
            try configure(opened)
        } catch {
            sqlite3_close_v2(opened)
            handle = nil
            throw error
        }
    }

    private func configure(_ opened: OpaquePointer) throws {
        sqlite3_extended_result_codes(opened, 1)
        sqlite3_busy_timeout(opened, Self.busyTimeoutMilliseconds)
        // WAL keeps a reader (the sqlite3 shell, a second Beam) and the writer out of each other's way.
        // The pragma answers with the resulting mode, so it is read as a query; `Database.diagnostics()` reports it.
        _ = try scalar("PRAGMA journal_mode = WAL") { $0.string(0) }
        // NORMAL is what WAL is designed for: safe across app crashes, one fsync per checkpoint instead of per commit.
        // Foreign keys are off by default in SQLite, and the cascades depend on them.
        try execute(script: "PRAGMA synchronous = NORMAL; PRAGMA foreign_keys = ON;")
    }

    deinit {
        finalizeStatements()
        // close_v2 cannot fail: if anything were still open SQLite would defer the close instead of leaking the file handle.
        sqlite3_close_v2(handle)
    }

    /// Finalizes every statement and closes the file. Throws if SQLite reports unfinished work, which would mean a leaked statement.
    func close() throws {
        guard let open = handle else { return }
        finalizeStatements()
        guard sqlite3_close(open) == SQLITE_OK else { throw StoreError.current(open, context: "close") }
        handle = nil
    }

    var cachedStatementCount: Int { statements.count }

    // MARK: Running SQL

    /// Runs statements that take no parameters and return nothing: schema, pragmas, transaction control.
    func execute(script: String) throws {
        let open = try openHandle()
        guard sqlite3_exec(open, script, nil, nil, nil) == SQLITE_OK else { throw StoreError.current(open, context: script) }
    }

    /// Runs one statement to completion and returns the number of rows it changed.
    @discardableResult
    func execute(_ sql: String, _ bindings: [any SQLBindable] = []) throws -> Int {
        let open = try openHandle()
        try run(sql, bindings) { statement in
            while try statement.step() {}
        }
        return Int(sqlite3_changes64(open))
    }

    /// Reads every row eagerly. No cursor escapes, so a cached statement is never left mid-run holding a read snapshot.
    func query<T>(_ sql: String, _ bindings: [any SQLBindable] = [], _ map: (Row) throws -> T) throws -> [T] {
        try run(sql, bindings) { statement in
            var rows: [T] = []
            while try statement.step() { rows.append(try map(statement.row)) }
            return rows
        }
    }

    /// The first row, or nil when there is none.
    func first<T>(_ sql: String, _ bindings: [any SQLBindable] = [], _ map: (Row) throws -> T) throws -> T? {
        try run(sql, bindings) { statement in
            try statement.step() ? try map(statement.row) : nil
        }
    }

    /// For statements that always return exactly one row (COUNT, PRAGMA).
    func scalar<T>(_ sql: String, _ bindings: [any SQLBindable] = [], _ map: (Row) throws -> T) throws -> T {
        guard let value = try first(sql, bindings, map) else { throw StoreError.corrupt("no row from: \(sql)") }
        return value
    }

    var lastInsertedID: Int64 {
        get throws { sqlite3_last_insert_rowid(try openHandle()) }
    }

    // MARK: Transactions

    /// Runs `body` atomically. Nested calls become savepoints, so store operations compose:
    /// an inner failure undoes only the inner work unless the error travels on to the outer level.
    /// The transaction is closed on every path: commit, thrown error, or a commit that itself fails.
    func transaction<T>(_ body: () throws -> T) throws -> T {
        let savepoint = "beam_\(transactionDepth)"
        let isOutermost = transactionDepth == 0
        // IMMEDIATE takes the write lock up front, where the busy timeout applies, instead of failing midway on a lock upgrade.
        try execute(isOutermost ? "BEGIN IMMEDIATE" : "SAVEPOINT \(savepoint)")
        transactionDepth += 1
        defer { transactionDepth -= 1 }
        do {
            let value = try body()
            try execute(isOutermost ? "COMMIT" : "RELEASE \(savepoint)")
            return value
        } catch {
            // ROLLBACK TO rewinds a savepoint but leaves it open; RELEASE then closes it.
            try rollBack(isOutermost ? ["ROLLBACK"] : ["ROLLBACK TO \(savepoint)", "RELEASE \(savepoint)"], after: error)
            throw error
        }
    }

    private func rollBack(_ statements: [String], after cause: Error) throws {
        // Disk-full and I/O errors make SQLite roll back by itself; a second ROLLBACK would then be an error of its own.
        guard let open = handle, sqlite3_get_autocommit(open) == 0 else { return }
        do {
            for statement in statements { try execute(statement) }
        } catch {
            throw StoreError.rollbackFailed(cause: "\(cause)", rollback: "\(error)")
        }
    }

    // MARK: Statement cache

    private func run<T>(_ sql: String, _ bindings: [any SQLBindable], _ body: (Statement) throws -> T) throws -> T {
        let statement = try prepared(sql)
        defer { statement.reset() }
        try statement.bind(bindings)
        return try body(statement)
    }

    private func prepared(_ sql: String) throws -> Statement {
        if let cached = statements[sql] { return cached }
        let statement = try Statement(sql: sql, database: try openHandle())
        statements[sql] = statement
        return statement
    }

    private func finalizeStatements() {
        for statement in statements.values { statement.finalize() }
        statements.removeAll()
    }

    private func openHandle() throws -> OpaquePointer {
        guard let handle else { throw StoreError.closed }
        return handle
    }
}
