import BeamModels
import Foundation

/// Which stored items a query or a bulk change covers.
///
/// There is no pin case on purpose: what belongs to a pin is decided by judgments, which the engine combines with
/// `newestItems`. For a pin list the engine names the rows itself (`setRead(_:itemIDs:)`).
public enum ItemScope: Hashable, Sendable {
    case all
    case source(Int64)
}

extension Database {
    /// Items of removed sources stay in the file for Undo but are invisible to every list and count.
    static let liveItemFilter = "source_id NOT IN (SELECT id FROM source WHERE removed IS NOT NULL)"
    /// Must match the `item_sort` indexes letter for letter, or SQLite sorts 50,000 rows instead of walking an index.
    static let newestFirst = "COALESCE(published, fetched) DESC, id DESC"

    /// One item with its feed `content`, which is what the article loader needs. Works for items of a removed source too
    /// (the reader may still be showing one).
    public func item(id: Int64) throws -> Item? {
        try connection.first("SELECT \(Self.itemColumns(withContent: true)) FROM item WHERE id = ?", [id]) { Self.item(from: $0) }
    }

    /// The items a refresh reported as new or edited (`UpsertResult`), in list order and without `content`:
    /// what the engine loads to judge them. Unknown ids are skipped.
    public func items(ids: [Int64]) throws -> [Item] {
        guard !ids.isEmpty else { return [] }
        let list = "[" + ids.map(String.init).joined(separator: ",") + "]"
        return try connection.query("""
            SELECT \(Self.itemColumns(withContent: false)) FROM item WHERE id IN (SELECT value FROM json_each(?))
            ORDER BY \(Self.newestFirst)
            """, [list]) { Self.item(from: $0) }
    }

    /// The newest items of a scope, in list order (`Item.sortDate`, newest first).
    ///
    /// `content` is left nil: a list never shows it, and full feed HTML for 300 rows would cost megabytes per snapshot.
    /// Load `item(id:)` before opening one. `offset` pages further back ("Check 1,200 older").
    public func newestItems(in scope: ItemScope = .all, limit: Int, offset: Int = 0, unreadOnly: Bool = false) throws -> [Item] {
        var conditions = [Self.liveItemFilter]
        var bindings: [any SQLBindable] = []
        if case let .source(id) = scope {
            conditions.append("source_id = ?")
            bindings.append(id)
        }
        if unreadOnly { conditions.append("read = 0") }
        bindings.append(max(limit, 0))
        bindings.append(max(offset, 0))
        let sql = """
            SELECT \(Self.itemColumns(withContent: false)) FROM item WHERE \(conditions.joined(separator: " AND "))
            ORDER BY \(Self.newestFirst) LIMIT ? OFFSET ?
            """
        return try connection.query(sql, bindings) { Self.item(from: $0) }
    }

    /// How many items a scope holds, for "Newest 300 of 6,200 checked" and "64 items in r/swift".
    public func itemCount(in scope: ItemScope = .all) throws -> Int {
        switch scope {
        case .all:
            return try connection.scalar("SELECT COUNT(*) FROM item WHERE \(Self.liveItemFilter)") { $0.int(0) }
        case let .source(id):
            return try connection.scalar("SELECT COUNT(*) FROM item WHERE \(Self.liveItemFilter) AND source_id = ?", [id]) { $0.int(0) }
        }
    }

    // MARK: Row mapping

    /// Every item query selects exactly these columns in this order, so one function reads them all.
    static func itemColumns(withContent: Bool) -> String {
        "id, source_id, guid, url, title, snippet, published, fetched, opened, read, repo_name, " + (withContent ? "content" : "NULL")
    }

    static func item(from row: Row) -> Item {
        Item(id: row.int64(0), sourceID: row.int64(1), guid: row.string(2), url: row.optionalURL(3), title: row.string(4),
             snippet: row.string(5), content: row.optionalString(11), published: row.optionalDate(6), fetched: row.date(7),
             opened: row.optionalDate(8), read: row.bool(9), repoName: row.optionalString(10))
    }
}
