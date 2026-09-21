import BeamModels
import Foundation

/// Gets the text of one item, by the per-source rules of PRODUCT.md section 6.
///
/// | Source | Text |
/// |---|---|
/// | YouTube (source or link) | none: `.external`, Return opens the browser |
/// | GitHub releases | the feed's release notes, however short |
/// | arXiv | `arxiv.org/html/<id>`, else the abstract from the feed |
/// | anything else | feed content when it holds 1,200+ characters of text, else the page |
///
/// Failures never throw: thin text, HTTP errors, non-HTML, paywalls and JavaScript-only shells all come back as
/// `.unavailable(reason:)`, and the reader shows its one calm sentence. A cancelled load also reports
/// `.unavailable`; callers that cache results must check `Task.isCancelled` first.
public struct ArticleLoader: Sendable {
    /// Feed content with at least this much text is taken to be the whole article (PRODUCT.md).
    public static let feedContentMinimumCharacters = 1200
    /// A publisher-declared paywall with less text than this is showing a teaser, and a teaser is not the article.
    public static let paywalledMinimumWords = 400

    private let fetcher: any PageFetching

    public init(fetcher: any PageFetching = PageFetcher()) { self.fetcher = fetcher }

    public func load(item: Item, sourceKind: SourceKind) async -> ArticleContent {
        let feed = feedArticle(for: item)

        switch sourceKind {
        case .youtube:
            return .external
        case .githubReleases:
            if let feed, !feed.passages.isEmpty { return feed.asContent }
            return .unavailable(reason: "The release has no notes")
        case .arxiv:
            if let page = await arxivPaper(ArxivID.find(in: item), title: item.title) { return page }
            if let feed, !feed.passages.isEmpty { return feed.asContent }
            let abstract = Passages.fromPlainText(item.snippet)
            guard !abstract.isEmpty else { return .unavailable(reason: "No HTML version and no abstract") }
            return .ready(passages: abstract.map { var passage = $0; passage.article = item.title; return passage },
                          images: 0, tables: 0)
        case .feed, .hackerNews, .reddit:
            if item.url.map(Self.isVideoPage) == true { return .external }
            if let feed, Self.characters(in: feed) >= Self.feedContentMinimumCharacters { return feed.asContent }
            guard let url = item.url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
                if let feed, !feed.passages.isEmpty { return feed.asContent }
                return .unavailable(reason: "The item has no link")
            }
            if let page = await arxivPaper(ArxivID.find(in: url), title: item.title) { return page }
            let page = await self.page(at: url, title: item.title)
            // A feed entry too short to be trusted as the whole article still beats nothing when the page fails.
            if case .unavailable = page, let feed, feed.wordCount >= Readability.minimumWords { return feed.asContent }
            return page
        }
    }

    // MARK: Pages

    private func page(at url: URL, title: String) async -> ArticleContent {
        do {
            let fetched = try await fetcher.fetch(url)
            let article = try Readability.extract(data: fetched.data, httpCharset: fetched.charset, knownTitle: title)
            return Self.verdict(on: article)
        } catch let failure as FetchFailure {
            return .unavailable(reason: failure.description)
        } catch let error as ExtractionError {
            return .unavailable(reason: error.description)
        } catch is CancellationError {
            return .unavailable(reason: "Cancelled")
        } catch {
            return .unavailable(reason: error.localizedDescription)
        }
    }

    /// The full paper, when arXiv has an HTML version of it. Nil means "fall back", never "failed".
    private func arxivPaper(_ identifier: String?, title: String) async -> ArticleContent? {
        guard let identifier, let url = ArxivID.htmlURL(for: identifier) else { return nil }
        let page = await self.page(at: url, title: title)
        if case .ready = page { return page }
        return nil
    }

    /// The failure taxonomy: what was extracted is an article only if there is enough of it.
    static func verdict(on article: ExtractedArticle) -> ArticleContent {
        let words = article.wordCount
        if article.declaresPaywall, words < paywalledMinimumWords { return .unavailable(reason: "Paywalled: only \(words) words are public") }
        guard words < Readability.minimumWords else { return article.asContent }
        if article.needsJavaScript { return .unavailable(reason: "The page needs JavaScript to show its text (\(words) words without it)") }
        return .unavailable(reason: "Too little text (\(words) words)")
    }

    // MARK: Feed content

    /// The item's own content as passages, whether the feed carried HTML or plain text. Nil when it carried nothing usable.
    private func feedArticle(for item: Item) -> ExtractedArticle? {
        guard let content = item.content, !content.allSatisfy(\.isWhitespace) else { return nil }
        if content.range(of: "</?[A-Za-z][^>]*>", options: .regularExpression) != nil {
            return try? Readability.extractFragment(content, knownTitle: item.title)
        }
        let passages = Passages.fromPlainText(content)
        let words = passages.reduce(0) { $0 + TextCleaner.wordCount($1.text) }
        return ExtractedArticle(title: item.title, passages: passages, images: 0, tables: 0, wordCount: words,
                                usedEmbeddedBody: false, declaresPaywall: false, needsJavaScript: false)
    }

    private static func characters(in article: ExtractedArticle) -> Int { article.passages.reduce(0) { $0 + $1.text.count } }

    /// A link to a video has nothing to read, whichever source it came from (Hacker News links to YouTube daily).
    private static func isVideoPage(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "youtu.be" || host == "youtube.com" || host.hasSuffix(".youtube.com")
    }
}
