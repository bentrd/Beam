import Foundation

/// What the XML pass collects, before any judgment about which title, link or date wins.
/// Keeping the two steps apart lets the reader stay a dumb recorder and the builder stay free of parser state.
struct RawFeed {
    var format: ParsedFeed.Format
    var title: RawText?
    var siteLinkText: String?
    var links: [RawLink] = []
    var entries: [RawEntry] = []
}

struct RawEntry {
    var title: RawText?
    var mediaTitle: RawText?
    var linkText: String?
    var links: [RawLink] = []
    var guid: String?
    /// RSS says a `<guid>` is a permalink unless it declares otherwise.
    var guidIsPermalink = true
    /// RDF identifies an item by its `rdf:about` attribute.
    var about: String?
    var published: String?
    var updated: String?
    var summary: RawText?
    var mediaDescription: RawText?
    var content: RawText?
}

/// An Atom `<link>`: the address lives in attributes, and `rel` says what it is for.
struct RawLink {
    var href: String
    var rel: String
    var type: String?
}

struct RawText {
    enum Kind {
        /// Literal text: Atom `type="text"`, Media RSS. "a < b" means exactly that.
        case plain
        /// HTML: RSS descriptions, `content:encoded`, Atom `type="html"` and `type="xhtml"`.
        case html
        /// An RSS title: nominally plain, in practice escaped entities and the odd `<em>`.
        case looseTitle
    }
    var text: String
    var kind: Kind

    var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
