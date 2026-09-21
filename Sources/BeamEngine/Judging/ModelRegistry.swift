import BeamStore
import Foundation

/// Which model's opinions the cache is holding.
///
/// Requests ask for "jev-latest"; only the answer says which model actually replied, and that id is the third
/// part of every cache key. It is remembered in the store so that a launch with no network can still read back
/// yesterday's answers, and it moves on by itself when TypeSafe ships a new model: older answers then stop
/// matching, which is exactly right, because they are a different model's opinion.
@MainActor
final class ModelRegistry {
    private static let metaKey = "judge.model"

    private let database: Database
    private(set) var current: String?

    init(database: Database) {
        self.database = database
    }

    func load() async {
        current = try? await database.meta(Self.metaKey)
    }

    /// Records the model an answer came from. Writing is fire-and-forget: the id is a cache hint, and losing it
    /// costs one re-judging pass, never a wrong answer.
    func saw(_ model: String) {
        guard !model.isEmpty, model != current else { return }
        current = model
        let database = self.database
        Task { try? await database.setMeta(Self.metaKey, to: model) }
    }
}
