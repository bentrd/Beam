import Foundation

/// The single XML pass over a feed: recognises RSS 2.0, Atom and RDF by their root element and records the
/// fields Beam uses into a `RawFeed`. It decides nothing; `FeedItemBuilder` does.
final class FeedXMLReader: NSObject, XMLParserDelegate {
    private var feed: RawFeed?

    private var path: [String] = []
    private var entry: RawEntry?
    private var entryDepth = 0
    private var capture: Capture?
    /// A `<feed>` with no namespace at all: unprefixed names are Atom.
    private var treatsBareNamesAsAtom = false

    /// - Returns: nil when the root element is not a feed's (an HTML page, a sitemap), or the document has no root at all.
    static func read(_ xml: Data) -> RawFeed? {
        let reader = FeedXMLReader()
        let parser = XMLParser(data: xml)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        // A fatal error part-way through is not a reason to discard the entries already read: feeds get truncated.
        parser.parse()
        return reader.feed
    }

    // MARK: Element names

    /// Prefixes are the author's choice; namespace URIs are not. Known namespaces map to one fixed prefix so the
    /// rest of the reader can match on `media:description` whatever the feed called it.
    private static let prefixes: [String: String] = [
        "http://www.w3.org/2005/Atom": "atom", "http://purl.org/atom/ns#": "atom",
        "http://purl.org/rss/1.0/": "", "http://my.netscape.com/rdf/simple/0.9/": "",
        "http://purl.org/rss/1.0/modules/content/": "content",
        "http://search.yahoo.com/mrss/": "media", "http://search.yahoo.com/mrss": "media",
        "http://purl.org/dc/elements/1.1/": "dc",
        "http://www.w3.org/1999/02/22-rdf-syntax-ns#": "rdf",
    ]

    private func canonicalName(local: String, namespace: String?, qualified: String?) -> String {
        if let namespace, !namespace.isEmpty {
            guard let prefix = Self.prefixes[namespace] else { return "unknown:" + local }
            return prefix.isEmpty ? local : prefix + ":" + local
        }
        // No namespace: either genuinely bare (RSS 2.0) or a prefix the feed forgot to declare; the written name is the best guide.
        let written = qualified ?? local
        return treatsBareNamesAsAtom && !written.contains(":") ? "atom:" + written : written
    }

    // MARK: XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        if feed == nil {
            guard let format = format(forRoot: elementName, namespace: namespaceURI) else {
                parser.abortParsing()
                return
            }
            feed = RawFeed(format: format)
        }
        let name = canonicalName(local: elementName, namespace: namespaceURI, qualified: qualifiedName)
        path.append(name)

        if capture != nil {
            capture?.appendOpeningTag(elementName, attributes: attributes)
        } else if entry != nil {
            startEntryChild(name, attributes: attributes)
        } else if name == "item" || name == "atom:entry" {
            entry = RawEntry(about: attributes["rdf:about"])
            entryDepth = path.count
        } else {
            startFeedChild(name, attributes: attributes)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        capture?.appendText(string)
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        capture?.appendText(String(decoding: CDATABlock, as: UTF8.self))
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        // Nothing is open when the root was refused and parsing aborted.
        guard !path.isEmpty else { return }
        defer { path.removeLast() }
        if let active = capture {
            if path.count == active.depth {
                store(active)
                capture = nil
            } else {
                capture?.appendClosingTag(elementName)
            }
        } else if let finished = entry, path.count == entryDepth {
            feed?.entries.append(finished)
            entry = nil
        }
    }

    // MARK: Structure

    private func format(forRoot local: String, namespace: String?) -> ParsedFeed.Format? {
        // An undeclared prefix leaves "rdf:RDF" unsplit.
        switch local.split(separator: ":").last?.lowercased() ?? "" {
        case "rss": return .rss
        case "rdf": return .rdf
        case "feed":
            treatsBareNamesAsAtom = (namespace ?? "").isEmpty
            return .atom
        default: return nil
        }
    }

    private func startEntryChild(_ name: String, attributes: [String: String]) {
        let depthInEntry = path.count - entryDepth
        let insideMediaGroup = depthInEntry == 2 && path[path.count - 2] == "media:group"
        guard depthInEntry == 1 || insideMediaGroup else { return }
        switch name {
        case "title": begin(.title, kind: .looseTitle)
        case "atom:title", "dc:title": begin(.title, kind: Self.textKind(atomType: attributes["type"]))
        case "link": begin(.link)
        case "atom:link":
            if let link = Self.link(from: attributes) { entry?.links.append(link) }
        case "guid":
            entry?.guidIsPermalink = attributes["isPermaLink"]?.lowercased() != "false"
            begin(.guid)
        case "atom:id", "dc:identifier": begin(.guid)
        case "pubDate", "dc:date", "atom:published", "atom:issued", "atom:created": begin(.published)
        case "atom:updated", "atom:modified": begin(.updated)
        case "description": begin(.summary, kind: .html)
        case "atom:summary": begin(.summary, kind: Self.textKind(atomType: attributes["type"]))
        case "content:encoded": begin(.content, kind: .html)
        case "atom:content":
            // Anything that is not text (a base64 image, an out-of-line `src`) is of no use to a reader.
            let type = attributes["type"]?.lowercased() ?? "text"
            if type == "text" || type.contains("html") || type.hasPrefix("text/") { begin(.content, kind: Self.textKind(atomType: type)) }
        case "media:description": begin(.mediaDescription)
        case "media:title": begin(.mediaTitle)
        default: break
        }
    }

    /// Feed-level fields sit directly under `<channel>` (RSS, RDF) or under the Atom root; an `<image><title>` must not win.
    private func startFeedChild(_ name: String, attributes: [String: String]) {
        guard path.count >= 2 else { return }
        let parent = path[path.count - 2]
        guard parent == "channel" || (parent == "atom:feed" && path.count == 2) else { return }
        switch name {
        case "title": begin(.feedTitle, kind: .looseTitle)
        case "atom:title" where parent == "atom:feed": begin(.feedTitle, kind: Self.textKind(atomType: attributes["type"]))
        case "link": begin(.feedLink)
        case "atom:link" where parent == "atom:feed":
            if let link = Self.link(from: attributes) { feed?.links.append(link) }
        default: break
        }
    }

    private static func textKind(atomType: String?) -> RawText.Kind {
        (atomType ?? "text").lowercased().contains("html") ? .html : .plain
    }

    private static func link(from attributes: [String: String]) -> RawLink? {
        guard let href = attributes["href"], !href.isEmpty else { return nil }
        return RawLink(href: href, rel: attributes["rel"]?.lowercased() ?? "alternate", type: attributes["type"]?.lowercased())
    }

    // MARK: Capturing text

    private enum Field { case title, mediaTitle, link, guid, published, updated, summary, mediaDescription, content, feedTitle, feedLink }

    private func begin(_ field: Field, kind: RawText.Kind = .plain) {
        capture = Capture(field: field, kind: kind, depth: path.count)
    }

    /// The first value wins: a second `<title>` or `<link>` in the same entry is an extension repeating itself.
    private func store(_ finished: Capture) {
        let text = RawText(text: finished.text, kind: finished.sawMarkup ? .html : finished.kind)
        guard !text.isEmpty else { return }
        let plain = text.text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch finished.field {
        case .title: if entry?.title == nil { entry?.title = text }
        case .mediaTitle: if entry?.mediaTitle == nil { entry?.mediaTitle = text }
        case .link: if entry?.linkText == nil { entry?.linkText = plain }
        case .guid: if entry?.guid == nil { entry?.guid = plain }
        case .published: if entry?.published == nil { entry?.published = plain }
        case .updated: if entry?.updated == nil { entry?.updated = plain }
        case .summary: if entry?.summary == nil { entry?.summary = text }
        case .mediaDescription: if entry?.mediaDescription == nil { entry?.mediaDescription = text }
        case .content: if entry?.content == nil { entry?.content = text }
        case .feedTitle: if feed?.title == nil { feed?.title = text }
        case .feedLink: if feed?.siteLinkText == nil { feed?.siteLinkText = plain }
        }
    }

    /// Text being collected for one field. Child elements inside it (Atom `type="xhtml"`, or HTML a feed forgot to
    /// escape) are written back out as markup, so the field ends up as the HTML its author meant.
    private struct Capture {
        let field: Field
        let kind: RawText.Kind
        let depth: Int
        private(set) var text = ""
        private(set) var sawMarkup = false

        init(field: Field, kind: RawText.Kind, depth: Int) {
            self.field = field; self.kind = kind; self.depth = depth
        }

        private static let voidElements: Set<String> = ["br", "hr", "img", "input", "meta", "link", "wbr", "source", "col", "area"]

        mutating func appendText(_ string: String) {
            text += sawMarkup ? Self.escaped(string) : string
        }

        mutating func appendOpeningTag(_ name: String, attributes: [String: String]) {
            if !sawMarkup {
                // What was read so far came through the XML parser unescaped; it is about to sit beside real tags.
                text = Self.escaped(text)
                sawMarkup = true
            }
            text += "<" + name
            for (key, value) in attributes.sorted(by: { $0.key < $1.key }) where !key.hasPrefix("xmlns") {
                text += " \(key)=\"\(Self.escaped(value).replacingOccurrences(of: "\"", with: "&quot;"))\""
            }
            text += ">"
        }

        mutating func appendClosingTag(_ name: String) {
            if !Self.voidElements.contains(name.lowercased()) { text += "</\(name)>" }
        }

        private static func escaped(_ string: String) -> String {
            string.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
        }
    }
}
