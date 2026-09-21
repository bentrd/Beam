import Foundation

/// Reads the dates feeds actually carry.
///
/// Six shapes cover what is in the wild: RFC 822 with a four-digit year, with a two-digit year, without the weekday,
/// and without seconds; and ISO 8601 (RFC 3339) with and without fractional seconds. Zones may be numeric, `Z`,
/// `GMT`/`UT`/`UTC` or a North American abbreviation; a missing zone means UTC.
///
/// Parsed by hand rather than with a stack of `DateFormatter`s: formatters are locale-sensitive, slow to build,
/// and each accepts one rigid pattern, while feeds mix all of these freely.
public enum FeedDate {
    public static func parse(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.unicodeScalars.first else { return nil }
        let startsWithYear = trimmed.count >= 10 && ("0"..."9").contains(first) && trimmed.dropFirst(4).first == "-"
        return startsWithYear ? iso8601(trimmed) : rfc822(trimmed)
    }

    // MARK: ISO 8601

    /// `2026-09-21`, `2026-09-21T09:30Z`, `2026-09-21T09:30:00+02:00`, `2026-09-21 09:30:00.123456-0700`.
    private static func iso8601(_ text: String) -> Date? {
        var scanner = DigitScanner(text)
        guard let year = scanner.number(digits: 4), scanner.skip("-"),
              let month = scanner.number(digits: 2), scanner.skip("-"),
              let day = scanner.number(digits: 2) else { return nil }
        var hour = 0, minute = 0, second = 0
        var fraction = 0.0
        if scanner.skip("T") || scanner.skip("t") || scanner.skip(" ") {
            guard let h = scanner.number(digits: 2), scanner.skip(":"), let m = scanner.number(digits: 2) else { return nil }
            hour = h; minute = m
            if scanner.skip(":") {
                guard let s = scanner.number(digits: 2) else { return nil }
                second = s
                if scanner.skip(".") || scanner.skip(",") { fraction = scanner.fraction() }
            }
        }
        guard let offset = zoneOffset(scanner.remainder) else { return nil }
        return date(year: year, month: month, day: day, hour: hour, minute: minute, second: second, fraction: fraction, offset: offset)
    }

    // MARK: RFC 822

    private static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

    /// `Mon, 21 Sep 2026 09:30:00 +0200`, `21 Sep 26 09:30 GMT`, `Monday, 21 September 2026 09:30:00 EST`.
    private static func rfc822(_ text: String) -> Date? {
        var tokens = text.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\t" }).map(String.init)
        if let first = tokens.first, first.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) || $0 == "." }) {
            tokens.removeFirst()
        }
        guard tokens.count >= 3, let day = Int(tokens[0]),
              let monthIndex = months.firstIndex(of: String(tokens[1].lowercased().prefix(3))),
              var year = Int(tokens[2]) else { return nil }
        if tokens[2].count <= 2 { year += year < 70 ? 2000 : 1900 }

        var hour = 0, minute = 0, second = 0
        var zone = ""
        if tokens.count >= 4 {
            let clock = tokens[3].split(separator: ":").map { Int($0) }
            guard clock.count == 2 || clock.count == 3, let h = clock[0], let m = clock[1] else { return nil }
            hour = h; minute = m
            if clock.count == 3 {
                guard let s = clock[2] else { return nil }
                second = s
            }
            // Anything after the zone is a comment such as "(CEST)".
            zone = tokens.count > 4 ? tokens[4] : ""
        }
        guard let offset = zoneOffset(zone) else { return nil }
        return date(year: year, month: monthIndex + 1, day: day, hour: hour, minute: minute, second: second, fraction: 0, offset: offset)
    }

    // MARK: Zones

    private static let namedZones: [String: Int] = [
        "Z": 0, "UT": 0, "UTC": 0, "GMT": 0,
        "EST": -5, "EDT": -4, "CST": -6, "CDT": -5, "MST": -7, "MDT": -6, "PST": -8, "PDT": -7,
        "CET": 1, "CEST": 2, "BST": 1,
    ]

    /// Seconds east of UTC. An empty zone is UTC; an unreadable one fails the whole date rather than shifting it silently.
    private static func zoneOffset(_ text: String) -> Int? {
        let zone = text.trimmingCharacters(in: .whitespaces)
        if zone.isEmpty { return 0 }
        if let hours = namedZones[zone.uppercased()] { return hours * 3600 }
        guard let sign = zone.first, sign == "+" || sign == "-" else { return nil }
        let digits = zone.dropFirst().filter { $0 != ":" }
        guard digits.count == 4 || digits.count == 2, digits.allSatisfy(\.isNumber),
              let hours = Int(digits.prefix(2)), let minutes = digits.count == 4 ? Int(digits.suffix(2)) : 0,
              hours <= 14, minutes < 60 else { return nil }
        let seconds = hours * 3600 + minutes * 60
        return sign == "-" ? -seconds : seconds
    }

    // MARK: Calendar arithmetic

    private static func date(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int, fraction: Double, offset: Int) -> Date? {
        guard (1...9999).contains(year), (1...12).contains(month), (1...daysIn(month: month, year: year)).contains(day),
              (0...24).contains(hour), (0..<60).contains(minute), (0...60).contains(second) else { return nil }
        let days = daysFromCivil(year: year, month: month, day: day)
        let seconds = days * 86_400 + hour * 3600 + minute * 60 + second - offset
        return Date(timeIntervalSince1970: TimeInterval(seconds) + fraction)
    }

    private static func daysIn(month: Int, year: Int) -> Int {
        let isLeap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
        return [31, isLeap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1]
    }

    /// Days since 1970-01-01 in the proleptic Gregorian calendar (Howard Hinnant's `days_from_civil`): exact, and
    /// free of `Calendar`, whose time-zone and locale settings have no business in a wire format.
    private static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let dayOfYear = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }
}

/// Reads fixed-width decimal fields off the front of a string.
private struct DigitScanner {
    private var rest: Substring
    init(_ text: String) { rest = Substring(text) }

    var remainder: String { String(rest) }

    mutating func number(digits count: Int) -> Int? {
        let field = rest.prefix(count)
        guard field.count == count, field.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(field) else { return nil }
        rest = rest.dropFirst(count)
        return value
    }

    mutating func skip(_ character: Character) -> Bool {
        guard rest.first == character else { return false }
        rest = rest.dropFirst()
        return true
    }

    /// The digits after a decimal point, as a fraction of a second.
    mutating func fraction() -> Double {
        let digits = rest.prefix(while: { $0.isASCII && $0.isNumber })
        rest = rest.dropFirst(digits.count)
        return Double("0." + digits) ?? 0
    }
}
