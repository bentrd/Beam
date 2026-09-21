import BeamModels
import BeamUI
import Foundation

/// Stands in for the judge. The two captured sentences answer with their measured probabilities;
/// any other question is matched by its words, which is enough to exercise Find by Meaning in a demo.
struct DemoJudge {
    private let captured: [String: [Int: Double]]

    init(fixtures: [ReaderFixture]) {
        captured = Dictionary(fixtures.map { (Self.normalise($0.sentence), $0.probabilities) }, uniquingKeysWith: { first, _ in first })
    }

    func probability(of passage: Passage, at index: Int, about sentence: String) -> Double {
        if let measured = captured[Self.normalise(sentence)] { return measured[index] ?? 0.02 }
        let words = Self.normalise(sentence).split(separator: " ").filter { $0.count > 3 }
        guard !words.isEmpty else { return 0.02 }
        let text = passage.text.lowercased()
        let matched = words.filter { text.contains($0) }.count
        if matched == words.count { return 0.9 }
        return matched > 0 ? 0.5 : 0.02
    }

    private static func normalise(_ sentence: String) -> String {
        sentence.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
