import Foundation

/// Decides, element by element, what can never be article text.
///
/// Three verdicts, because the evidence differs in strength:
/// - `skip`: certain. Tags that hold no prose, hidden elements, page furniture named by HTML5 or ARIA, and
///   reference lists (EVIDENCE.md: Wikipedia's "↑ …" lines were extracted as passages and lit up).
/// - `suspect`: a class or id *suggests* furniture (comments, sidebars, share bars). Names lie often enough
///   ("content-sidebar-wrap" wraps whole pages) that the final decision waits until the page has been measured;
///   see `ContentSelector.resolve`.
/// - `keep`.
enum JunkFilter {
    enum Verdict: Equatable {
        case keep, skip
        /// `isStrong` is true for names that practically never label an article ("comments", "sidebar").
        case suspect(isStrong: Bool)
    }

    private static let skippedTags: Set<String> = [
        "script", "style", "noscript", "iframe", "button", "select", "option", "textarea", "input", "label", "object", "embed",
        "map", "area", "head", "link", "meta", "title", "hr", "col", "colgroup",
    ]
    private static let skippedMarkers: Set<String> = ["nav", "footer", "aside", "figcaption", "dialog", "search"]
    private static let skippedRoles: Set<String> = [
        "navigation", "banner", "contentinfo", "complementary", "search", "dialog", "alert", "alertdialog", "menu", "menubar",
        "toolbar", "tablist", "doc-bibliography", "doc-endnotes",
    ]
    /// Whole class names that mark reference and citation lists, on Wikipedia, LaTeXML (arXiv) and citation tools,
    /// plus LaTeXML's author block, which reads as "1] UMass Amherst 2] 3] Emory University".
    private static let referenceClasses: Set<String> = [
        "references", "reference", "reflist", "refbegin", "citation", "citations", "mw-references-wrap", "mw-cite-backlink",
        "bibliography", "ltx_bibliography", "ltx_bibitem", "ltx_note", "ltx_authors", "ltx_dates", "csl-bib-body",
    ]
    private static let strongTokens: Set<String> = [
        "comment", "comments", "disqus", "replies", "respond", "sidebar", "outbrain", "taboola", "newsletter", "cookie", "cookies",
        "consent", "gdpr", "breadcrumb", "breadcrumbs", "pagination", "navbox", "infobox", "catlinks", "editsection", "advert",
        "advertisement", "sponsor", "sponsored", "recirc", "masthead", "toc", "navbar", "navigation", "noprint", "hatnote",
        "sistersitebox", "thumbcaption", "byline", "dateline", "timestamp",
    ]
    private static let weakTokens: Set<String> = [
        "share", "sharing", "social", "related", "recommended", "trending", "popular", "promo", "subscribe", "signup", "popup",
        "modal", "widget", "widgets", "footer", "nav", "menu", "meta", "metadata", "author", "authors", "bio", "credit", "credits",
        "caption", "tags", "toolbar", "skip", "jump",
    ]
    /// A class name starting with one of these describes a state or a taxonomy ("has-sidebar", "tag-social",
    /// "no-comments"), not what the element is.
    private static let modifierPrefixes: Set<String> = [
        "has", "with", "without", "no", "not", "is", "hide", "hides", "show", "shows", "js", "tag", "category", "cat", "type",
        "format", "status",
    ]

    static func verdict(for element: XMLElement, named name: String) -> Verdict {
        if skippedTags.contains(name) { return .skip }
        if let marker = element.attribute(forName: HTMLPreprocessor.markerAttribute)?.stringValue {
            if skippedMarkers.contains(marker) { return .skip }
            // An author who wrote <article> or <main> has told us what this is; a class name does not outvote that.
            if marker == "article" || marker == "main" { return .keep }
        }
        if let role = element.attribute(forName: "role")?.stringValue?.lowercased(), skippedRoles.contains(role) { return .skip }

        let classes = element.attribute(forName: "class")?.stringValue ?? ""
        if isHidden(element), !classes.lowercased().contains("math") { return .skip }
        if name == "body" || name == "html" { return .keep }

        let identifier = element.attribute(forName: "id")?.stringValue ?? ""
        guard !classes.isEmpty || !identifier.isEmpty else { return .keep }
        var weak = false
        for className in (classes + " " + identifier).lowercased().split(whereSeparator: \.isWhitespace) {
            // Sphinx and docutils mark every ordinary prose link `class="reference"`, so anchors are exempt.
            if name != "a", referenceClasses.contains(String(className)) { return .skip }
            let tokens = className.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            guard let first = tokens.first, !modifierPrefixes.contains(first) else { continue }
            if tokens.contains(where: strongTokens.contains) { return .suspect(isStrong: true) }
            if tokens.contains(where: weakTokens.contains) { weak = true }
        }
        if weak || name == "form" { return .suspect(isStrong: false) }
        return .keep
    }

    /// Labels that sites drop between paragraphs. They are matched whole, so prose that merely mentions them is safe.
    private static let labels: Set<String> = [
        "advertisement", "advertisements", "sponsored", "sponsored content", "publicité", "anzeige", "share", "share this",
        "share this article", "read more", "continue reading", "related", "related articles", "loading…", "loading...",
    ]

    /// True for a block that is only an advertising or sharing label; merged into a neighbour it would read as the author's words.
    static func isLabel(_ text: String) -> Bool { text.count <= 24 && labels.contains(text.lowercased()) }

    /// A superscript that is nothing but a short link is a footnote or citation marker ("[12]"); left in, it glues
    /// digits onto the end of sentences.
    static func isNoteMarker(_ element: XMLElement) -> Bool {
        guard let text = element.stringValue, text.trimmingCharacters(in: .whitespacesAndNewlines).count <= 6 else { return false }
        return element.children?.contains { ($0 as? XMLElement)?.name?.lowercased() == "a" } ?? false
    }

    /// Images that are furniture rather than illustrations: spacers, tracking pixels, emoji, avatars, rendered formulas.
    static func isCountable(image: XMLElement) -> Bool {
        for side in ["width", "height"] {
            if let value = image.attribute(forName: side)?.stringValue, let points = Int(value), points < 48 { return false }
        }
        let classes = (image.attribute(forName: "class")?.stringValue ?? "").lowercased()
        return !["emoji", "avatar", "icon", "math", "pixel"].contains(where: classes.contains)
    }

    private static func isHidden(_ element: XMLElement) -> Bool {
        if element.attribute(forName: "hidden") != nil { return true }
        if element.attribute(forName: "aria-hidden")?.stringValue == "true" { return true }
        guard let style = element.attribute(forName: "style")?.stringValue else { return false }
        let compact = style.lowercased().filter { !$0.isWhitespace }
        return compact.contains("display:none") || compact.contains("visibility:hidden")
    }
}
