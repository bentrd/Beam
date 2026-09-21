import Foundation
import SQLite3

/// Tells SQLite to copy bound text before the bind call returns: a Swift string's buffer does not outlive it.
private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// One prepared statement. Owned by `Connection`'s cache, which finalizes it.
final class Statement {
    private let handle: OpaquePointer
    private let database: OpaquePointer
    private let sql: String

    init(sql: String, database: OpaquePointer) throws {
        var prepared: OpaquePointer?
        // PERSISTENT: the statement is cached and reused for the life of the connection.
        let code = sqlite3_prepare_v3(database, sql, -1, UInt32(SQLITE_PREPARE_PERSISTENT), &prepared, nil)
        guard code == SQLITE_OK else {
            sqlite3_finalize(prepared)
            throw StoreError.current(database, context: sql)
        }
        guard let prepared else { throw StoreError.invalid("empty statement: \(sql)") }
        self.handle = prepared
        self.database = database
        self.sql = sql
    }

    /// Binds values to `?1…?n` in order.
    func bind(_ values: [any SQLBindable]) throws {
        let expected = Int(sqlite3_bind_parameter_count(handle))
        guard values.count == expected else {
            throw StoreError.invalid("\(values.count) values for \(expected) parameters: \(sql)")
        }
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let code: Int32
            switch value.sqlValue {
            case .null: code = sqlite3_bind_null(handle, index)
            case let .integer(number): code = sqlite3_bind_int64(handle, index, number)
            case let .real(number): code = sqlite3_bind_double(handle, index, number)
            case let .text(string): code = bindText(string, at: index)
            }
            guard code == SQLITE_OK else { throw StoreError.current(database, context: sql) }
        }
    }

    /// Binds by byte count, never by C-string length, so text with an embedded NUL is stored whole.
    private func bindText(_ string: String, at index: Int32) -> Int32 {
        var string = string
        return string.withUTF8 { buffer in
            // An empty buffer may have no base address, and a null pointer would bind NULL rather than "".
            guard let base = buffer.baseAddress, buffer.count > 0 else {
                return sqlite3_bind_text64(handle, index, "", 0, transient, UInt8(SQLITE_UTF8))
            }
            return base.withMemoryRebound(to: CChar.self, capacity: buffer.count) { characters in
                sqlite3_bind_text64(handle, index, characters, sqlite3_uint64(buffer.count), transient, UInt8(SQLITE_UTF8))
            }
        }
    }

    /// Advances one row. Returns false when the statement has finished.
    func step() throws -> Bool {
        switch sqlite3_step(handle) {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        default: throw StoreError.current(database, context: sql)
        }
    }

    var row: Row { Row(handle: handle) }

    /// Ends the current run and drops bound values, so a cached statement never pins a read snapshot or a large string.
    func reset() {
        sqlite3_reset(handle)
        sqlite3_clear_bindings(handle)
    }

    func finalize() {
        sqlite3_finalize(handle)
    }
}

/// The current result row of a statement. Valid only inside the mapping closure it is handed to.
struct Row {
    fileprivate let handle: OpaquePointer

    func isNull(_ column: Int32) -> Bool { sqlite3_column_type(handle, column) == SQLITE_NULL }
    func int64(_ column: Int32) -> Int64 { sqlite3_column_int64(handle, column) }
    func int(_ column: Int32) -> Int { Int(sqlite3_column_int64(handle, column)) }
    func bool(_ column: Int32) -> Bool { sqlite3_column_int64(handle, column) != 0 }
    func double(_ column: Int32) -> Double { sqlite3_column_double(handle, column) }
    func date(_ column: Int32) -> Date { Date(timeIntervalSinceReferenceDate: double(column)) }
    func optionalDate(_ column: Int32) -> Date? { isNull(column) ? nil : date(column) }
    func string(_ column: Int32) -> String { optionalString(column) ?? "" }

    /// Reads by byte count and repairs invalid UTF-8, so no stored text can crash or truncate a read.
    func optionalString(_ column: Int32) -> String? {
        guard let bytes = sqlite3_column_text(handle, column) else { return nil }
        let count = Int(sqlite3_column_bytes(handle, column))
        return String(decoding: UnsafeBufferPointer(start: bytes, count: count), as: UTF8.self)
    }

    /// nil for NULL and for text that is not a URL: a bad link in a feed must not hide the item.
    func optionalURL(_ column: Int32) -> URL? { optionalString(column).flatMap { URL(string: $0) } }
}
