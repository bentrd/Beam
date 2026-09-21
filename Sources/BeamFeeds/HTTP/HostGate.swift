import Foundation

/// Time as the pacing code sees it. Injectable so a check can prove "one request per 3 s" without waiting 9 s.
public struct PacingClock: Sendable {
    /// Seconds on any steadily advancing scale.
    public var now: @Sendable () -> TimeInterval
    public var sleep: @Sendable (TimeInterval) async throws -> Void

    public init(now: @escaping @Sendable () -> TimeInterval, sleep: @escaping @Sendable (TimeInterval) async throws -> Void) {
        self.now = now
        self.sleep = sleep
    }

    /// Wall-clock time, because a host's "retry after" is a wall-clock promise that should survive the Mac sleeping.
    public static let system = PacingClock(
        now: { Date().timeIntervalSinceReferenceDate },
        sleep: { try await Task.sleep(nanoseconds: UInt64(max(0, $0) * 1_000_000_000)) }
    )
}

/// Every request to one touchy host goes through one gate: strictly one at a time, never closer together than
/// `minimumInterval`, and never sooner than the host's own rate-limit headers allow.
///
/// arXiv asks API clients for one request every three seconds. Reddit gives an anonymous reader about one request
/// a minute and says so in `X-Ratelimit-Remaining` / `X-Ratelimit-Reset` (measured; EVIDENCE.md saw the 429).
/// The gates are process-wide (`arxiv`, `reddit`) because the limit is the host's, not any one caller's:
/// refreshing and resolving must share it.
public actor HostGate {
    public static let arxiv = HostGate(minimumInterval: 3)
    public static let reddit = HostGate(minimumInterval: 2)

    private let minimumInterval: TimeInterval
    private let clock: PacingClock
    /// The earliest moment the next request to join the queue could start, ignoring what the host may yet say.
    private var nextSlot: TimeInterval = 0
    /// The host asked for silence until then.
    private var blockedUntil: TimeInterval = 0
    private var tail: Task<Void, Never>?

    /// What to assume when a host says "too many requests" without saying for how long.
    private static let unspecifiedBackoff: TimeInterval = 60

    public init(minimumInterval: TimeInterval, clock: PacingClock = .system) {
        self.minimumInterval = minimumInterval
        self.clock = clock
    }

    /// - Parameter patience: how long this caller will wait for the host's permission. A background refresh can
    ///   sit out Reddit's minute; someone watching "Looking for a feed" cannot. When the wait would be longer, the
    ///   call fails at once with `FeedError.rateLimited`, without touching the network or holding up the queue.
    public func send(_ request: HTTPRequest, using fetch: @escaping HTTPFetch, patience: TimeInterval) async throws -> HTTPResponse {
        let now = clock.now()
        let start = max(now, nextSlot, blockedUntil)
        guard start - now <= patience else { throw FeedError.rateLimited(retryAfter: start - now) }
        nextSlot = start + minimumInterval

        let previous = tail
        let turn = Task { () throws -> HTTPResponse in
            await previous?.value
            return try await self.sendInTurn(request, using: fetch, notBefore: start, patience: patience)
        }
        tail = Task { _ = try? await turn.value }
        return try await withTaskCancellationHandler { try await turn.value } onCancel: { turn.cancel() }
    }

    /// Runs with no other turn in progress, so the host's latest word is always known before the next request leaves.
    private func sendInTurn(_ request: HTTPRequest, using fetch: HTTPFetch, notBefore start: TimeInterval,
                            patience: TimeInterval) async throws -> HTTPResponse {
        var earliest = start
        for attempt in 0..<2 {
            try Task.checkCancellation()
            earliest = max(earliest, blockedUntil)
            let now = clock.now()
            if earliest - now > patience { throw FeedError.rateLimited(retryAfter: earliest - now) }
            if earliest > now { try await clock.sleep(earliest - now) }

            let response = try await fetch(request)
            let sent = clock.now()
            nextSlot = max(nextSlot, sent + minimumInterval)
            if let cooldown = Self.cooldown(after: response, now: Date()) { blockedUntil = max(blockedUntil, sent + cooldown) }
            guard let delay = Self.requestedDelay(in: response, now: Date()) else { return response }
            if attempt == 1 { throw FeedError.rateLimited(retryAfter: delay) }
        }
        throw FeedError.rateLimited(retryAfter: nil)
    }

    // MARK: Reading the host's wishes

    /// Non-nil when the response is a refusal: 429, or 503 carrying `Retry-After`. The value is how long to stay away.
    static func requestedDelay(in response: HTTPResponse, now: Date) -> TimeInterval? {
        let stated = response.header("Retry-After").flatMap { seconds(from: $0, now: now) }
        guard response.status == 429 || (response.status == 503 && stated != nil) else { return nil }
        return stated ?? response.header("X-Ratelimit-Reset").flatMap { seconds(from: $0, now: now) } ?? unspecifiedBackoff
    }

    /// How long to stay away after this response, refusal or not: a success that spent the last of the allowance
    /// (`X-Ratelimit-Remaining: 0`) says when the next one becomes possible.
    static func cooldown(after response: HTTPResponse, now: Date) -> TimeInterval? {
        if let delay = requestedDelay(in: response, now: now) { return delay }
        guard let remaining = response.header("X-Ratelimit-Remaining").flatMap(Double.init), remaining < 1 else { return nil }
        return response.header("X-Ratelimit-Reset").flatMap { seconds(from: $0, now: now) }
    }

    /// Hosts state a delay as seconds from now, as an HTTP date, or (GitHub-style resets) as a Unix time.
    private static func seconds(from header: String, now: Date) -> TimeInterval? {
        let value = header.trimmingCharacters(in: .whitespaces)
        if let number = TimeInterval(value) {
            let isUnixTime = number > 1_000_000_000
            return max(0, isUnixTime ? number - now.timeIntervalSince1970 : number)
        }
        return FeedDate.parse(value).map { max(0, $0.timeIntervalSince(now)) }
    }
}
