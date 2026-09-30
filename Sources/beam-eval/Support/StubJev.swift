import BeamJev
import Foundation

/// A TypeSafe that answers from a rule instead of a model, counts what it was asked, and can refuse on command.
///
/// It exists because the things `beam-eval` must prove are about what Beam *sends*: twenty new items cost twenty
/// requests whatever the pin count, arrowing rows costs nothing, a repeated search costs nothing, and exactly the
/// requests that fail read as "not checked". None of that can be measured against the real service.
final class StubJev: @unchecked Sendable {
    /// One request as it left Beam: the state judged, and the framed sentences asked about it.
    struct Ask {
        let state: [String: String]
        let frames: [String]
    }

    private let lock = NSLock()
    private var asks: [Ask] = []
    private let answer: @Sendable ([String: String], String) -> Double
    private var fails: @Sendable ([String: String]) -> Bool
    private let responseGate: ResponseGate?

    /// What the answers say they came from: the third part of every cache key.
    let model: String
    /// Input tokens each answer claims, which is what the daily breaker counts.
    let tokens: Int

    init(model: String = "jev-stub-1", tokens: Int = 600, holdsResponses: Bool = false,
         fails: @escaping @Sendable ([String: String]) -> Bool = { _ in false },
         answer: @escaping @Sendable ([String: String], String) -> Double = StubJev.overlap) {
        self.model = model
        self.tokens = tokens
        self.fails = fails
        self.answer = answer
        self.responseGate = holdsResponses ? ResponseGate() : nil
    }

    /// Turned off by Retry checks: the same request must work the second time.
    func stopFailing() { lock.withLock { fails = { _ in false } } }

    var count: Int { lock.withLock { asks.count } }
    var all: [Ask] { lock.withLock { asks } }
    func reset() { lock.withLock { asks.removeAll() } }
    func releaseResponses() async { await responseGate?.release() }

    /// A client Beam cannot tell from the real one, except that it never waits between retries.
    var client: JevClient {
        JevClient(transport: { [weak self] request in
            guard let self else { throw URLError(.cancelled) }
            let response = try self.answer(request)
            if let gate = self.responseGate { await gate.wait() }
            return response
        },
                  pause: { _ in })
    }

    private func answer(_ request: URLRequest) throws -> (Data, URLResponse) {
        guard let body = request.httpBody,
              let root = try JSONSerialization.jsonObject(with: body) as? [String: Any],
              let state = root["state"] as? [String: String],
              let questions = root["questions"] as? [String: Any]
        else { throw URLError(.badServerResponse) }

        var frames: [String] = []
        var index = 0
        while let question = questions["q\(index)"] as? [String: Any], let frame = question["instructions"] as? String {
            frames.append(frame)
            index += 1
        }
        lock.withLock { asks.append(Ask(state: state, frames: frames)) }

        guard !lock.withLock({ fails(state) }) else { return (Data("{}".utf8), Self.response(status: 500)) }
        var answers: [String: Any] = [:]
        for (position, frame) in frames.enumerated() {
            answers["q\(position)"] = ["type": "noul", "noul": answer(state, frame)]
        }
        let payload: [String: Any] = ["model": model, "usage": ["input_tokens": tokens], "answers": answers]
        return (try JSONSerialization.data(withJSONObject: payload), Self.response(status: 200))
    }

    private static func response(status: Int) -> URLResponse {
        HTTPURLResponse(url: JevClient.endpoint, statusCode: status, httpVersion: "HTTP/2", headerFields: nil)!
    }

    // MARK: The rule

    /// How much of the sentence's vocabulary the text repeats: enough for found, unsure and nothing to be told
    /// apart in a fixture, and deterministic, so a check that passes passes every time.
    static let overlap: @Sendable ([String: String], String) -> Double = { state, frame in
        let asked = words(in: sentence(in: frame))
        guard !asked.isEmpty else { return 0 }
        let text = words(in: state.values.sorted().joined(separator: " "))
        let share = Double(asked.intersection(text).count) / Double(asked.count)
        if share >= 0.6 { return 0.9 }
        return share >= 0.3 ? 0.5 : 0.05
    }

    /// The sentence a frame was built from: the only thing in it between double quotes.
    static func sentence(in frame: String) -> String {
        guard let first = frame.firstIndex(of: "\""), let last = frame.lastIndex(of: "\""), first < last else { return "" }
        return String(frame[frame.index(after: first)..<last])
    }

    static func words(in text: String) -> Set<String> {
        Set(text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count > 2 })
    }
}

/// Holds the first transport wave until a check has inspected it; later responses complete normally.
private actor ResponseGate {
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiting.append($0) }
    }
    func release() {
        isOpen = true
        let pending = waiting
        waiting.removeAll()
        pending.forEach { $0.resume() }
    }
}

extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
