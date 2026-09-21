import BeamJev
import BeamModels
import Foundation

/// Settings ▸ "Light up top results before I open them", off by default.
///
/// When Ben allows it, the top three found rows of a settled search have their first 40 paragraphs judged ahead,
/// so opening one is lit before the eye settles. It is off by default because it sends paragraphs of articles
/// nobody has opened; when it is on, the key sheet's disclosure says so.
@MainActor
final class Prejudge {
    private let context: EngineContext
    private var task: Task<Void, Never>?

    init(context: EngineContext) {
        self.context = context
    }

    /// Starts over: a new run of the list replaces whatever was being judged ahead.
    func start(items: [Item], sentence: Sentence) {
        cancel()
        guard !items.isEmpty, !sentence.isEmpty, context.canSend else { return }
        let top = Array(items.prefix(Windows.prejudgedRows))
        task = Task { [weak self] in await self?.judge(top, sentence: sentence) }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    private func judge(_ items: [Item], sentence: Sentence) async {
        let framed = FramedSentence.passage(sentence)
        let articles = ArticleStore(context: context)
        for item in items {
            guard !Task.isCancelled else { return }
            // The list leaves `content` out of its rows; the loader needs it to use a feed's own text.
            guard let full = try? await context.database.item(id: item.id) else { continue }
            guard case let .ready(passages, _, _) = await articles.article(for: full) else { continue }

            let judgeable = passages.indices.filter { passages[$0].isJudgeable }.prefix(Windows.prejudgedPassages)
            let targets = judgeable.map { index in
                JudgeTarget(id: index, textHash: passages[index].textHash,
                            state: ["article": full.title, "section_heading": passages[index].section, "passage": passages[index].text])
            }
            guard !targets.isEmpty else { continue }
            let known = await context.cache.answers(textHashes: targets.map(\.textHash), sentences: [framed],
                                                    model: context.models.current)
            // Pre-judging is not reading: it spends from the search's share of the day, never the reader's reserve.
            let outcome = await context.passagePass(for: .ranking)
                .run(targets: targets, sentences: [framed], known: known, answered: { _, _ in }, failed: { _ in })
            guard outcome == .completed else { return }
        }
    }
}
