import Foundation

/// Where the day's token count survives a relaunch. BeamStore backs it with the `spend(day, tokens)` table;
/// the meter works without one (checks, previews) and then counts from zero each launch.
public protocol SpendPersisting: Sendable {
    /// Tokens recorded for a local calendar day written "2026-09-21"; 0 when the day has no row.
    func tokens(on day: String) async throws -> Int
    /// Replaces the day's total.
    func setTokens(_ tokens: Int, on day: String) async throws
}

/// The silent daily breaker. Beam judges hundreds of items on one Return, so a bug or a huge source list
/// must not be able to run up a bill: at the ceiling requests stop and the foot says
/// "Daily limit reached. Resets at midnight."
///
/// The last slice of the day is reserved for reading, because being unable to light the article you just
/// opened is worse than a search that stops early. Requests already in flight when the line is crossed
/// still land, so the day can overshoot by at most one round of requests (a fraction of a cent).
public actor SpendMeter {
    /// What a request is for, which decides how much of the day it may use.
    public enum Purpose: Sendable {
        /// Searches, pins and pre-judging: everything but the reader reserve.
        case ranking
        /// The article the user opened, and Find by Meaning in it: the whole ceiling.
        case reading
    }

    public static let dollarsPerMillionTokens = 0.042
    public static let dailyCeiling = 0.50
    public static let readerReserve = 0.05

    private let ceiling: Double
    private let reserve: Double
    private let persistence: SpendPersisting?
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    private struct Stored: Equatable {
        var day: String
        var tokens: Int
    }
    /// The day being counted, as the local calendar names it.
    private var day: String
    /// Tokens added by this process on `day`.
    private var counted = 0
    /// Tokens already stored for `day` when this process first looked.
    private var carried = 0
    private var knowsCarried: Bool
    private var stored: Stored?
    private var writer: Task<Void, Never>?

    /// Set when the store could not be read or written, cleared when it works again. Until a failed read
    /// succeeds the meter counts this launch only and leaves the stored total untouched.
    public private(set) var persistenceFailure: String?

    /// `ceiling`, `reserve`, `calendar` and `now` are injectable so the checks can trip the breaker for a cent and cross midnight at will.
    public init(ceiling: Double = SpendMeter.dailyCeiling, readerReserve: Double = SpendMeter.readerReserve,
                persistence: SpendPersisting? = nil, calendar: Calendar = .autoupdatingCurrent,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.ceiling = ceiling
        self.reserve = min(max(0, readerReserve), ceiling)
        self.persistence = persistence
        self.calendar = calendar
        self.now = now
        self.day = SpendMeter.name(of: now(), in: calendar)
        self.knowsCarried = persistence == nil
    }

    /// Records the input tokens of one answered request.
    public func add(tokens: Int) async {
        await settle()
        counted += max(0, tokens)
        scheduleWrite()
    }

    /// Dollars spent since local midnight, for Settings ("About $0.04 today").
    public var dollarsToday: Double {
        get async {
            await settle()
            return dollars
        }
    }

    /// True when a request for `purpose` must not be sent.
    public func isExhausted(for purpose: Purpose) async -> Bool {
        await settle()
        switch purpose {
        case .ranking: return dollars >= ceiling - reserve
        case .reading: return dollars >= ceiling
        }
    }

    /// Returns once everything added so far is stored. Call before quitting.
    public func flush() async {
        scheduleWrite()
        await writer?.value
    }

    // MARK: Days

    private var dollars: Double { Double(carried + counted) * Self.dollarsPerMillionTokens / 1_000_000 }

    /// Brings the meter to today, and to what the store already holds for today.
    private func settle() async {
        startNewDayIfNeeded()
        guard let persistence, !knowsCarried else { return }
        let asked = day
        do {
            let tokens = try await persistence.tokens(on: asked)
            // The actor was free while the store answered: another caller may have finished first, or midnight may have passed.
            guard asked == day, !knowsCarried else { return }
            carried = max(0, tokens)
            knowsCarried = true
            persistenceFailure = nil
        } catch {
            persistenceFailure = "Couldn't read today's spend: \(error.localizedDescription)"
        }
    }

    /// Resets at local midnight. A clock that moves backwards (a flight west) keeps the later day:
    /// counting one long day is the careful side of the mistake.
    private func startNewDayIfNeeded() {
        let today = Self.name(of: now(), in: calendar)
        guard today > day else { return }
        day = today
        counted = 0
        carried = 0
        knowsCarried = persistence == nil
    }

    private static func name(of date: Date, in calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    // MARK: Storing

    /// One writer at a time, always writing the newest total: a burst of 300 answers becomes a handful of writes,
    /// they cannot land out of order, and no judgment waits for the disk.
    private func scheduleWrite() {
        guard persistence != nil, writer == nil else { return }
        writer = Task { await self.writeUntilCurrent() }
    }

    private func writeUntilCurrent() async {
        defer { writer = nil }
        guard let persistence else { return }
        // Never write before the stored total is known: it would replace the day's real count with this launch's.
        while knowsCarried {
            let target = Stored(day: day, tokens: carried + counted)
            guard target != stored else { return }
            do {
                try await persistence.setTokens(target.tokens, on: target.day)
                stored = target
                persistenceFailure = nil
            } catch {
                persistenceFailure = "Couldn't store today's spend: \(error.localizedDescription)"
                return
            }
        }
    }
}
