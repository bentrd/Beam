import Foundation
import SQLite3

/// Direct access to a database file, for what the store's API rightly does not offer:
/// reading the schema back and tampering with `user_version`.
enum RawSQLite {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    static func strings(_ sql: String, column: Int32 = 0, at file: URL) throws -> [String] {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(file.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close_v2(handle)
            throw Failure(description: "cannot open \(file.lastPathComponent)")
        }
        defer { sqlite3_close_v2(handle) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw Failure(description: String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        var values: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            values.append(sqlite3_column_text(statement, column).map { String(cString: $0) } ?? "")
        }
        return values
    }

    static func execute(_ sql: String, at file: URL) throws {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(file.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            sqlite3_close_v2(handle)
            throw Failure(description: "cannot open \(file.lastPathComponent)")
        }
        defer { sqlite3_close_v2(handle) }
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
            throw Failure(description: String(cString: sqlite3_errmsg(handle)))
        }
    }
}
