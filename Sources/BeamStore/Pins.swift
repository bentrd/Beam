import BeamModels
import Foundation

extension Database {
    private static let pinColumns = "id, sentence, position, created, last_viewed"

    /// The pins in sidebar order, which is also the ⌘1…⌘9 order.
    public func pins() throws -> [Pin] {
        try connection.query("SELECT \(Self.pinColumns) FROM pin WHERE removed IS NULL ORDER BY position, id") { Self.pin(from: $0) }
    }

    public func pin(id: Int64) throws -> Pin? {
        try connection.first("SELECT \(Self.pinColumns) FROM pin WHERE id = ? AND removed IS NULL", [id]) { Self.pin(from: $0) }
    }

    /// Pins a sentence at the end of the list. At most `Pin.maximum` pins exist, one per ⌘-digit.
    /// Re-pinning a sentence unpinned earlier in this session revives that pin, with its last-viewed date.
    public func addPin(sentence: String, at date: Date = Date()) throws -> PinOutcome {
        try connection.transaction {
            let existing = try connection.first("SELECT id, removed IS NOT NULL FROM pin WHERE sentence = ?", [sentence]) {
                (id: $0.int64(0), isRemoved: $0.bool(1))
            }
            if let existing, !existing.isRemoved, let pin = try pin(id: existing.id) { return .alreadyPinned(pin) }

            let position = try connection.nextPosition(in: .pin)
            guard position < Pin.maximum else { return .limitReached }

            let id: Int64
            if let existing {
                try connection.execute("UPDATE pin SET position = ?, removed = NULL WHERE id = ?", [position, existing.id])
                id = existing.id
            } else {
                try connection.execute("INSERT INTO pin(sentence, position, created) VALUES (?, ?, ?)", [sentence, position, date])
                id = try connection.lastInsertedID
            }
            guard let pinned = try pin(id: id) else { throw StoreError.notFound("pin \(id) after insert") }
            return .pinned(pinned)
        }
    }

    /// Hides the pin, keeping it for Undo until the database next opens. Returns the pin as it was, or nil when there is no such live pin.
    @discardableResult
    public func removePin(id: Int64, at date: Date = Date()) throws -> Pin? {
        try connection.transaction {
            guard let removed = try pin(id: id) else { return nil }
            _ = try connection.softDelete(id, at: date, in: .pin)
            return removed
        }
    }

    /// Undo for Remove Pin: the pin returns to its former place. `.limitReached` when nine others took the room meanwhile;
    /// `.alreadyPinned` when it was never gone. Throws `notFound` once the removal has become permanent.
    public func restorePin(id: Int64) throws -> PinOutcome {
        try connection.transaction {
            let isRemoved = try connection.first("SELECT removed IS NOT NULL FROM pin WHERE id = ?", [id]) { $0.bool(0) }
            guard let isRemoved else { throw StoreError.notFound("pin \(id)") }
            if isRemoved {
                guard try connection.nextPosition(in: .pin) < Pin.maximum else { return .limitReached }
                try connection.restore(id, in: .pin)
            }
            guard let pin = try pin(id: id) else { throw StoreError.notFound("pin \(id)") }
            return isRemoved ? .pinned(pin) : .alreadyPinned(pin)
        }
    }

    /// Move Pin Up (negative offset) / Move Pin Down, stopping at the ends.
    public func movePin(id: Int64, by offset: Int) throws {
        guard try connection.move(id, by: offset, in: .pin) else { throw StoreError.notFound("pin \(id)") }
    }

    /// Leaving a pin marks it viewed: its badge counts what was found after this moment.
    public func markPinViewed(id: Int64, at date: Date = Date()) throws {
        let changed = try connection.execute("UPDATE pin SET last_viewed = ? WHERE id = ? AND removed IS NULL", [date, id])
        guard changed == 1 else { throw StoreError.notFound("pin \(id)") }
    }

    private static func pin(from row: Row) -> Pin {
        Pin(id: row.int64(0), sentence: row.string(1), position: row.int(2), created: row.date(3), lastViewed: row.optionalDate(4))
    }
}
