import CryptoKit
import Foundation

// MARK: Sources and items

public enum SourceKind: String, Codable, Sendable, CaseIterable {
    case feed, hackerNews, reddit, arxiv, githubReleases, youtube
}

public struct Source: Identifiable, Hashable, Codable, Sendable {
    public var id: Int64
    public var kind: SourceKind
    public var title: String
    public var feedURL: URL
    public var siteURL: URL?
    public var position: Int
    public var lastFetch: Date?
    public var lastError: String?
    /// When the current run of failures began; the sidebar warns only after 24 hours.
    public var failingSince: Date?

    public init(id: Int64 = 0, kind: SourceKind, title: String, feedURL: URL, siteURL: URL? = nil, position: Int = 0,
                lastFetch: Date? = nil, lastError: String? = nil, failingSince: Date? = nil) {
        self.id = id; self.kind = kind; self.title = title; self.feedURL = feedURL; self.siteURL = siteURL
        self.position = position; self.lastFetch = lastFetch; self.lastError = lastError; self.failingSince = failingSince
    }
}

/// A source the resolver found but that is not stored yet.
public struct SourceCandidate: Hashable, Codable, Sendable {
    public var kind: SourceKind
    public var title: String
    public var feedURL: URL
    public var siteURL: URL?
    public init(kind: SourceKind, title: String, feedURL: URL, siteURL: URL? = nil) {
        self.kind = kind; self.title = title; self.feedURL = feedURL; self.siteURL = siteURL
    }
}

/// One entry of the built-in catalog shown in the Add Source popover.
public struct CatalogEntry: Identifiable, Hashable, Sendable {
    public var id: String { candidate.feedURL.absoluteString }
    public var candidate: SourceCandidate
    public var blurb: String
    public var isStarter: Bool
    public init(candidate: SourceCandidate, blurb: String, isStarter: Bool = false) {
        self.candidate = candidate; self.blurb = blurb; self.isStarter = isStarter
    }
}

/// An item as parsed from a feed, before it is stored.
public struct FeedItem: Hashable, Codable, Sendable {
    public var guid: String
    public var url: URL?
    public var title: String
    /// Plain text, at most 300 characters.
    public var snippet: String
    /// Full HTML or text from the feed when it carries any.
    public var content: String?
    public var published: Date?
    public init(guid: String, url: URL?, title: String, snippet: String, content: String? = nil, published: Date? = nil) {
        self.guid = guid; self.url = url; self.title = title; self.snippet = snippet; self.content = content; self.published = published
    }
}

public struct Item: Identifiable, Hashable, Codable, Sendable {
    public var id: Int64
    public var sourceID: Int64
    public var guid: String
    public var url: URL?
    public var title: String
    public var snippet: String
    public var content: String?
    public var published: Date?
    public var fetched: Date
    public var opened: Date?
    public var read: Bool
    /// Set for release feeds only ("mlx"): a bare "v0.30.6" title is unjudgeable on its own (measured).
    public var repoName: String?

    public init(id: Int64 = 0, sourceID: Int64, guid: String, url: URL?, title: String, snippet: String, content: String? = nil,
                published: Date? = nil, fetched: Date = Date(), opened: Date? = nil, read: Bool = false, repoName: String? = nil) {
        self.id = id; self.sourceID = sourceID; self.guid = guid; self.url = url; self.title = title; self.snippet = snippet
        self.content = content; self.published = published; self.fetched = fetched; self.opened = opened; self.read = read; self.repoName = repoName
    }

    /// Exactly the text sent to the judge for list ranking. Never includes the source title, except the repo name of a release feed.
    public var judgedText: [String: String] {
        let shown = repoName.map { "\($0) \(title)" } ?? title
        return ["title": shown, "snippet": snippet]
    }

    /// Changes whenever the judged text changes, which makes older judgments unreachable ("not checked" until re-judged).
    public var textHash: String { Hashing.sha256(canonical: judgedText) }

    /// What list ordering uses: the feed's date, else when we first saw it.
    public var sortDate: Date { published ?? fetched }
}

public struct Pin: Identifiable, Hashable, Codable, Sendable {
    public var id: Int64
    public var sentence: String
    public var position: Int
    public var created: Date
    public var lastViewed: Date?
    public init(id: Int64 = 0, sentence: String, position: Int = 0, created: Date = Date(), lastViewed: Date? = nil) {
        self.id = id; self.sentence = sentence; self.position = position; self.created = created; self.lastViewed = lastViewed
    }
    public static let maximum = 9
}

// MARK: Articles

public struct Passage: Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable { case heading, paragraph, quote, listItem, code }
    public var kind: Kind
    public var text: String
    /// The nearest heading above, or "" — sent with the passage because context lifts recall (measured).
    public var section: String
    public init(kind: Kind, text: String, section: String = "") { self.kind = kind; self.text = text; self.section = section }
    /// Headings and code are shown but never judged.
    public var isJudgeable: Bool { kind == .paragraph || kind == .quote || kind == .listItem }
    public var textHash: String { Hashing.sha256(canonical: ["section": section, "passage": text]) }
}

public enum ArticleContent: Hashable, Codable, Sendable {
    case ready(passages: [Passage], images: Int, tables: Int)
    /// Thin text, HTTP error, paywall, JavaScript-only page. `reason` is for logs and help tags, not for the page.
    case unavailable(reason: String)
    /// Nothing to read in Beam (YouTube): Return opens the browser.
    case external
}

// MARK: Judgments

public enum Band: Int, Comparable, Codable, Sendable {
    case nothing, unsure, found
    public static func < (a: Band, b: Band) -> Bool { a.rawValue < b.rawValue }
}

/// The state of one judgment. "Not checked" (pending, failed, stale) is never the same thing as "nothing".
public enum Check: Hashable, Codable, Sendable {
    case judged(Double)
    case pending
    case failed
    /// Judged against text that has since changed.
    case stale

    public var probability: Double? { if case let .judged(p) = self { return p }; return nil }
    public var isChecked: Bool { probability != nil }
}

/// Thresholds measured in EVIDENCE.md. Lists judge a title and a snippet; articles judge whole paragraphs with context.
public enum Bands {
    public static let listFound = 0.60
    public static let listUnsure = 0.45
    public static let passageFound = 0.75
    public static let passageUnsure = 0.25
    /// Above this share of found paragraphs the sentence describes the whole article and marks are meaningless.
    public static let saturationShare = 0.35
    /// Never decide saturation before this many paragraphs are checked (or all of them, if fewer).
    public static let saturationMinimumChecked = 24

    public static func list(_ p: Double) -> Band { p >= listFound ? .found : (p >= listUnsure ? .unsure : .nothing) }
    public static func passage(_ p: Double) -> Band { p >= passageFound ? .found : (p > passageUnsure ? .unsure : .nothing) }
}

public enum KeyStatus: Hashable, Sendable {
    case missing
    case valid
    case rejected
    case unreachable
}

// MARK: Hashing

public enum Hashing {
    public static func sha256(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    /// Stable across runs and machines: keys sorted, no whitespace.
    public static func sha256(canonical dictionary: [String: String]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
