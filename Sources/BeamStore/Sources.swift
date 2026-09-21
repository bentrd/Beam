import BeamModels
import Foundation

extension Database {
    private static let sourceColumns = "id, kind, title, feed_url, site_url, position, last_fetch, last_error, failing_since"

    /// The sources in sidebar order. Removed sources are not listed.
    public func sources() throws -> [Source] {
        try connection.query("SELECT \(Self.sourceColumns) FROM source WHERE removed IS NULL ORDER BY position, id") { try Self.source(from: $0) }
    }

    public func source(id: Int64) throws -> Source? {
        try connection.first("SELECT \(Self.sourceColumns) FROM source WHERE id = ? AND removed IS NULL", [id]) { try Self.source(from: $0) }
    }

    /// The live source with exactly this feed address, if any: what the Add Source popover checks for "Already added".
    public func source(feedURL: URL) throws -> Source? {
        try connection.first("SELECT \(Self.sourceColumns) FROM source WHERE feed_url = ? AND removed IS NULL", [feedURL]) { try Self.source(from: $0) }
    }

    /// Appends a source to the end of the sidebar. Never returns `.failed`: database errors are thrown.
    ///
    /// Adding back a feed that was removed earlier in this session revives it, with its items and their read states,
    /// rather than starting from nothing (the unique feed address would refuse a second row anyway).
    public func addSource(_ candidate: SourceCandidate) throws -> AddOutcome {
        try connection.transaction {
            let existing = try connection.first("SELECT id, removed IS NOT NULL FROM source WHERE feed_url = ?", [candidate.feedURL]) {
                (id: $0.int64(0), isRemoved: $0.bool(1))
            }
            let id: Int64
            switch existing {
            case let .some(row) where row.isRemoved:
                try connection.execute("UPDATE source SET kind = ?, title = ?, site_url = ?, position = ?, removed = NULL WHERE id = ?",
                                       [candidate.kind.rawValue, candidate.title, candidate.siteURL, try connection.nextPosition(in: .source), row.id])
                id = row.id
            case .some:
                return .alreadyAdded
            case .none:
                try connection.execute("INSERT INTO source(kind, title, feed_url, site_url, position) VALUES (?, ?, ?, ?, ?)",
                                       [candidate.kind.rawValue, candidate.title, candidate.feedURL, candidate.siteURL,
                                        try connection.nextPosition(in: .source)])
                id = try connection.lastInsertedID
            }
            guard let added = try source(id: id) else { throw StoreError.notFound("source \(id) after insert") }
            return .added(added)
        }
    }

    /// Hides the source and everything under it, keeping it all for Undo until the database next opens.
    /// Returns the source as it was, or nil when there is no such live source.
    @discardableResult
    public func removeSource(id: Int64, at date: Date = Date()) throws -> Source? {
        try connection.transaction {
            guard let removed = try source(id: id) else { return nil }
            _ = try connection.softDelete(id, at: date, in: .source)
            return removed
        }
    }

    /// Undo for Remove Source: the source returns to its place with its items, their read states and cached articles.
    /// Judgments are keyed by text, not by source, so they were never gone.
    /// Throws `notFound` once the removal has become permanent (the database was reopened).
    @discardableResult
    public func restoreSource(id: Int64) throws -> Source {
        try connection.transaction {
            let isRemoved = try connection.first("SELECT removed IS NOT NULL FROM source WHERE id = ?", [id]) { $0.bool(0) }
            guard let isRemoved else { throw StoreError.notFound("source \(id)") }
            if isRemoved { try connection.restore(id, in: .source) }
            guard let restored = try source(id: id) else { throw StoreError.notFound("source \(id)") }
            return restored
        }
    }

    /// Moves a source up (negative offset) or down in the sidebar, stopping at the ends.
    public func moveSource(id: Int64, by offset: Int) throws {
        guard try connection.move(id, by: offset, in: .source) else { throw StoreError.notFound("source \(id)") }
    }

    /// A fetch worked: the error and the failing-since stamp clear, so the sidebar warning goes away.
    public func recordFetchSuccess(sourceID: Int64, at date: Date = Date()) throws {
        let changed = try connection.execute("UPDATE source SET last_fetch = ?, last_error = NULL, failing_since = NULL WHERE id = ?", [date, sourceID])
        guard changed == 1 else { throw StoreError.notFound("source \(sourceID)") }
    }

    /// A fetch failed. `failing_since` is set by the first failure of a run and kept by the following ones,
    /// because the sidebar warns only after 24 hours of continuous failure. `last_fetch` keeps meaning "last success".
    public func recordFetchFailure(sourceID: Int64, error: String, at date: Date = Date()) throws {
        let changed = try connection.execute("UPDATE source SET last_error = ?, failing_since = COALESCE(failing_since, ?) WHERE id = ?",
                                             [error, date, sourceID])
        guard changed == 1 else { throw StoreError.notFound("source \(sourceID)") }
    }

    private static func source(from row: Row) throws -> Source {
        guard let kind = SourceKind(rawValue: row.string(1)) else { throw StoreError.corrupt("source kind '\(row.string(1))'") }
        guard let feedURL = URL(string: row.string(3)) else { throw StoreError.corrupt("feed URL '\(row.string(3))'") }
        return Source(id: row.int64(0), kind: kind, title: row.string(2), feedURL: feedURL, siteURL: row.optionalURL(4),
                      position: row.int(5), lastFetch: row.optionalDate(6), lastError: row.optionalString(7), failingSince: row.optionalDate(8))
    }
}
