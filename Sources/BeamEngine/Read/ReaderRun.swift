import BeamJev
import BeamModels
import Foundation

/// One open article: what was opened, what was extracted, and what is known about its paragraphs.
///
/// Answers are kept per sentence, so closing Find by Meaning hands the carried sentence's marks back from
/// memory at once, with nothing sent (DESIGN.md section 4).
struct ReaderRun {
    let itemID: Int64
    let continuation: AsyncStream<ReaderSnapshot>.Continuation
    var item: Item
    var sourceTitle: String
    var sourceKind: SourceKind

    var phase = ReaderPhase.loading
    var passages: [Passage] = []
    /// `Passage.textHash` by index, for judgeable passages only. Computed once with the article.
    var hashes: [Int: String] = [:]
    var images = 0
    var tables = 0

    /// The sentence the row carried in from the list or the pin.
    var carried: Sentence?
    /// Find by Meaning. While it is set it is the sentence the article is lit for.
    var find: Sentence?
    /// Raw probabilities by passage index, per framed sentence hash.
    var answers: [String: [Int: Double]] = [:]
    var failed: Set<Int> = []

    /// What the reader says is on screen. Until it says, the top of the article is assumed.
    var viewport: ClosedRange<Int> = 0...14
    var isRunning = false
    /// True once the article has been loading for more than a second: only then is the wait worth a sentence.
    var isSlowToLoad = false
    /// Sticky for the run: a share that dips back below the line mid-run must not make the marks flash in.
    var isSaturated = false
    var outcome: JudgePassOutcome?
    /// True when the row itself was found on its title: "Matched by title. Nothing found in 84 paragraphs checked".
    var matchedByTitle = false
    var task: Task<Void, Never>?

    var sentence: Sentence? { find ?? carried }
    var isFindActive: Bool { find != nil }

    /// Headings and code are shown but never judged.
    var judgeable: [Int] { passages.indices.filter { passages[$0].isJudgeable } }
    var hasCode: Bool { passages.contains { $0.kind == .code } }

    /// The answers of the sentence the article is currently lit for.
    func answers(for framed: FramedSentence?) -> [Int: Double] {
        guard let framed else { return [:] }
        return answers[framed.hash] ?? [:]
    }
}
