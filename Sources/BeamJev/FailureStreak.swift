import Foundation

/// Ten consecutive failures stop a run: past that point the service is down or the network is gone,
/// and sending the other 290 requests only turns one foot sentence into a long wait.
/// One value per run; the engine shows "Stopped after repeated errors. Retry" when `shouldStop` turns true.
public struct FailureStreak: Equatable, Sendable {
    public static let limit = 10
    public private(set) var consecutive = 0

    public init() {}

    public mutating func recordSuccess() { consecutive = 0 }

    /// Counts only failures that say something about the service (see `JevError.countsAsServiceFailure`);
    /// cancellation and the daily limit are not the service failing.
    public mutating func record(_ error: Error) {
        if let error = error as? JevError, error.countsAsServiceFailure { consecutive += 1 }
    }

    public var shouldStop: Bool { consecutive >= Self.limit }
}
