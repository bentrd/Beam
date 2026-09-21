import BeamExtract
import BeamModels
import Foundation

/// `ArticleLoader`'s per-source rules and failure taxonomy, against a stub network that serves the saved pages.
enum LoaderChecks {
    private static let prose = "Beam ranks everything you follow against one plain sentence, then opens each article with the matching paragraphs already lit. "

    static func run(_ report: inout CheckReport) async {
        await sources(&report)
        await failures(&report)
        await arxiv(&report)
    }

    private static func item(url: String?, content: String? = nil, title: String = "An item", snippet: String = "", guid: String = "guid") -> Item {
        Item(sourceID: 1, guid: guid, url: url.flatMap(URL.init(string:)), title: title, snippet: snippet, content: content)
    }

    private static func passages(_ content: ArticleContent) -> [Passage] {
        if case let .ready(passages, _, _) = content { return passages }
        return []
    }

    private static func reason(_ content: ArticleContent) -> String {
        if case let .unavailable(reason) = content { return reason }
        return "not unavailable: \(content)"
    }

    private static func sources(_ report: inout CheckReport) async {
        report.section("ArticleLoader: per-source rules")
        let network = StubFetcher()
        let loader = ArticleLoader(fetcher: network)

        report.expectEqual(await loader.load(item: item(url: "https://www.youtube.com/watch?v=abc"), sourceKind: .youtube), .external, "a YouTube source is external")
        report.expectEqual(await loader.load(item: item(url: "https://youtu.be/abc"), sourceKind: .hackerNews), .external, "a Hacker News link to YouTube is external too")

        let notes = "<h2>What's Changed</h2><ul><li>Fix a crash when the array is empty by @someone in <a href=\"/pull/1\">#1</a></li><li>Bump version</li></ul>"
        let release = await loader.load(item: item(url: "https://github.com/ml-explore/mlx/releases/tag/v0.30.6", content: notes, title: "v0.30.6"), sourceKind: .githubReleases)
        report.expectEqual(passages(release).map(\.kind), [.heading, .listItem], "GitHub releases read the feed's notes, however short")
        report.expect(passages(release).last?.text.hasSuffix("#1\u{2028}Bump version") == true, "with a short bullet kept on its own line")
        let empty = await loader.load(item: item(url: "https://github.com/a/b/releases/tag/v1", content: " "), sourceKind: .githubReleases)
        report.expect(reason(empty).contains("no notes"), "a release without notes is unavailable")

        let full = (1...12).map { "<p>Paragraph \($0). \(prose)</p>" }.joined()
        let fromFeed = await loader.load(item: item(url: "https://example.com/post", content: full), sourceKind: .feed)
        report.expectEqual(passages(fromFeed).count, 12, "feed content with 1,200+ characters of text is the article")
        report.expectEqual(network.requested, [], "and none of the above touched the network")

        guard let page = Fixture.named("blog-daringfireball.html"), let data = page.data else { report.expect(false, "blog-daringfireball.html is in the bundle"); return }
        let live = StubFetcher([page.url: .page(data, charset: page.httpCharset)])
        let fetched = await ArticleLoader(fetcher: live).load(item: item(url: page.url, content: "<p>\(prose)</p>"), sourceKind: .feed)
        report.expect(passages(fetched).count > 40, "feed content under 1,200 characters sends the loader to the page (\(passages(fetched).count) passages)")
        report.expectEqual(live.requested, [page.url], "with exactly one request")
        report.expect(!passages(fetched).contains { $0.kind == .heading && $0.text.contains("Rotten") } , "the page's own title heading is not repeated under Beam's title")
    }

    private static func failures(_ report: inout CheckReport) async {
        report.section("ArticleLoader: failures are .unavailable(reason:), never errors")
        for fixture in Fixture.all {
            guard case let .unavailable(expected) = fixture.expectation else { continue }
            guard let data = fixture.data else { report.expect(false, "\(fixture.file) is in the bundle"); continue }
            let loader = ArticleLoader(fetcher: StubFetcher([fixture.url: .page(data, charset: fixture.httpCharset)]))
            let content = await loader.load(item: item(url: fixture.url), sourceKind: .feed)
            report.expect(reason(content).contains(expected), "\(fixture.file) is unavailable: \(reason(content))")
        }

        let url = "https://example.com/post"
        func load(_ response: StubFetcher.Response?, content: String? = nil) async -> ArticleContent {
            await ArticleLoader(fetcher: StubFetcher(response.map { [url: $0] } ?? [:])).load(item: item(url: url, content: content), sourceKind: .feed)
        }
        let thinPage = Data("<html><body><p>\(prose)</p></body></html>".utf8)
        let hugePage = Data(repeating: 0x20, count: Readability.maximumBytes + 1)
        let cases: [(StubFetcher.Response, String, String)] = [
            (.failure(.http(status: 403)), "HTTP 403", "an HTTP error is unavailable"),
            (.failure(.notHTML(contentType: "application/pdf")), "application/pdf", "a PDF is unavailable"),
            (.failure(.transport("The request timed out.")), "timed out", "a timeout is unavailable"),
            (.page(thinPage, charset: nil), "Too little text", "thin text (under 150 words) is unavailable"),
            (.page(hugePage, charset: nil), "too large", "a body over 5 MB is unavailable"),
        ]
        for (response, expected, what) in cases {
            let content = await load(response)
            report.expect(reason(content).contains(expected), "\(what): \(reason(content))")
        }
        let unlinked = await ArticleLoader(fetcher: StubFetcher()).load(item: item(url: nil), sourceKind: .feed)
        report.expect(reason(unlinked).contains("no link"), "an item with neither link nor content is unavailable")

        let summary = "<p>" + String(repeating: "word ", count: 170) + "</p>"
        let rescued = await load(.failure(.http(status: 500)), content: summary)
        report.expectEqual(passages(rescued).count, 1, "when the page fails, 150+ words of feed content are shown instead")
        let teaser = await load(.failure(.http(status: 500)), content: "<p>\(prose)</p>")
        report.expectEqual(reason(teaser), "HTTP 500", "but a two-line summary is not passed off as the article")
    }

    private static func arxiv(_ report: inout CheckReport) async {
        report.section("ArticleLoader: arXiv")
        guard let paper = Fixture.named("arxiv-html.html"), let data = paper.data else { report.expect(false, "arxiv-html.html is in the bundle"); return }
        let abstract = "The dominant sequence transduction models are based on complex recurrent or convolutional\nneural networks that include an encoder and a decoder. " + prose
        let entry = item(url: "http://arxiv.org/abs/1706.03762v7", content: abstract, title: "Attention Is All You Need")

        let withHTML = StubFetcher(["https://arxiv.org/html/1706.03762v7": .page(data, charset: "utf-8")])
        let full = await ArticleLoader(fetcher: withHTML).load(item: entry, sourceKind: .arxiv)
        report.expect(passages(full).count > 80, "the paper's HTML version is read when arXiv has one (\(passages(full).count) passages)")
        report.expectEqual(withHTML.requested, ["https://arxiv.org/html/1706.03762v7"], "asking arxiv.org/html/<id> and nothing else")

        let withoutHTML = StubFetcher()
        let fallback = passages(await ArticleLoader(fetcher: withoutHTML).load(item: entry, sourceKind: .arxiv))
        report.expect(fallback.count == 1 && fallback[0].text.hasPrefix("The dominant sequence") && !fallback[0].text.contains("\n"), "without one, the abstract from the feed is the article (hard wraps joined)")

        let byGUID = item(url: nil, content: abstract, guid: "oai:arXiv.org:1706.03762v7")
        _ = await ArticleLoader(fetcher: withHTML).load(item: byGUID, sourceKind: .arxiv)
        report.expectEqual(withHTML.requested.count, 2, "the identifier is also found in an OAI GUID")

        let viaHackerNews = StubFetcher(["https://arxiv.org/html/1706.03762": .page(data, charset: "utf-8")])
        let linked = await ArticleLoader(fetcher: viaHackerNews).load(item: item(url: "https://arxiv.org/abs/1706.03762"), sourceKind: .hackerNews)
        report.expect(passages(linked).count > 80 && viaHackerNews.requested == ["https://arxiv.org/html/1706.03762"], "a Hacker News link to an abstract page reads the paper instead")
    }
}
