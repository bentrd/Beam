import Foundation

/// How old an item is, the way a list row says it: "38m", "7h", "2d", "3w".
enum Age {
    static func short(since date: Date, now: Date = Date()) -> String {
        let seconds = max(now.timeIntervalSince(date), 0)
        switch seconds {
        case ..<60: return "now"
        case ..<3_600: return "\(Int(seconds / 60))m"
        case ..<86_400: return "\(Int(seconds / 3_600))h"
        case ..<(14 * 86_400): return "\(Int(seconds / 86_400))d"
        case ..<(61 * 86_400): return "\(Int(seconds / (7 * 86_400)))w"
        default: return "\(Int(seconds / (30.44 * 86_400)))mo"            // items are purged after a year
        }
    }

    /// The same age in words, for VoiceOver: "2 hours ago".
    static func spoken(since date: Date, now: Date = Date()) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: min(date, now), relativeTo: now)
    }
}
