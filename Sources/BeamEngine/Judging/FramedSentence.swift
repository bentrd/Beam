import BeamJev
import BeamModels

/// One sentence ready to be sent and to be looked up: its frame, and the hash that keys its cached answers.
///
/// Framing and hashing are pure and repeated for every item, so they are done once per run and carried here.
struct FramedSentence: Sendable, Hashable {
    let sentence: Sentence
    /// The exact proposition sent to the judge.
    let frame: String
    /// sha256 of the frame: the sentence half of the judgment cache key.
    let hash: String

    private init(_ sentence: Sentence, frame: String) {
        self.sentence = sentence
        self.frame = frame
        self.hash = sentence.hash(frame: frame)
    }

    /// For a title and a snippet in a list.
    static func item(_ sentence: Sentence) -> FramedSentence { FramedSentence(sentence, frame: sentence.itemFrame()) }

    /// For one paragraph, sent with its article title and section heading as context.
    static func passage(_ sentence: Sentence) -> FramedSentence { FramedSentence(sentence, frame: sentence.passageFrame()) }

    /// A probability as it may be banded for this sentence: an unjudgeable sentence never reaches "found".
    /// The raw answer is what gets cached; only what is shown is capped.
    func cappedForList(_ probability: Double) -> Double { sentence.cappedForList(probability) }
    func cappedForPassage(_ probability: Double) -> Double { sentence.cappedForPassage(probability) }
}
