import BeamModels
import Foundation

/// The reader's own sentences, word for word from DESIGN.md section 6.
///
/// Run status ("Checking 84 paragraphs", "3 found, 2 unsure", …) is written by the engine and arrives in `ReaderSnapshot.foot`.
/// What is here is what only the view can know: which hit is current, whether the ask field is open,
/// how long the article has been loading, and the fixed wording of each phase.
enum ReaderCopy {
    static let returnToRead = "Return to read"
    static let returnToOpenInBrowser = "Return to open in your browser"
    static let gettingArticle = "Getting the article"
    static let unavailable = "Beam couldn't get the article text."
    static let openOriginalSentence = "Open Original."
    static let unsure = "Unsure. Read this yourself."
    static let notChecked = "Not checked"
    static let askPlaceholder = "Find by meaning"
    static let checking = "Checking"
    static let saturatedShort = "Most of this article is about this"
    static let findNext = "Find Next"
    static let findPrevious = "Find Previous"
    static let openOriginal = "Open Original"
    static let markedRotor = "Marked paragraphs"
    static let notCheckedRotor = "Not checked"

    static func counter(_ position: Int, of total: Int) -> String { "\(position.formatted()) of \(total.formatted())" }

    static func nothingFound(checked: Int) -> String { "Nothing found in \(checked.formatted()) checked" }

    /// "3 found, 2 unsure", dropping a side that is zero.
    static func summary(found: Int, unsure: Int) -> String {
        var parts: [String] = []
        if found > 0 { parts.append("\(found.formatted()) found") }
        if unsure > 0 { parts.append("\(unsure.formatted()) unsure") }
        return parts.joined(separator: ", ")
    }

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
