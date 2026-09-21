import Foundation

/// Stands in for the judge when a sentence was never really sent: a deterministic word-overlap score, shaped so that
/// the list and passage bands of `Bands` all occur. It exists to exercise the interface, not to be right.
enum FakeJudge {
    /// The cache key for a sentence: what the user typed, trimmed, whitespace collapsed, lowercased.
    static func normalise(_ sentence: String) -> String {
        sentence.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func probability(of text: String, about sentence: String) -> Double {
        let wanted = stems(sentence)
        let jitter = Double(hash(text + "\u{1F}" + normalise(sentence)) % 1_000) / 1_000      // 0..<1, stable across launches
        guard !wanted.isEmpty else { return 0.02 + jitter * 0.1 }
        let present = stems(text)
        let matched = wanted.filter { stem in present.contains { matches($0, stem) } }
        let share = Double(matched.count) / Double(wanted.count)
        guard share > 0 else { return 0.02 + jitter * 0.12 }
        return min(0.05 + 0.9 * pow(share, 1.6) + (jitter - 0.5) * 0.06, 0.98)
    }

    /// Equal stems, or one the prefix of the other once both are long enough for that to mean something.
    private static func matches(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        return a.count > 4 && b.count > 4 && (a.hasPrefix(b) || b.hasPrefix(a))
    }

    /// True when the sentence asks for something the judge cannot weigh: an exclusion, an amount or a date.
    static func asksForExclusionAmountOrDate(_ sentence: String) -> Bool {
        let words = Set(normalise(sentence).split { !$0.isLetter && !$0.isNumber && $0 != "-" }.map(String.init))
        if !words.isDisjoint(with: unjudgeable) { return true }
        return words.contains { $0.allSatisfy(\.isNumber) }
    }

    private static let unjudgeable: Set<String> = ["not", "no", "without", "except", "excluding", "today", "yesterday", "tomorrow",
                                                   "since", "before", "after", "cheaper", "under", "over"]

    private static let ignored: Set<String> = ["a", "an", "the", "of", "on", "in", "for", "to", "and", "or", "about", "with", "is", "are",
                                               "my", "your", "that", "this", "things", "stuff", "how", "what", "can", "i",
                                               "sur", "la", "le", "les", "et", "de", "des", "du", "un", "une", "trucs"]

    private static func stems(_ text: String) -> Set<String> {
        var result: Set<String> = []
        for piece in text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            let word = String(piece)
            guard word.count > 1, !ignored.contains(word) else { continue }
            result.insert(word.count > 3 && word.hasSuffix("s") ? String(word.dropLast()) : word)
        }
        return result
    }

    /// FNV-1a: `hashValue` is seeded per process and would reshuffle results on every launch.
    static func hash(_ string: String) -> UInt64 {
        string.utf8.reduce(14_695_981_039_346_656_037) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
    }
}
