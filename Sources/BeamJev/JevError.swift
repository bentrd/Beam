import Foundation

/// Everything that can stop a judgment. Each case maps to one sentence the engine shows in a foot
/// (DESIGN.md section 6), so callers switch on the case and never parse a message.
/// No case ever carries the key.
public enum JevError: Error, Equatable, Sendable, LocalizedError {
    /// No key in the Keychain or the environment: "Add a key to search."
    case missingKey
    /// HTTP 401 or 403: "TypeSafe rejected this key".
    case unauthorized
    /// The day's spend reached the breaker: "Daily limit reached. Resets at midnight." Nothing was sent.
    case dailyLimitReached
    /// No connection, or the transport kept failing: "Offline. Showing what was already checked."
    case unreachable(String)
    /// 429, 529 or 5xx on every try. The item stays "not checked".
    case overloaded(status: Int)
    /// Any other status, such as 422: a bug in the request Beam built. `detail` is the start of the response body, for logs.
    case rejected(status: Int, detail: String)
    /// A 200 whose body is not the documented shape, or that cannot be priced because it carries no token count.
    case malformedResponse

    public var errorDescription: String? {
        switch self {
        case .missingKey: return "No TypeSafe key is configured."
        case .unauthorized: return "TypeSafe rejected this key."
        case .dailyLimitReached: return "Daily limit reached. Resets at midnight."
        case let .unreachable(why): return "Can't reach TypeSafe. \(why)"
        case let .overloaded(status): return "TypeSafe is busy (HTTP \(status))."
        case let .rejected(status, detail): return "TypeSafe refused the request (HTTP \(status)). \(detail)"
        case .malformedResponse: return "TypeSafe returned something unexpected."
        }
    }

    /// Whether the failure says something about the service, and so counts toward the ten consecutive failures that stop a run.
    /// A missing key, a rejected key and the daily limit are states of the app; retrying cannot change them.
    public var countsAsServiceFailure: Bool {
        switch self {
        case .unreachable, .overloaded, .rejected, .malformedResponse: return true
        case .missingKey, .unauthorized, .dailyLimitReached: return false
        }
    }
}
