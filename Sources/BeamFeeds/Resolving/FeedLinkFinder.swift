import Foundation

/// Finds the feeds a web page advertises: `<link rel="alternate" type="application/rss+xml" href="…">`.
///
/// Worked on four sites of four (EVIDENCE.md). The tags are read with a scanner, not an HTML parser: they sit in
/// `<head>`, attribute order and quoting vary, and nothing else about the page matters here.
enum FeedLinkFinder {
    struct Advertised: Hashable {
        var url: URL
        /// The link's own `title`, if any ("Example » Comments Feed").
        var title: String
    }

    private static let feedTypes: Set<String> = ["application/rss+xml", "application/atom+xml", "application/rdf+xml"]

    /// Feeds in document order, without repeats. Relative `href`s resolve against the page's address.
    static func feeds(inHTML html: String, pageURL: URL) -> [Advertised] {
        var found: [Advertised] = []
        for tag in tags(named: "link", in: html) {
            let attributes = attributes(of: tag)
            let relations = (attributes["rel"] ?? "").lowercased().split(separator: " ")
            guard relations.contains("alternate"),
                  let type = attributes["type"]?.lowercased().split(separator: ";").first,
                  feedTypes.contains(type.trimmingCharacters(in: .whitespaces)),
                  let href = attributes["href"]?.trimmingCharacters(in: .whitespacesAndNewlines), !href.isEmpty,
                  let url = URL(string: href, relativeTo: pageURL)?.absoluteURL,
                  url.scheme == "http" || url.scheme == "https",
                  !found.contains(where: { $0.url == url }) else { continue }
            found.append(Advertised(url: url, title: attributes["title"] ?? ""))
        }
        return found
    }

    /// The page's `<title>`, as a name of last resort for a feed that has none.
    static func pageTitle(inHTML html: String) -> String? {
        guard let open = html.range(of: "<title", options: .caseInsensitive),
              let openEnd = html.range(of: ">", range: open.upperBound..<html.endIndex),
              let close = html.range(of: "</title", options: .caseInsensitive, range: openEnd.upperBound..<html.endIndex) else { return nil }
        let title = HTMLText.plainText(fromHTML: String(html[openEnd.upperBound..<close.lowerBound]))
        return title.isEmpty ? nil : title
    }

    // MARK: Scanning

    private static let attributePattern = try? NSRegularExpression(
        pattern: #"([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))"#)

    private static func tags(named name: String, in html: String) -> [Substring] {
        var tags: [Substring] = []
        var searchStart = html.startIndex
        while let open = html.range(of: "<" + name, options: .caseInsensitive, range: searchStart..<html.endIndex),
              let close = html.range(of: ">", range: open.upperBound..<html.endIndex) {
            // "<link" must be followed by a space or the like, or it is "<linkfoo".
            if html[open.upperBound].isWhitespace || html[open.upperBound] == "/" {
                tags.append(html[open.upperBound..<close.lowerBound])
            }
            searchStart = close.upperBound
        }
        return tags
    }

    /// Attribute names lowercased, values entity-decoded (`&amp;` in a query string is the usual case).
    private static func attributes(of tag: Substring) -> [String: String] {
        guard let pattern = attributePattern else { return [:] }
        let text = String(tag)
        var attributes: [String: String] = [:]
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let nameRange = Range(match.range(at: 1), in: text) else { continue }
            let value = (2...4).compactMap { Range(match.range(at: $0), in: text) }.first.map { String(text[$0]) } ?? ""
            attributes[text[nameRange].lowercased()] = HTMLText.decodeEntities(value)
        }
        return attributes
    }
}
