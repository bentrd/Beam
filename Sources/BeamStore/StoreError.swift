import Foundation
import SQLite3

/// Everything the store can fail with.
///
/// SQLite's own message and the statement that failed travel with the error, so a failure in the field
/// can be understood from one log line, without a debugger.
public enum StoreError: Error, Hashable, CustomStringConvertible {
    /// SQLite refused an operation. `code` is the extended result code; `context` is the SQL or the step that failed.
    case sqlite(code: Int32, message: String, context: String)
    /// A transaction failed and could not be rolled back either. Both causes are kept: the first explains the bug,
    /// the second says the connection may still hold a write lock.
    case rollbackFailed(cause: String, rollback: String)
    /// The file was written by a newer Beam. Older code could destroy what it does not know about, so it refuses to open.
    case newerSchema(found: Int, supported: Int)
    /// A row the caller named does not exist, or can no longer be restored.
    case notFound(String)
    /// Stored data could not be decoded (an unknown source kind, an article's passages).
    case corrupt(String)
    /// The caller passed a value the store will not keep (a negative token count, a probability outside 0...1).
    case invalid(String)
    /// The database was used after `close()`.
    case closed

    public var description: String {
        switch self {
        case let .sqlite(code, message, context): return "SQLite error \(code): \(message) [\(context)]"
        case let .rollbackFailed(cause, rollback): return "Transaction failed (\(cause)) and could not be rolled back (\(rollback))"
        case let .newerSchema(found, supported): return "Database schema \(found) is newer than this build supports (\(supported))"
        case let .notFound(what): return "Not found: \(what)"
        case let .corrupt(what): return "Stored data could not be read: \(what)"
        case let .invalid(what): return "Invalid value: \(what)"
        case .closed: return "The database is closed"
        }
    }

    /// Captures the connection's current error. Call it immediately after the failing SQLite call.
    static func current(_ database: OpaquePointer?, context: String) -> StoreError {
        guard let database else { return .closed }
        return .sqlite(code: sqlite3_extended_errcode(database), message: String(cString: sqlite3_errmsg(database)), context: context)
    }
}
