import Foundation

/// The answer to one request: one piece of state judged against every frame at once.
public struct Judgments: Equatable, Sendable {
    /// One per frame, in the order given. nil where the answer was missing or invalid:
    /// that frame is "not checked", never "nothing".
    public let probabilities: [Double?]
    /// Input tokens billed for the request, already added to the spend meter.
    public let tokens: Int
    /// The model that answered ("jev-1.13.0"), the third part of the judgment cache key.
    public let model: String

    public init(probabilities: [Double?], tokens: Int, model: String) {
        self.probabilities = probabilities; self.tokens = tokens; self.model = model
    }
}

/// The gate every number from the service passes before Beam ranks or tints with it.
public enum Probability {
    /// nil unless `raw` is a real number (not a boolean, not a string), finite, and within 0...1.
    public static func validated(_ raw: Any?) -> Double? {
        guard let number = Wire.number(raw) else { return nil }
        let value = number.doubleValue
        return value.isFinite && (0...1).contains(value) ? value : nil
    }
}

/// The JSON of `POST /v1/systemone`, for Nouls only: Beam asks nothing else.
enum Wire {
    /// Question ids are for code and never reach the model, so position is enough.
    static func questionID(_ index: Int) -> String { "q\(index)" }

    static func body(model: String, state: [String: String], frames: [String]) throws -> Data {
        var questions: [String: Any] = [:]
        for (index, frame) in frames.enumerated() {
            questions[questionID(index)] = ["type": "noul", "instructions": frame]
        }
        let body: [String: Any] = ["model": model, "state": state, "questions": questions]
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }

    static func judgments(from data: Data, frameCount: Int) throws -> Judgments {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let answers = root["answers"] as? [String: Any],
              let model = root["model"] as? String, !model.isEmpty,
              let usage = root["usage"] as? [String: Any],
              let count = number(usage["input_tokens"]),
              let tokens = Int(exactly: count.doubleValue), tokens >= 0
        else { throw JevError.malformedResponse }

        let probabilities = (0..<frameCount).map { index -> Double? in
            guard let answer = answers[questionID(index)] as? [String: Any], answer["type"] as? String == "noul" else { return nil }
            return Probability.validated(answer["noul"])
        }
        return Judgments(probabilities: probabilities, tokens: tokens, model: model)
    }

    /// JSON `true` arrives as an NSNumber too, and would otherwise read as 1.0.
    static func number(_ raw: Any?) -> NSNumber? {
        guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number
    }
}
