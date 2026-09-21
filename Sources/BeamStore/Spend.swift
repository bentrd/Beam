import Foundation

extension Database {
    /// Tokens recorded for one day key such as "2026-09-21" (see `SpendLedger.day(for:timeZone:)`). Zero for a day never written.
    public func tokensSpent(onDay day: String) throws -> Int {
        try connection.first("SELECT tokens FROM spend WHERE day = ?", [day]) { $0.int(0) } ?? 0
    }

    /// Adds to a day's total and returns the new total, in one statement, so two callers cannot lose each other's tokens.
    @discardableResult
    public func addTokensSpent(_ tokens: Int, onDay day: String) throws -> Int {
        guard tokens >= 0 else { throw StoreError.invalid("negative token count \(tokens)") }
        return try connection.scalar("""
            INSERT INTO spend(day, tokens) VALUES (?1, ?2)
            ON CONFLICT(day) DO UPDATE SET tokens = tokens + ?2
            RETURNING tokens
            """, [day, tokens]) { $0.int(0) }
    }

    /// Replaces a day's total, for a meter that keeps the running count itself and only needs it to survive a relaunch.
    public func setTokensSpent(_ tokens: Int, onDay day: String) throws {
        guard tokens >= 0 else { throw StoreError.invalid("negative token count \(tokens)") }
        try connection.execute("INSERT INTO spend(day, tokens) VALUES (?, ?) ON CONFLICT(day) DO UPDATE SET tokens = excluded.tokens", [day, tokens])
    }
}

/// Tokens sent to TypeSafe, per local day: what the $0.50 daily breaker and "About $0.04 today" survive a relaunch on.
///
/// Deliberately free of any judge types, but shaped like the judge's `SpendPersisting` protocol
/// (`tokens(on:)`, `setTokens(_:on:)`), so the engine adopts it with `extension SpendLedger: SpendPersisting {}`.
/// Rows are never purged: a year is 365 tiny rows, and a purge that misread a day key could reset today's breaker.
public struct SpendLedger: Sendable {
    private let database: Database

    public init(database: Database) {
        self.database = database
    }

    public func tokens(on day: String) async throws -> Int {
        try await database.tokensSpent(onDay: day)
    }

    public func setTokens(_ tokens: Int, on day: String) async throws {
        try await database.setTokensSpent(tokens, onDay: day)
    }

    /// Returns the day's new total.
    @discardableResult
    public func add(tokens: Int, on day: String) async throws -> Int {
        try await database.addTokensSpent(tokens, onDay: day)
    }

    /// "2026-09-21" in the user's time zone: the limit "resets at midnight", the user's midnight.
    /// Always Gregorian, so the key keeps its shape on a Mac set to the Buddhist or Japanese calendar.
    public static func day(for date: Date = Date(), timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
