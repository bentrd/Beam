import Foundation

/// Why a source could not be fetched or read.
///
/// `reason` is written to finish the foot sentence "Couldn't refresh: {reason}. Retry" (DESIGN.md section 6),
/// so every case reads as a lowercase clause without a full stop.
public enum FeedError: Error, Hashable, Sendable {
    case offline
    case timedOut
    case http(status: Int)
    /// The host said to come back later. `retryAfter` is in seconds when the host named a delay.
    case rateLimited(retryAfter: TimeInterval?)
    /// The address answered, but not with RSS, Atom, RDF or the expected JSON.
    case notAFeed
    case network(String)

    public var reason: String {
        switch self {
        case .offline: return "no internet connection"
        case .timedOut: return "the server took too long to answer"
        case .http(let status) where status == 404 || status == 410: return "the feed is gone (HTTP \(status))"
        case .http(let status): return "the server answered HTTP \(status)"
        case .rateLimited(let retryAfter?) where retryAfter.isFinite && retryAfter >= 0 && retryAfter.rounded(.up) < Double(Int.max):
            return "the server asked Beam to wait \(Int(retryAfter.rounded(.up))) s"
        case .rateLimited: return "the server asked Beam to slow down"
        case .notAFeed: return "the address doesn't return a feed"
        case .network(let message): return message
        }
    }
}

extension FeedError: LocalizedError {
    public var errorDescription: String? { reason }
}

extension FeedError {
    /// Collapses whatever a transport threw into the cases the product distinguishes.
    /// Cancellation is not a failure of the source, so it is rethrown untouched.
    static func wrapping(_ error: Error) throws -> FeedError {
        if let known = error as? FeedError { return known }
        if error is CancellationError { throw error }
        guard let urlError = error as? URLError else { return .network(error.localizedDescription) }
        switch urlError.code {
        case .cancelled: throw CancellationError()
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff: return .offline
        case .timedOut: return .timedOut
        default: return .network(urlError.localizedDescription)
        }
    }
}
