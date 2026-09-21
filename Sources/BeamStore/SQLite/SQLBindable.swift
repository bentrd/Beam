import Foundation

/// The storage classes Beam uses. There are no blobs: hashes are hex text and articles are JSON text.
enum SQLValue {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
}

/// A Swift value that can stand behind a `?` in a statement, so call sites pass model values directly
/// and the conversions (dates, URLs, optionals) live in exactly one place.
protocol SQLBindable {
    var sqlValue: SQLValue { get }
}

extension Int64: SQLBindable {
    var sqlValue: SQLValue { .integer(self) }
}

extension Int: SQLBindable {
    var sqlValue: SQLValue { .integer(Int64(self)) }
}

extension Bool: SQLBindable {
    var sqlValue: SQLValue { .integer(self ? 1 : 0) }
}

extension Double: SQLBindable {
    var sqlValue: SQLValue { .real(self) }
}

extension String: SQLBindable {
    var sqlValue: SQLValue { .text(self) }
}

extension Date: SQLBindable {
    /// Seconds since 2001-01-01 UTC, which is `Date`'s own representation: a date read back equals the date written,
    /// bit for bit, so stored items compare equal to the values they came from.
    var sqlValue: SQLValue { .real(timeIntervalSinceReferenceDate) }
}

extension URL: SQLBindable {
    var sqlValue: SQLValue { .text(absoluteString) }
}

extension Optional: SQLBindable where Wrapped: SQLBindable {
    var sqlValue: SQLValue { self?.sqlValue ?? .null }
}
