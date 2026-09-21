import Foundation

/// Rewrites raw HTML into something Foundation's tidy can keep the structure of.
///
/// Why this exists (measured on this machine): the tidy inside `XMLDocument` predates HTML5. It deletes the tags of
/// every element it does not know (`article`, `main`, `section`, `nav`, `footer`, `aside`, `figure`, `math`, `svg`…) and
/// keeps their text, so a page's navigation and footer end up as loose text in `<body>` and `//article` never matches.
/// Beam therefore turns those elements into `<div data-beam="article">` and friends, which tidy preserves, and removes
/// the ones whose content is never article text before tidy sees them (which also makes the parse much faster:
/// scripts are often most of a page's bytes).
enum HTMLPreprocessor {
    /// The attribute that remembers which HTML5 element a `div` used to be.
    static let markerAttribute = "data-beam"

    /// HTML5 sectioning and grouping elements tidy would otherwise dissolve.
    private static let structuralTags = "article|section|main|nav|header|footer|aside|figure|figcaption|details|summary|hgroup|dialog|search"
    /// Elements whose content is never readable article text.
    private static let opaqueTags = "script|style|svg|template|noscript|iframe|canvas|video|audio|object"

    private static let comments = NSRegularExpression.builtIn(#"<!--[\s\S]*?-->"#)
    private static let opaque = NSRegularExpression.builtIn("<(\(opaqueTags))\\b[^>]*>[\\s\\S]*?</\\1\\s*>")
    private static let math = NSRegularExpression.builtIn(#"<math\b([^>]*)>([\s\S]*?)</math\s*>"#)
    private static let mathAltText = NSRegularExpression.builtIn(#"\balttext\s*=\s*"([^"]*)""#)
    private static let mathAnnotation = NSRegularExpression.builtIn(#"<annotation\b[^>]*application/x-tex[^>]*>([\s\S]*?)</annotation\s*>"#)
    private static let mathScript = NSRegularExpression.builtIn(#"<script\b[^>]*type\s*=\s*["']math/tex[^"']*["'][^>]*>([\s\S]*?)</script\s*>"#)
    private static let structuralOpen = NSRegularExpression.builtIn("<(\(structuralTags))(?=[\\s>/])")
    private static let structuralClose = NSRegularExpression.builtIn("</(?:\(structuralTags))\\s*>")
    private static let jsonLD = NSRegularExpression.builtIn(#"<script\b[^>]*type\s*=\s*["']?application/ld\+json["']?[^>]*>([\s\S]*?)</script\s*>"#)

    static func prepare(_ html: String) -> String {
        var text = replace(comments, in: html, with: " ")
        // MathJax 2 keeps each formula's TeX in a script element; it is the only copy of the formula in the page.
        text = replace(mathScript, in: text, with: " $1 ")
        text = replace(opaque, in: text, with: " ")
        text = replaceMath(in: text)
        text = replace(structuralOpen, in: text, with: "<div \(markerAttribute)=\"$1\"")
        return replace(structuralClose, in: text, with: "</div>")
    }

    /// The bodies of every `<script type="application/ld+json">`, read from the raw page so they survive `prepare`.
    static func jsonLDPayloads(in html: String) -> [String] {
        let source = html as NSString
        return jsonLD.matches(in: html, range: NSRange(location: 0, length: source.length)).map { source.substring(with: $0.range(at: 1)) }
    }

    /// MathML becomes its TeX source (the `alttext` attribute, else the TeX annotation KaTeX embeds): the element's
    /// own text is presentation markup plus that annotation, which reads as "x2x^2".
    private static func replaceMath(in html: String) -> String {
        let source = html as NSString
        let matches = math.matches(in: html, range: NSRange(location: 0, length: source.length))
        guard !matches.isEmpty else { return html }
        let result = NSMutableString(string: html)
        for match in matches.reversed() {
            var tex = ""
            for (pattern, group) in [(mathAltText, 1), (mathAnnotation, 2)] where tex.isEmpty {
                let part = source.substring(with: match.range(at: group))
                if let found = pattern.firstMatch(in: part, range: NSRange(location: 0, length: (part as NSString).length)) {
                    tex = (part as NSString).substring(with: found.range(at: 1))
                }
            }
            // Wikipedia wraps every formula in {\displaystyle …} and LaTeXML opens display math with it; it says nothing.
            if tex.hasPrefix("{\\displaystyle "), tex.hasSuffix("}") { tex = String(tex.dropFirst(15).dropLast()) }
            tex = tex.replacingOccurrences(of: "\\displaystyle", with: "")
            result.replaceCharacters(in: match.range, with: " \(tex.trimmingCharacters(in: .whitespaces)) ")
        }
        return result as String
    }

    private static func replace(_ regex: NSRegularExpression, in text: String, with template: String) -> String {
        regex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: template)
    }
}
