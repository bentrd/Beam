import Foundation

/// Whitespace and invisible-character rules shared by everything that turns markup into passage text.
enum TextCleaner {
    /// Stands for `<br>` while inline text is being gathered, so that a real line break can be told apart from
    /// the newlines tidy and authors put in the source for formatting.
    static let lineBreak: Character = "\u{2028}"

    /// Collapses runs of whitespace to one space and trims the ends. Non-breaking spaces are kept where they stand
    /// alone (French punctuation relies on them); soft hyphens and zero-width characters are removed because they
    /// split words for the judge and for text selection.
    static func collapse(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.utf8.count)
        var pendingSpace: Character?
        for character in text {
            if isInvisible(character) { continue }
            if character.isWhitespace || character == lineBreak {
                let isNonBreaking = character == "\u{00A0}" || character == "\u{202F}"
                if pendingSpace == nil || !isNonBreaking { pendingSpace = isNonBreaking ? character : " " }
                continue
            }
            if let space = pendingSpace, !result.isEmpty { result.append(space) }
            pendingSpace = nil
            result.append(character)
        }
        return result
    }

    /// Splits gathered inline text at paragraph breaks written as two or more `<br>`, then collapses each piece.
    static func paragraphs(in text: String) -> [String] {
        var pieces: [String] = [], current = "", breaks = 0
        for character in text {
            if character == lineBreak { breaks += 1; current.append(" "); continue }
            if breaks >= 2, !character.isWhitespace { pieces.append(current); current = "" }
            if !character.isWhitespace { breaks = 0 }
            current.append(character)
        }
        pieces.append(current)
        return pieces.map(collapse).filter { !$0.isEmpty }
    }

    /// Code keeps its line structure: only surrounding blank lines and trailing spaces go.
    static func code(_ text: String) -> String {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: String(lineBreak), with: "\n")
            .components(separatedBy: "\n").map { line -> String in
                var line = line
                while line.last == " " || line.last == "\t" { line.removeLast() }
                return line
            }
        return Array(lines.drop { $0.isEmpty }.reversed().drop { $0.isEmpty }.reversed()).joined(separator: "\n")
    }

    /// Words as the text system sees them, so Japanese and Chinese count too (they have no spaces to split on).
    static func wordCount(_ text: String) -> Int {
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in count += 1 }
        return count
    }

    private static func isInvisible(_ character: Character) -> Bool {
        character == "\u{00AD}" || character == "\u{200B}" || character == "\u{FEFF}" || character == "\u{2060}"
    }
}
