import BeamExtract
import BeamModels
import BeamStore
import Foundation

/// The text of an article: the store's copy when there is one, else the page, extracted and then kept.
///
/// One place for the rule, because both the reader and pre-judging need it and they must agree: two copies of
/// "when is a failure worth another try" would eventually disagree and fetch the same dead link twice.
struct ArticleStore {
    let context: EngineContext

    /// - Parameter force: skip the stored copy (Retry on an article that could not be read).
    func article(for item: Item, force: Bool = false) async -> ArticleContent {
        if !force, let stored = try? await context.database.article(itemID: item.id) {
            if case .unavailable = stored.content {
                // A failure is remembered for an hour only: a site that was down at lunch should read by dinner,
                // but reopening a dead link must not fetch it again every time.
                if context.now().timeIntervalSince(stored.fetched) < Windows.failedArticleLife { return stored.content }
            } else {
                return stored.content
            }
        }
        let content = await context.articles.load(item: item, sourceKind: context.sourceKind(item.sourceID))
        // A cancelled load reports "unavailable" too; caching that would show a failure that never happened.
        guard !Task.isCancelled else { return content }
        do {
            try await context.database.putArticle(content, itemID: item.id, fetched: context.now())
        } catch {
            EngineLog.failure("storing the article of item \(item.id)", error)
        }
        return content
    }
}
