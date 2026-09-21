import BeamModels
import BeamStore
import Foundation

/// Every answer Beam has ever had, keyed by what was judged rather than by what row it was on:
/// (text hash, framed sentence hash, model). Answers are repeatable (EVIDENCE.md), so serving them from
/// here is truthful, and it is why a repeated search costs nothing.
///
/// Writes are buffered: 300 answers in a second become a handful of transactions instead of three hundred,
/// and nothing waits on the disk. Buffered answers are readable before they are stored, so a run that follows
/// another closely still sees them.
actor JudgmentCache {
    /// Enough to make writes rare, small enough that a crash loses only a fraction of a cent of judging.
    private static let batch = 32

    private let database: Database
    private var buffer: [String: CachedJudgment] = [:]
    private var writer: Task<Void, Never>?
    /// The last store failure, kept so a run can say the truth rather than silently forgetting answers.
    private(set) var writeFailure: String?

    init(database: Database) {
        self.database = database
    }

    /// The probabilities known for these texts, as `[text hash: [sentence hash: probability]]`.
    /// Texts never judged are simply absent: the caller shows those as "not checked", never as "nothing".
    func answers(textHashes: [String], sentences: [FramedSentence], model: String?) async -> [String: [String: Double]] {
        guard let model, !model.isEmpty, !textHashes.isEmpty, !sentences.isEmpty else { return [:] }
        var found: [String: [String: Double]] = [:]
        for sentence in sentences {
            let stored: [String: Double]
            do {
                stored = try await database.judgments(sentenceHash: sentence.hash, model: model, textHashes: textHashes)
            } catch {
                // A cache that cannot be read is not a wrong answer: the run judges again and says so if that fails.
                continue
            }
            for (textHash, probability) in stored { found[textHash, default: [:]][sentence.hash] = probability }
        }
        for judgment in buffer.values where judgment.model == model {
            found[judgment.textHash, default: [:]][judgment.sentenceHash] = judgment.probability
        }
        return found
    }

    /// Remembers one answer. It is readable at once and stored soon.
    func remember(textHash: String, sentenceHash: String, model: String, probability: Double, at date: Date) {
        buffer["\(textHash)\n\(sentenceHash)\n\(model)"] = CachedJudgment(textHash: textHash, sentenceHash: sentenceHash,
                                                                          model: model, probability: probability, at: date)
        if buffer.count >= Self.batch { scheduleWrite() }
    }

    /// Stores everything buffered. A run calls this when it settles, and the app before it quits.
    func flush() async {
        scheduleWrite()
        await writer?.value
    }

    private func scheduleWrite() {
        guard writer == nil, !buffer.isEmpty else { return }
        writer = Task { await self.writeUntilEmpty() }
    }

    private func writeUntilEmpty() async {
        defer { writer = nil }
        while !buffer.isEmpty {
            let batch = Array(buffer.values)
            do {
                try await database.putJudgments(batch)
                writeFailure = nil
            } catch {
                // Keeping them buffered would grow without bound; the answers are still in the run's own state.
                writeFailure = "Couldn't store judgments: \(error)"
            }
            for judgment in batch { buffer.removeValue(forKey: "\(judgment.textHash)\n\(judgment.sentenceHash)\n\(judgment.model)") }
        }
    }
}
