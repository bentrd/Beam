import BeamModels
import Foundation

/// The only door to the judge. Every request in the app, whatever it is for, passes the same three gates in
/// the same order: a key, the daily breaker, the global limiter. Create one per process and share it.
public actor Judge {
    private let keyProvider: @Sendable () -> String?
    private let spend: SpendMeter
    private let limiter: Limiter
    private let client: JevClient

    /// - Parameters:
    ///   - keyProvider: asked on every request, so a key added or removed in Settings takes effect at once. Pass `{ provider.key() }` for a `KeyProvider`.
    ///   - maxInFlight: 64 was measured as the knee: 96 items in about a second with no rate-limit errors (EVIDENCE.md).
    public init(keyProvider: @escaping @Sendable () -> String?, spend: SpendMeter, maxInFlight: Int = 96, client: JevClient = JevClient()) {
        self.keyProvider = keyProvider
        self.spend = spend
        self.limiter = Limiter(capacity: maxInFlight)
        self.client = client
    }

    /// One request: one piece of state, every frame as a parallel Noul (the search sentence plus every pin ride together,
    /// which is why keeping pins current costs one pass over new items whatever the pin count).
    ///
    /// - Returns: one probability per frame, nil where the answer was missing or invalid. Tokens are already metered.
    /// - Throws: `JevError`, or `CancellationError` if the task is cancelled while queued or in flight; a cancelled call never holds a slot.
    public func judge(state: [String: String], frames: [String], for purpose: SpendMeter.Purpose = .ranking) async throws -> Judgments {
        guard !frames.isEmpty else { return Judgments(probabilities: [], tokens: 0, model: "") }
        guard let key = currentKey() else { throw JevError.missingKey }
        return try await send(key: key, state: state, frames: frames, purpose: purpose)
    }

    /// Checks the stored key with one constant request that carries nothing of the user's.
    public func validateKey() async -> KeyStatus {
        guard let key = currentKey() else { return .missing }
        return await validate(key: key)
    }

    /// Checks a key the user has just typed, before it is stored.
    public func validate(key candidate: String) async -> KeyStatus {
        let key = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return .missing }
        do {
            // Not held back by the breaker: a few hundred tokens, and the user must be able to fix a key on a day the limit was hit.
            _ = try await send(key: key, state: ["text": "Beam key check."], frames: ["This text is a key check."], purpose: nil)
            return .valid
        } catch JevError.unauthorized {
            return .rejected
        } catch {
            return .unreachable
        }
    }

    /// Requests in flight and requests queued, for the checks and for diagnostics.
    public var load: Limiter.Load {
        get async { await limiter.load }
    }

    private func currentKey() -> String? {
        guard let key = keyProvider()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else { return nil }
        return key
    }

    private func send(key: String, state: [String: String], frames: [String], purpose: SpendMeter.Purpose?) async throws -> Judgments {
        let spend = self.spend
        let client = self.client
        return try await limiter.withSlot {
            // Checked with the slot in hand: a request may have queued behind the very ones that reached the limit.
            try Task.checkCancellation()
            if let purpose, await spend.isExhausted(for: purpose) { throw JevError.dailyLimitReached }
            let judgments = try await client.ask(key: key, state: state, frames: frames)
            await spend.add(tokens: judgments.tokens)
            return judgments
        }
    }
}
