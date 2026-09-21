import Foundation

/// One typed judgment to ask about a piece of state.
public enum Question: Sendable, Hashable, Codable {
    /// Exactly one of a small set of described options. Works best with 3–6.
    case choice(instructions: String, options: [Option])
    /// A position along an ordered rubric of described levels (2–10).
    case score(instructions: String, levels: [String])
    /// The probability that a plain-language proposition holds.
    case noul(instructions: String)

    public struct Option: Sendable, Hashable, Codable {
        public var key: String
        public var what: String
        public init(_ key: String, _ what: String) {
            self.key = key
            self.what = what
        }
    }

    /// The wire format expected by `POST /v1/systemone`.
    var wire: [String: Any] {
        switch self {
        case let .choice(instructions, options):
            var criteria: [String: Any] = [:]
            for option in options { criteria[option.key] = option.what }
            return ["type": "choice", "instructions": instructions, "criteria": criteria]
        case let .score(instructions, levels):
            return ["type": "score", "instructions": instructions, "criteria": levels]
        case let .noul(instructions):
            return ["type": "noul", "instructions": instructions]
        }
    }
}

/// A typed answer with its uncertainty.
public enum Answer: Sendable, Hashable, Codable {
    case choice(label: String, probabilities: [String: Double], confidence: Double)
    /// `value` is the probability-weighted level index; `probabilities[i]` is P(level i).
    case score(value: Double, probabilities: [Double], confidence: Double)
    case noul(Double)

    /// A single 0…1 number suitable for sorting and thresholds.
    public func unit(levels: Int = 2) -> Double {
        switch self {
        case let .noul(p): return p
        case let .score(value, probabilities, _):
            let top = Double(max(probabilities.count, levels) - 1)
            return top > 0 ? value / top : 0
        case let .choice(_, _, confidence): return confidence
        }
    }

    /// How sure the model is, 0…1. For a Noul this is its distance from a coin flip.
    public var certainty: Double {
        switch self {
        case let .noul(p): return abs(p - 0.5) * 2
        case let .score(_, _, confidence), let .choice(_, _, confidence): return confidence
        }
    }
}
