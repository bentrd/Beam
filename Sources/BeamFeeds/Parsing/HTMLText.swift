import Foundation

/// Turns the HTML that feeds carry into the plain text Beam lists, previews and sends to the judge.
///
/// This is deliberately not an HTML parser: a snippet only needs tags gone, entities decoded and whitespace
/// collapsed, and a scanner does that in one pass over text that is often malformed. Articles are lane D's job.
public enum HTMLText {
    /// The contract's cap for `FeedItem.snippet`.
    public static let snippetLimit = 300

    /// Plain text: tags stripped, `<script>` and `<style>` bodies dropped, entities decoded, whitespace collapsed.
    public static func plainText(fromHTML html: String) -> String {
        collapseWhitespace(decodeEntities(strippingTags(from: html)))
    }

    /// Plain text cut to `limit` characters. A cut lands on a word boundary and ends in an ellipsis,
    /// so a preview never stops mid-word and the judge never reads half a token.
    public static func snippet(fromHTML html: String, limit: Int = snippetLimit) -> String {
        truncate(plainText(fromHTML: html), limit: limit)
    }

    /// For text that is already plain (Atom `type="text"`, YouTube descriptions): "a < b" must survive untouched.
    public static func snippet(fromPlainText text: String, limit: Int = snippetLimit) -> String {
        truncate(collapseWhitespace(text), limit: limit)
    }

    /// Runs of any Unicode whitespace, including the no-break spaces `&nbsp;` decodes to, become one space.
    public static func collapseWhitespace(_ text: String) -> String {
        var result = String.UnicodeScalarView()
        var pendingSpace = false
        for scalar in text.unicodeScalars {
            if scalar.properties.isWhitespace || scalar == "\u{200B}" || scalar == "\u{FEFF}" {
                pendingSpace = !result.isEmpty
            } else {
                if pendingSpace { result.append(" "); pendingSpace = false }
                result.append(scalar)
            }
        }
        return String(result)
    }

    /// Decodes `&name;`, `&#38;` and `&#x26;`. Anything that is not a known reference stays exactly as typed,
    /// so "AT&T" and "?a=1&b=2" pass through.
    public static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        let scalars = Array(text.unicodeScalars)
        var result = String.UnicodeScalarView()
        var index = 0
        while index < scalars.count {
            if scalars[index] == "&", let (decoded, next) = reference(in: scalars, at: index) {
                result.append(decoded)
                index = next
            } else {
                result.append(scalars[index])
                index += 1
            }
        }
        return String(result)
    }

    // MARK: Tags

    /// Closing one of these ends a run of text, so it must leave a space behind or "…end.</p><p>Next" reads "end.Next".
    private static let blockTags: Set<String> = [
        "p", "br", "div", "li", "ul", "ol", "tr", "td", "th", "table", "blockquote", "pre", "hr", "section", "article",
        "h1", "h2", "h3", "h4", "h5", "h6", "dt", "dd", "figure", "figcaption", "header", "footer",
    ]
    private static let invisibleContainers: Set<String> = ["script", "style"]

    /// Removes every tag. With `only`, removes just those tags and keeps the rest as text: an RSS title such as
    /// "The <dialog> element" is about a tag, while "<em>Really</em> fast" merely uses one.
    static func strippingTags(from html: String, only removable: Set<String>? = nil) -> String {
        guard html.contains("<") else { return html }
        let scalars = Array(html.unicodeScalars)
        var result = String.UnicodeScalarView()
        var index = 0
        while index < scalars.count {
            guard scalars[index] == "<", let tag = tag(in: scalars, at: index) else {
                result.append(scalars[index])
                index += 1
                continue
            }
            if let removable, !removable.contains(tag.name) {
                result.append(contentsOf: scalars[index..<tag.end])
            } else if invisibleContainers.contains(tag.name), !tag.isClosing {
                index = endOfContainer(tag.name, in: scalars, from: tag.end)
                continue
            } else if blockTags.contains(tag.name) {
                result.append(" ")
            }
            index = tag.end
        }
        return String(result)
    }

    private struct Tag { let name: String; let isClosing: Bool; let end: Int }

    /// Recognises `<name …>`, `</name>`, `<!-- … -->`, `<!…>` and `<?…?>`. A `<` followed by anything else is text.
    private static func tag(in scalars: [Unicode.Scalar], at start: Int) -> Tag? {
        var index = start + 1
        guard index < scalars.count else { return nil }
        if scalars[index] == "!" || scalars[index] == "?" {
            return declaration(in: scalars, at: start)
        }
        let isClosing = scalars[index] == "/"
        if isClosing { index += 1 }
        let nameStart = index
        while index < scalars.count, isNameScalar(scalars[index]) { index += 1 }
        guard index > nameStart, isASCIILetter(scalars[nameStart]) else { return nil }
        var name = String.UnicodeScalarView()
        name.append(contentsOf: scalars[nameStart..<index])
        var quote: Unicode.Scalar?
        while index < scalars.count {
            let scalar = scalars[index]
            if let open = quote {
                if scalar == open { quote = nil }
            } else if scalar == "\"" || scalar == "'" {
                quote = scalar
            } else if scalar == ">" {
                return Tag(name: String(name).lowercased(), isClosing: isClosing, end: index + 1)
            }
            index += 1
        }
        return nil
    }

    /// Comments end at `-->` (they may contain `>`); doctypes, CDATA markers and processing instructions end at `>`.
    private static func declaration(in scalars: [Unicode.Scalar], at start: Int) -> Tag? {
        let isComment = start + 3 < scalars.count && scalars[start + 1] == "!" && scalars[start + 2] == "-" && scalars[start + 3] == "-"
        var cursor = isComment ? start + 6 : start + 2
        while cursor < scalars.count {
            if scalars[cursor] == ">", !isComment || (scalars[cursor - 1] == "-" && scalars[cursor - 2] == "-") {
                return Tag(name: "!", isClosing: false, end: cursor + 1)
            }
            cursor += 1
        }
        return nil
    }

    private static func endOfContainer(_ name: String, in scalars: [Unicode.Scalar], from start: Int) -> Int {
        var index = start
        while index < scalars.count {
            if scalars[index] == "<", let closing = tag(in: scalars, at: index), closing.isClosing, closing.name == name {
                return closing.end
            }
            index += 1
        }
        return scalars.count
    }

    private static func isASCIILetter(_ scalar: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar)
    }

    private static func isNameScalar(_ scalar: Unicode.Scalar) -> Bool {
        isASCIILetter(scalar) || ("0"..."9").contains(scalar) || scalar == ":" || scalar == "-" || scalar == "_"
    }

    // MARK: Entities

    /// The longest HTML 4 name is `thetasym`; a numeric reference needs at most `#x10FFFF`.
    private static let longestReference = 10

    private static func reference(in scalars: [Unicode.Scalar], at ampersand: Int) -> (Unicode.Scalar, Int)? {
        var end = ampersand + 1
        while end < scalars.count, end - ampersand <= longestReference, scalars[end] != ";" {
            guard isNameScalar(scalars[end]) || scalars[end] == "#" else { return nil }
            end += 1
        }
        guard end < scalars.count, scalars[end] == ";", end > ampersand + 1 else { return nil }
        var body = String.UnicodeScalarView()
        body.append(contentsOf: scalars[(ampersand + 1)..<end])
        guard let scalar = scalar(forReference: String(body)) else { return nil }
        return (scalar, end + 1)
    }

    /// `body` is what sits between `&` and `;`.
    static func scalar(forReference body: String) -> Unicode.Scalar? {
        guard body.hasPrefix("#") else { return HTMLEntities.scalar(named: body) }
        let digits = body.dropFirst()
        let value: UInt32?
        if digits.hasPrefix("x") || digits.hasPrefix("X") {
            value = UInt32(digits.dropFirst(), radix: 16)
        } else {
            value = UInt32(digits, radix: 10)
        }
        return value.flatMap(Unicode.Scalar.init)
    }

    // MARK: Truncation

    private static func truncate(_ text: String, limit: Int) -> String {
        guard text.count > limit, limit > 1 else { return text }
        var head = text.prefix(limit - 1)
        // Step back to a word boundary unless that would throw away a large part of the budget (one very long token).
        if let lastSpace = head.lastIndex(of: " "), head.distance(from: lastSpace, to: head.endIndex) <= 40 {
            head = head[..<lastSpace]
        }
        let trimmed = head.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-–—([\"'«"))
        return trimmed + "…"
    }
}
