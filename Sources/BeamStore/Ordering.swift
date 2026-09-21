import Foundation

/// The two user-ordered tables. Both keep live rows at positions 0..<n with no gaps, and both soft-delete,
/// so ordering, removal and restoration are written once here.
enum OrderedTable: String {
    case source, pin
}

extension Connection {
    func liveIDs(in table: OrderedTable) throws -> [Int64] {
        try query("SELECT id FROM \(table.rawValue) WHERE removed IS NULL ORDER BY position, id") { $0.int64(0) }
    }

    /// Rewrites positions to match `ids`. The lists are tiny (nine pins, tens of sources), so clarity beats a minimal update.
    func writePositions(_ ids: [Int64], in table: OrderedTable) throws {
        for (position, id) in ids.enumerated() {
            try execute("UPDATE \(table.rawValue) SET position = ? WHERE id = ?", [position, id])
        }
    }

    func nextPosition(in table: OrderedTable) throws -> Int {
        try scalar("SELECT COUNT(*) FROM \(table.rawValue) WHERE removed IS NULL") { $0.int(0) }
    }

    /// Moves a live row up (negative) or down, stopping at the ends. Returns false when the row is not live.
    func move(_ id: Int64, by offset: Int, in table: OrderedTable) throws -> Bool {
        try transaction {
            var ids = try liveIDs(in: table)
            guard let index = ids.firstIndex(of: id) else { return false }
            let target = min(max(index + offset, 0), ids.count - 1)
            ids.remove(at: index)
            ids.insert(id, at: target)
            try writePositions(ids, in: table)
            return true
        }
    }

    /// Hides a live row and closes the gap it leaves. The row keeps its old position so Undo can put it back there.
    /// Returns false when the row is not live.
    func softDelete(_ id: Int64, at date: Date, in table: OrderedTable) throws -> Bool {
        try transaction {
            let changed = try execute("UPDATE \(table.rawValue) SET removed = ? WHERE id = ? AND removed IS NULL", [date, id])
            guard changed == 1 else { return false }
            try writePositions(try liveIDs(in: table), in: table)
            return true
        }
    }

    /// Brings a soft-deleted row back where it was (or at the end, if the list has since become shorter).
    /// Call inside a transaction, after checking the row is currently removed.
    func restore(_ id: Int64, in table: OrderedTable) throws {
        let formerPosition = try scalar("SELECT position FROM \(table.rawValue) WHERE id = ?", [id]) { $0.int(0) }
        var ids = try liveIDs(in: table)
        ids.insert(id, at: min(max(formerPosition, 0), ids.count))
        try execute("UPDATE \(table.rawValue) SET removed = NULL WHERE id = ?", [id])
        try writePositions(ids, in: table)
    }
}
