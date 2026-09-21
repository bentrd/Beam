import Foundation

/// Beam has no confirmation alerts: Undo is the safety net (DESIGN.md section 4).
///
/// One stack for Remove Pin, Remove Source and Mark All as Read, newest first, living until Beam quits —
/// the same life as the store's soft deletes, which is what a restore actually revives.
@MainActor
final class UndoStack {
    /// A menu title ("Undo Remove Pin") and the work that puts things back.
    struct Entry {
        let title: String
        let restore: () async -> Void
    }

    private var entries: [Entry] = []

    var title: String? { entries.last?.title }

    func push(_ title: String, restore: @escaping () async -> Void) {
        entries.append(Entry(title: title, restore: restore))
    }

    /// Undoes the newest entry and returns its menu title, or nil when there is nothing to undo.
    func undo() async -> String? {
        guard let entry = entries.popLast() else { return nil }
        await entry.restore()
        return entry.title
    }
}

/// Something a main-actor callback can count. A judging pass reports its failures one by one, and a captured
/// variable cannot be added to from a callback that may arrive from anywhere.
@MainActor
final class Tally {
    private(set) var count = 0
    func add() { count += 1 }
}
