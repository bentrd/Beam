import BeamModels
import Foundation

/// Unread counts for the sidebar badges.
public struct UnreadCounts: Hashable, Sendable {
    /// The All Items badge.
    public var total: Int
    /// By source id. A source with nothing unread is absent, as its badge is.
    public var bySource: [Int64: Int]

    public init(total: Int = 0, bySource: [Int64: Int] = [:]) {
        self.total = total; self.bySource = bySource
    }
}

extension Database {
    /// The item was opened in the reader (or the browser): it becomes read, and `opened` records when.
    /// Arrowing past an item never calls this.
    public func markOpened(itemID: Int64, at date: Date = Date()) throws {
        let changed = try connection.execute("UPDATE item SET opened = ?, read = 1 WHERE id = ?", [date, itemID])
        guard changed == 1 else { throw StoreError.notFound("item \(itemID)") }
    }

    /// Mark as Read / Mark as Unread. Returns the items whose state actually changed, which is exactly what Undo must flip back.
    /// `opened` is left alone: it records the last open, not the read state.
    @discardableResult
    public func setRead(_ read: Bool, itemIDs: [Int64]) throws -> [Int64] {
        guard !itemIDs.isEmpty else { return [] }
        // One statement for any number of ids: the list travels as a JSON array instead of a variable count of `?`.
        let list = "[" + itemIDs.map(String.init).joined(separator: ",") + "]"
        return try connection.query("UPDATE item SET read = ?1 WHERE read <> ?1 AND id IN (SELECT value FROM json_each(?2)) RETURNING id",
                                    [read, list]) { $0.int64(0) }
    }

    /// Mark All as Read. Returns the items that were unread, so Undo is `setRead(false, itemIDs:)` with this result.
    @discardableResult
    public func markAllRead(in scope: ItemScope) throws -> [Int64] {
        switch scope {
        case .all:
            return try connection.query("UPDATE item SET read = 1 WHERE read = 0 AND \(Self.liveItemFilter) RETURNING id") { $0.int64(0) }
        case let .source(id):
            return try connection.query("UPDATE item SET read = 1 WHERE read = 0 AND source_id = ? AND \(Self.liveItemFilter) RETURNING id",
                                        [id]) { $0.int64(0) }
        }
    }

    /// One pass over the partial index of unread items, so it stays a few milliseconds at 50,000 items.
    public func unreadCounts() throws -> UnreadCounts {
        let rows = try connection.query("SELECT source_id, COUNT(*) FROM item WHERE read = 0 AND \(Self.liveItemFilter) GROUP BY source_id") {
            (sourceID: $0.int64(0), count: $0.int(1))
        }
        var counts = UnreadCounts()
        for row in rows {
            counts.bySource[row.sourceID] = row.count
            counts.total += row.count
        }
        return counts
    }
}
