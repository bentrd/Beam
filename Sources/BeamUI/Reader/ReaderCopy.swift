import BeamModels
import Foundation

/// The reader's own sentences, word for word from DESIGN.md section 6.
///
/// Every status sentence ("Checking 84 paragraphs", "3 found, 2 unsure", "Getting the article", …) is written by the
/// engine and arrives in `ReaderSnapshot.foot`. What is here is what only the view can know: which hit is current,
/// the words of the page's own anatomy, and the help tags and announcements that have no visual of their own.
/// The failed-article sentence is here too, because its tail is Open Original, which `FootAction` cannot name.
enum ReaderCopy {
    static let unavailable = "Beam couldn't get the article text."
    static let openOriginalSentence = "Open Original."
    static let unsure = "Unsure. Read this yourself."
    static let notChecked = "Not checked"
    static let askPlaceholder = "Find by meaning"
    static let findNext = "Find Next"
    static let findPrevious = "Find Previous"
    static let openOriginal = "Open Original"
    static let markedRotor = "Marked paragraphs"
    static let notCheckedRotor = "Not checked"

    static func counter(_ position: Int, of total: Int) -> String { "\(position.formatted()) of \(total.formatted())" }

    /// "2 of 5, unsure": what VoiceOver hears on every jump. A probability is never spoken.
    static func jumpAnnouncement(_ position: Int, of total: Int, band: Band) -> String {
        counter(position, of: total) + (band == .unsure ? ", unsure" : ", found")
    }

    /// "Found, {first words}" for the rotors.
    static func rotorLabel(band: Band?, text: String) -> String {
        let words = text.split(whereSeparator: \.isWhitespace).prefix(8).joined(separator: " ")
        switch band {
        case .found: return "Found, " + words
        case .unsure: return "Unsure, " + words
        default: return words
        }
    }

    /// "Simon Willison · 31 December 2024 · ", the part of the byline before the link. The date follows the user's locale.
    static func bylineLead(source: String, date: Date?) -> String {
        var parts = [source].filter { !$0.isEmpty }
        if let date { parts.append(date.formatted(date: .long, time: .omitted)) }
        return parts.map { $0 + " · " }.joined()
    }

    /// "(4 images, 2 tables)", or nil when nothing was left out.
    static func omitted(images: Int, tables: Int) -> String? {
        var parts: [String] = []
        if images > 0 { parts.append(images == 1 ? "1 image" : "\(images.formatted()) images") }
        if tables > 0 { parts.append(tables == 1 ? "1 table" : "\(tables.formatted()) tables") }
        return parts.isEmpty ? nil : "(" + parts.joined(separator: ", ") + ")"
    }
}
