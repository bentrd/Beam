import BeamModels
import Foundation

/// A feed as Beam sees it: enough to name a source and to list its items.
public struct ParsedFeed: Hashable, Sendable {
    public enum Format: String, Sendable { case rss, atom, rdf }
    public var format: Format
    /// Plain text; empty when the feed names itself nowhere.
    public var title: String
    /// The human-readable site the feed belongs to, when it says.
    public var siteURL: URL?
    /// In feed order, one per identity.
    public var items: [FeedItem]
}

/// Reads RSS 2.0, Atom and RDF (RSS 1.0), as found in the wild rather than as specified.
///
/// Tolerated: byte-order marks and leading junk, declared non-UTF-8 encodings, HTML entities and bare ampersands,
/// control characters, CDATA, unescaped or XHTML markup inside text fields, `content:encoded`, Media RSS
/// (YouTube's `media:group`), six date shapes, relative links, missing GUIDs, and documents cut off mid-way
/// (the entries read before the break are kept).
public enum FeedParser {
    /// - Parameters:
    ///   - feedURL: where the bytes came from, after redirects; relative links resolve against it.
    ///   - charsetHint: the HTTP `charset`, consulted only when the document itself does not say.
    ///   - now: the reference for rejecting dates from the future; injectable so checks are repeatable.
    /// - Throws: `FeedError.notAFeed` when the document is not RSS, Atom or RDF at all.
    public static func parse(_ data: Data, feedURL: URL, charsetHint: String? = nil, now: Date = Date()) throws -> ParsedFeed {
        guard let raw = FeedXMLReader.read(FeedText.repairedXML(from: data, charsetHint: charsetHint)) else { throw FeedError.notAFeed }

        let builder = FeedItemBuilder(baseURL: feedURL, now: now)
        var seen = Set<String>()
        let items = raw.entries.compactMap(builder.item).filter { seen.insert($0.guid).inserted }

        let siteLink = raw.siteLinkText ?? raw.links.first(where: { $0.rel == "alternate" && $0.type?.contains("html") != false })?.href
        return ParsedFeed(format: raw.format, title: raw.title.map(FeedItemBuilder.plainTitle) ?? "",
                          siteURL: siteLink.flatMap(builder.resolve), items: items)
    }

    /// A cheap test the resolver runs on whatever a URL returned, before paying for a full parse:
    /// does a feed's root element open within the first kilobytes?
    public static func looksLikeFeed(_ data: Data) -> Bool {
        let head = FeedText.decode(data.prefix(4096)).lowercased()
        guard let root = ["<rss", "<feed", "<rdf:rdf"].compactMap({ head.range(of: $0)?.lowerBound }).min() else { return false }
        // An HTML page that merely mentions "<feed" in a script is not a feed: the root must come before any markup of a page.
        return !head[..<root].contains("<html") && !head[..<root].contains("<body")
    }
}
