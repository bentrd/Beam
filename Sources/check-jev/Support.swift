import BeamJev
import Foundation

/// A stand-in for api.typesafe.ai: replies from a script, then from `fallback`, and records what it was sent.
final class FakeService: @unchecked Sendable {
    enum Reply {
        case http(Int, body: String)
        case failure(URLError.Code)
    }

    private let lock = NSLock()
    private var script: [Reply]
    private let fallback: Reply
    private let latency: ClosedRange<UInt64>?
    private var received: [URLRequest] = []
    private var inFlight = 0
    private var peak = 0

    /// `latency` (milliseconds) makes requests overlap, so the peak in flight means something.
    init(script: [Reply] = [], fallback: Reply = .http(200, body: FakeService.answers(["0.5"])), latency: ClosedRange<UInt64>? = nil) {
        self.script = script
        self.fallback = fallback
        self.latency = latency
    }

    var transport: JevClient.Transport {
        { [self] request in try await self.handle(request) }
    }

    var requests: [URLRequest] { lock.withLock { received } }
    var peakInFlight: Int { lock.withLock { peak } }

    private func handle(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let reply: Reply = lock.withLock {
            received.append(request)
            inFlight += 1
            peak = max(peak, inFlight)
            return script.isEmpty ? fallback : script.removeFirst()
        }
        defer { lock.withLock { inFlight -= 1 } }
        if let latency { try await Task.sleep(nanoseconds: UInt64.random(in: latency) * 1_000_000) }
        switch reply {
        case let .failure(code):
            throw URLError(code)
        case let .http(status, body):
            guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/2", headerFields: nil) else {
                throw URLError(.badServerResponse)
            }
            return (Data(body.utf8), response)
        }
    }

    /// A response body whose Noul values are raw JSON fragments, so a check can send `true`, `"0.5"` or `1.5` as easily as `0.5`.
    static func answers(_ values: [String], tokens: Int = 300, model: String = "jev-test") -> String {
        let answers = values.enumerated().map { "\"q\($0.offset)\": {\"type\": \"noul\", \"noul\": \($0.element)}" }
        return "{\"model\": \"\(model)\", \"answers\": {\(answers.joined(separator: ", "))}, \"usage\": {\"input_tokens\": \(tokens), \"output_tokens\": 20}}"
    }
}

/// Collects the waits a client asked for instead of waiting.
final class PauseLog: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [TimeInterval] = []
    var pauses: [TimeInterval] { lock.withLock { recorded } }
    var pause: JevClient.Pause {
        { [self] seconds in self.lock.withLock { self.recorded.append(seconds) } }
    }
}

/// A clock the checks can move across midnight.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ start: Date) { current = start }
    var now: Date { lock.withLock { current } }
    func set(_ date: Date) { lock.withLock { current = date } }
}

/// The `spend` table, in memory.
actor MemorySpendStore: SpendPersisting {
    struct Unavailable: Error {}
    private(set) var rows: [String: Int] = [:]
    private(set) var writes = 0
    private var isBroken = false

    func tokens(on day: String) async throws -> Int {
        if isBroken { throw Unavailable() }
        return rows[day] ?? 0
    }

    func setTokens(_ tokens: Int, on day: String) async throws {
        if isBroken { throw Unavailable() }
        rows[day] = tokens
        writes += 1
    }

    func setBroken(_ broken: Bool) { isBroken = broken }
}

/// Counts how many pieces of work run at once.
actor Gauge {
    private(set) var current = 0
    private(set) var peak = 0
    func enter() { current += 1; peak = max(peak, current) }
    func leave() { current -= 1 }
}

/// A seeded generator, so a failing run of the limiter check can be replayed.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Polls until `condition` holds; false if it never does within two seconds.
func eventually(_ condition: @Sendable () async -> Bool) async -> Bool {
    for _ in 0..<2_000 {
        if await condition() { return true }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    return false
}

extension Result {
    var isCancellation: Bool {
        if case let .failure(error) = self { return error is CancellationError }
        return false
    }
}
