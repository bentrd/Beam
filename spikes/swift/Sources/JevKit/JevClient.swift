import Foundation

public struct JevResponse: Sendable {
    public let answers: [String: Answer]
    public let inputTokens: Int
    public let model: String
    public let milliseconds: Double
}

public enum JevError: Error, LocalizedError, Sendable {
    case missingKey
    case unauthorized
    case rejected(String)
    case overloaded
    case transport(String)
    case malformed

    public var errorDescription: String? {
        switch self {
        case .missingKey: "No TypeSafe API key is configured."
        case .unauthorized: "The TypeSafe API key was rejected."
        case let .rejected(why): "The request was rejected: \(why)"
        case .overloaded: "The service is busy. Try again in a moment."
        case let .transport(why): why
        case .malformed: "The service returned something unexpected."
        }
    }
}

/// A thin, retrying client for TypeSafe's System One endpoint.
public struct JevClient: Sendable {
    public static let endpoint = URL(string: "https://api.typesafe.ai/v1/systemone")!

    private let key: String
    private let session: URLSession
    private let model: String

    public init(key: String, model: String = "jev-latest") {
        self.key = key
        self.model = model
        let config = URLSessionConfiguration.ephemeral
        config.httpMaximumConnectionsPerHost = 64
        config.timeoutIntervalForRequest = 20
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }

    /// Ask several independent questions about one piece of state in a single round trip.
    public func ask(state: Any, questions: [String: Question]) async throws -> JevResponse {
        guard !key.isEmpty else { throw JevError.missingKey }
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": model,
            "state": state,
            "questions": questions.mapValues(\.wire),
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])

        var delay = 0.4
        for attempt in 0..<5 {
            let started = ContinuousClock.now
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: request)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if attempt == 4 { throw JevError.transport(error.localizedDescription) }
                try await Task.sleep(for: .seconds(delay))
                delay *= 2
                continue
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            switch status {
            case 200:
                let elapsed = ContinuousClock.now - started
                let ms = Double(elapsed.components.seconds) * 1000
                    + Double(elapsed.components.attoseconds) / 1e15
                return try Self.decode(data, milliseconds: ms)
            case 401, 403:
                throw JevError.unauthorized
            case 429, 529, 500...599:
                if attempt == 4 { throw JevError.overloaded }
                try await Task.sleep(for: .seconds(delay))
                delay *= 2
            default:
                throw JevError.rejected(String(data: data.prefix(300), encoding: .utf8) ?? "status \(status)")
            }
        }
        throw JevError.overloaded
    }

    static func decode(_ data: Data, milliseconds: Double) throws -> JevResponse {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rawAnswers = root["answers"] as? [String: [String: Any]]
        else { throw JevError.malformed }

        var answers: [String: Answer] = [:]
        for (id, raw) in rawAnswers {
            switch raw["type"] as? String {
            case "noul":
                if let p = raw["noul"] as? Double { answers[id] = .noul(p) }
            case "choice":
                if let label = raw["choice"] as? String {
                    answers[id] = .choice(
                        label: label,
                        probabilities: (raw["probabilities"] as? [String: Double]) ?? [:],
                        confidence: (raw["confidence"] as? Double) ?? 0)
                }
            case "score":
                if let value = raw["score"] as? Double {
                    let table = (raw["probabilities"] as? [String: Double]) ?? [:]
                    let ordered = table.keys.compactMap(Int.init).sorted().map { table[String($0)] ?? 0 }
                    answers[id] = .score(
                        value: value, probabilities: ordered,
                        confidence: (raw["confidence"] as? Double) ?? 0)
                }
            default:
                continue
            }
        }
        let usage = root["usage"] as? [String: Any]
        return JevResponse(
            answers: answers,
            inputTokens: (usage?["input_tokens"] as? Int) ?? 0,
            model: (root["model"] as? String) ?? "",
            milliseconds: milliseconds)
    }
}
