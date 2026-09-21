import BeamExtract
import BeamJev
import BeamModels
import BeamStore
import Foundation

/// The middle of the engine: the services every run needs, and the small pieces of state a run reads but never owns.
///
/// The list and the reader are long-lived machines with their own state; they share this rather than each other.
/// Everything here is main-actor, so a run reads a source title or the key status without a hop.
@MainActor
final class EngineContext {
    let database: Database
    let judge: Judge
    let spend: SpendMeter
    let cache: JudgmentCache
    let models: ModelRegistry
    let articles: ArticleLoader
    let maxInFlight: Int
    let now: @Sendable () -> Date

    /// The sidebar's sources, in order. Kept here because rows carry their source's title and the reader its kind.
    var sources: [Source] = []
    /// The pins, in ⌘1…⌘9 order. Every list run carries them as extra questions, which is what keeps them current.
    var pins: [Pin] = []
    /// What Beam believes about the key right now. A run that is refused updates it, so the next foot is right.
    var keyStatus: KeyStatus = .missing
    /// True while sources are being fetched: an empty list then says "Getting your sources" rather than "No items yet."
    var isRefreshing = false

    init(database: Database, judge: Judge, spend: SpendMeter, cache: JudgmentCache, models: ModelRegistry,
         articles: ArticleLoader, maxInFlight: Int, now: @escaping @Sendable () -> Date) {
        self.database = database
        self.judge = judge
        self.spend = spend
        self.cache = cache
        self.models = models
        self.articles = articles
        self.maxInFlight = maxInFlight
        self.now = now
    }

    func source(_ id: Int64) -> Source? { sources.first { $0.id == id } }
    func sourceTitle(_ id: Int64) -> String { source(id)?.title ?? "" }
    func sourceKind(_ id: Int64) -> SourceKind { source(id)?.kind ?? .feed }

    /// Whether a request is worth sending. A missing or rejected key is a state of the app: trying again cannot
    /// change it, and Beam must send nothing at all without a key. Everything else is worth one attempt, so that
    /// a Mac that was offline a minute ago is not told it still is.
    var canSend: Bool { keyStatus != .missing && keyStatus != .rejected }

    /// The sentences every ranking request carries: the one being searched, and every pin.
    /// One request per item, all of them as parallel Nouls (EVIDENCE.md).
    func rankingSentences(searching sentence: Sentence?) -> [FramedSentence] {
        var sentences: [FramedSentence] = []
        if let sentence, !sentence.isEmpty { sentences.append(.item(sentence)) }
        for pin in pins {
            let pinned = Sentence(pin.sentence)
            guard !pinned.isEmpty else { continue }
            let framed = FramedSentence.item(pinned)
            if !sentences.contains(framed) { sentences.append(framed) }
        }
        return sentences
    }

    func itemPass() -> JudgePass<Int64> {
        JudgePass(judge: judge, cache: cache, models: models, purpose: .ranking, now: now)
    }

    /// The reader's own pass. `.reading` spends the last $0.05 of the day, which is reserved for it: being unable
    /// to light the article you just opened is worse than a search that stopped early.
    func passagePass(for purpose: SpendMeter.Purpose) -> JudgePass<Int> {
        JudgePass(judge: judge, cache: cache, models: models, purpose: purpose, now: now)
    }
}
