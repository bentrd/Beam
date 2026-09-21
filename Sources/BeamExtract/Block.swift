import Foundation

/// One piece of a page in reading order, before the passage rules (merge, split, sections, cap) are applied.
struct Block: Equatable {
    enum Kind: Equatable {
        case heading(level: Int)
        case paragraph, quote, listItem, code
        /// Media Beam does not show. They travel with the text so that only those inside the chosen article are counted.
        case image, table
    }

    var kind: Kind
    var text: String
    /// How much this block argues that its container is the article: its length, discounted by how much of it is link text.
    var weight: Int

    var isBody: Bool {
        switch kind {
        case .paragraph, .quote, .listItem, .code: return true
        case .heading, .image, .table: return false
        }
    }
}

/// A wall-clock budget for one extraction. Tidy cannot be interrupted, but everything after it checks in here,
/// so a pathological page costs a bounded amount of time instead of hanging the reader.
struct Deadline {
    private let end: ContinuousClock.Instant

    init(budget: Duration) { end = ContinuousClock.now + budget }

    func check() throws {
        if ContinuousClock.now > end { throw ExtractionError.timedOut }
    }
}

public enum ExtractionError: Error, Equatable, CustomStringConvertible {
    /// The body is larger than `Readability.maximumBytes`.
    case tooLarge(bytes: Int)
    /// The page took longer than `Readability.timeBudget` to process.
    case timedOut

    public var description: String {
        switch self {
        case let .tooLarge(bytes): return "The page is too large (\(bytes / 1_048_576) MB)"
        case .timedOut: return "The page took too long to process"
        }
    }
}
