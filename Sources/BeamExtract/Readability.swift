import BeamModels
import Foundation

/// The readable text of one page, as passages, plus what had to be left out.
public struct ExtractedArticle: Hashable, Sendable {
    /// The page's own title (`og:title`, else `<title>`). Beam shows the feed's title; this one is for checks and logs.
    public var title: String
    public var passages: [Passage]
    /// Images and data tables inside the article that Beam does not show ("Open Original (4 images, 2 tables)").
    public var images: Int
    public var tables: Int
    /// Words in everything but headings: the measure of whether there is an article here at all. Code counts,
    /// because an article that is mostly code is still an article ("Code not checked." in the reader's foot).
    public var wordCount: Int
    /// True when the markup held nothing readable and the text came from JSON-LD `articleBody`.
    public var usedEmbeddedBody: Bool
    /// The publisher marks the article as not free to read; short text is then a teaser, not an article.
    public var declaresPaywall: Bool
    /// The page asks for JavaScript or is an empty application shell.
    public var needsJavaScript: Bool

    public var asContent: ArticleContent { .ready(passages: passages, images: images, tables: tables) }

    /// Stamps every passage with the article's title, which is part of the text each one is judged on and so
    /// part of its cache key. Done here, where the title and the passages first meet, because a passage that
    /// travelled without it would be judged in one article and answered for from another.
    public init(title: String, passages: [Passage], images: Int, tables: Int, wordCount: Int,
                usedEmbeddedBody: Bool, declaresPaywall: Bool, needsJavaScript: Bool) {
        self.title = title
        self.passages = passages.map { var passage = $0; passage.article = title; return passage }
        self.images = images
        self.tables = tables
        self.wordCount = wordCount
        self.usedEmbeddedBody = usedEmbeddedBody
        self.declaresPaywall = declaresPaywall
        self.needsJavaScript = needsJavaScript
    }
}

/// Dependency-free article extraction: Beam's own decoding, a pass that makes HTML5 survive tidy, Foundation's
/// `XMLDocument` in tidy mode, then block walking, container selection and the passage rules.
/// Measured in the spike at 7-113 ms a page.
public enum Readability {
    /// Bodies over this size are refused: they are not articles, and tidy's time and memory grow with them.
    public static let maximumBytes = 5 * 1_048_576
    /// The most wall-clock time one page may take after download, unless the caller asks for less.
    public static let timeBudget: Duration = .seconds(3)
    /// Under this many words the markup is judged to hold no article, and the wider fallbacks are tried.
    public static let minimumWords = 150

    /// Extracts the article from a downloaded page. `knownTitle` (the feed's title) lets a repeated first heading be dropped.
    public static func extract(data: Data, httpCharset: String?, knownTitle: String? = nil,
                               timeBudget: Duration = Readability.timeBudget) throws -> ExtractedArticle {
        guard data.count <= maximumBytes else { throw ExtractionError.tooLarge(bytes: data.count) }
        return try extract(html: TextDecoder.decode(data, httpCharset: httpCharset), knownTitle: knownTitle, timeBudget: timeBudget)
    }

    public static func extract(html: String, knownTitle: String? = nil, timeBudget: Duration = Readability.timeBudget) throws -> ExtractedArticle {
        guard html.utf8.count <= maximumBytes else { throw ExtractionError.tooLarge(bytes: html.utf8.count) }
        // Content-Type cannot be trusted: servers that content-negotiate an ActivityPub or API representation
        // still label it `text/html`, and handed to the parser that JSON becomes one giant paragraph of
        // `{"@context":…` in the reader. Read the post out of it where it is there, refuse where it is not.
        switch JSONPage.body(of: html) {
        case let .fragment(body): return try extractFragment(body, knownTitle: knownTitle)
        case .notAPage: throw ExtractionError.notAPage
        case nil: break
        }
        let deadline = Deadline(budget: timeBudget)
        let signals = PageSignals(html: html)
        let page = try WalkedPage(html: html, deadline: deadline)
        let titles = [knownTitle, page.title].compactMap { $0 }

        var best = page.article(in: page.selectedRange(), titles: titles)
        // The spike's fallbacks, in order: a wider container, then the text the publisher embedded for search engines.
        if best.wordCount < minimumWords {
            let whole = page.article(in: page.wholeRange, titles: titles)
            if whole.wordCount > best.wordCount { best = whole }
        }
        if best.wordCount < minimumWords, let fragment = EmbeddedBody.fragment(in: html) {
            var embedded = try extractFragment(fragment, knownTitle: knownTitle)
            if embedded.wordCount > best.wordCount { embedded.usedEmbeddedBody = true; embedded.title = page.title; best = embedded }
        }
        best.declaresPaywall = signals.declaresPaywall
        best.needsJavaScript = signals.needsJavaScript
        return best
    }

    /// Extracts feed content (`content:encoded`, Atom `content`, release notes): the whole fragment is the article,
    /// so nothing is selected, but junk, references and the passage rules apply as they do to pages.
    public static func extractFragment(_ html: String, knownTitle: String? = nil) throws -> ExtractedArticle {
        guard html.utf8.count <= maximumBytes else { throw ExtractionError.tooLarge(bytes: html.utf8.count) }
        let page = try WalkedPage(html: "<html><body>\(html)</body></html>", deadline: Deadline(budget: timeBudget))
        return page.article(in: page.wholeRange, titles: [knownTitle].compactMap { $0 })
    }
}

/// One parsed and walked page: everything `Readability` needs to try a range and, if it is thin, a wider one,
/// without parsing twice.
private struct WalkedPage {
    let document: XMLDocument
    let body: XMLElement?
    let blocks: [Block]
    let selector: ContentSelector
    let title: String

    init(html: String, deadline: Deadline) throws {
        let prepared = HTMLPreprocessor.prepare(html)
        try deadline.check()
        // Tidy refuses very little (an empty string, mostly). A page it refuses has no markup to read, which is
        // not an error: the embedded-body fallback may still find the article.
        let parsed = (try? XMLDocument(xmlString: prepared, options: [.documentTidyHTML, .nodeLoadExternalEntitiesNever])) ?? XMLDocument()
        try deadline.check()
        document = parsed
        body = (try? parsed.nodes(forXPath: "//body"))?.first as? XMLElement

        let walker = BlockWalker(deadline: deadline)
        if let body { try walker.walk(body) }
        blocks = walker.blocks
        selector = ContentSelector(blocks: walker.blocks, ranges: walker.ranges, suspects: walker.suspects)

        let openGraph = (try? parsed.nodes(forXPath: "//meta[@property='og:title']/@content"))?.first?.stringValue
        let plain = (try? parsed.nodes(forXPath: "//title"))?.first?.stringValue
        title = TextCleaner.collapse(openGraph ?? plain ?? "")
    }

    var wholeRange: Range<Int> { 0..<blocks.count }

    func selectedRange() -> Range<Int> {
        guard let body else { return wholeRange }
        return selector.select(in: document, body: body)
    }

    func article(in range: Range<Int>, titles: [String]) -> ExtractedArticle {
        let kept = range.filter { selector.isKept[$0] }.map { blocks[$0] }
        let passages = Passages.assemble(kept, titles: titles)
        let words = passages.filter { $0.kind != .heading }.reduce(0) { $0 + TextCleaner.wordCount($1.text) }
        return ExtractedArticle(title: title, passages: passages,
                                images: kept.filter { $0.kind == .image }.count, tables: kept.filter { $0.kind == .table }.count,
                                wordCount: words, usedEmbeddedBody: false, declaresPaywall: false, needsJavaScript: false)
    }
}
