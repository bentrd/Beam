import Foundation

extension Database {
    /// Small persistent settings that belong with the data rather than in user defaults (the last model id seen, for one).
    public func meta(_ key: String) throws -> String? {
        try connection.first("SELECT value FROM meta WHERE key = ?", [key]) { $0.string(0) }
    }

    /// Stores a value, or deletes the key when `value` is nil.
    public func setMeta(_ key: String, to value: String?) throws {
        guard let value else {
            try connection.execute("DELETE FROM meta WHERE key = ?", [key])
            return
        }
        try connection.execute("INSERT INTO meta(key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value", [key, value])
    }
}
