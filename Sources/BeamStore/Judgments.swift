import BeamModels
import Foundation

/// One cached answer: how probable the judge found one framed sentence for one text.
///
/// The key is content, never a row id: `textHash` is `Item.textHash` or `Passage.textHash`, `sentenceHash` covers the
/// framed sentence, and `model` is the model id the answer came from. Edit the text, reword the frame or change the model
/// and the old answer simply stops matching. Answers are repeatable (measured), so serving them from here is truthful.
public struct CachedJudgment: Hashable, Sendable {
    public var textHash: String
    public var sentenceHash: String
    public var model: String
    public var probability: Double
    public var at: Date

    public init(textHash: String, sentenceHash: String, model: String, probability: Double, at: Date = Date()) {
        self.textHash = textHash; self.sentenceHash = sentenceHash; self.model = model; self.probability = probability; self.at = at
    }
}

extension Database {
    /// The cached probabilities of one sentence for many texts, in one query. Texts never judged are absent from the result:
    /// the caller shows those as "not checked", never as "nothing".
    public func judgments(sentenceHash: String, model: String, textHashes: [String]) throws -> [String: Double] {
        guard !textHashes.isEmpty else { return [:] }
        // The hashes travel as one JSON array, so 300 or 1,500 of them reuse the same prepared statement.
        let list = String(decoding: try JSONEncoder().encode(textHashes), as: UTF8.self)
        let rows = try connection.query("""
            SELECT text_hash, p FROM judgment
            WHERE sentence_hash = ? AND model = ? AND text_hash IN (SELECT value FROM json_each(?))
            """, [sentenceHash, model, list]) { (textHash: $0.string(0), probability: $0.double(1)) }
        return Dictionary(rows.map { ($0.textHash, $0.probability) }, uniquingKeysWith: { first, _ in first })
    }

    /// Stores a batch of answers in one transaction. A repeated key overwrites: same text, same sentence, same model, same answer.
    /// A probability that is not a finite number in 0...1 is refused here, whatever the caller validated.
    public func putJudgments(_ judgments: [CachedJudgment]) throws {
        guard !judgments.isEmpty else { return }
        if let bad = judgments.first(where: { !($0.probability >= 0 && $0.probability <= 1) }) {
            throw StoreError.invalid("probability \(bad.probability) for text \(bad.textHash)")
        }
        try connection.transaction {
            for judgment in judgments {
                try connection.execute("""
                    INSERT INTO judgment(text_hash, sentence_hash, model, p, at) VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(text_hash, sentence_hash, model) DO UPDATE SET p = excluded.p, at = excluded.at
                    """, [judgment.textHash, judgment.sentenceHash, judgment.model, judgment.probability, judgment.at])
            }
        }
    }
}
