import BeamFeeds
import BeamModels
import Foundation

private func source(_ id: Int64, _ kind: SourceKind, _ address: String) -> Source {
    Source(id: id, kind: kind, title: "Source \(id)", feedURL: URL(string: address) ?? HackerNews.feedURL)
}

private func makeRefresher(_ web: MockWeb, timeout: TimeInterval = 15) -> Refresher {
    let clock = FakeClock()
    return Refresher(fetch: web.fetch, timeout: timeout, arxivGate: HostGate(minimumInterval: 3, clock: clock.pacing),
                     redditGate: HostGate(minimumInterval: 2, clock: clock.pacing))
}

func checkRefresher(_ report: inout CheckReport) async {
    report.section("Refresher: bounded, and one bad source never sinks the rest")
    var web = MockWeb()
    var sources: [Source] = []
    for index in 1...20 {
        let address = "https://site\(index).example.com/feed"
        sources.append(source(Int64(index), .feed, address))
        web.serve(address) { request in
            try await Task.sleep(nanoseconds: 30_000_000)
            return HTTPResponse(url: request.url, status: 200, body: Data(Fixtures.simpleRSS(title: "Site \(index)", items: 3).utf8))
        }
    }
    web.serve("https://site4.example.com/feed", status: 500)
    web.serve("https://site9.example.com/feed", body: Fixtures.bareHTMLPage)
    web.serve("https://site13.example.com/feed") { _ in throw URLError(.notConnectedToInternet) }
    sources.append(source(21, .feed, "https://missing.example.com/feed"))

    let results = await makeRefresher(web).refreshAll(sources)
    report.expectEqual(results.map(\.source.id), sources.map(\.id), "one result per source, in the order asked")
    report.expectEqual(web.peakConcurrency, 6, "never more than six requests on the wire (and six are used)")
    report.expectEqual(results.filter { $0.items.count == 3 }.count, 17, "seventeen good feeds deliver their items")
    let failures = Dictionary(uniqueKeysWithValues: results.compactMap { result in result.error.map { (result.source.id, $0) } })
    report.expect(failures == [4: .http(status: 500), 9: .notAFeed, 13: .offline, 21: .http(status: 404)], "each failure is reported for its own source", detail: "\(failures)")
    report.expectEqual(FeedError.http(status: 404).reason, "the feed is gone (HTTP 404)", "a reason finishes the sentence \"Couldn't refresh: …\"")
    for delay in [Double.infinity, Double.nan, Double.greatestFiniteMagnitude] {
        report.expectEqual(FeedError.rateLimited(retryAfter: delay).reason, "the server asked Beam to slow down",
                           "an unrepresentable rate-limit delay remains a source error, never a crash")
    }

    report.section("Refresher: timeout")
    web = MockWeb()
    web.serve("https://slow.example.com/feed") { request in
        try await Task.sleep(nanoseconds: 5_000_000_000)
        return HTTPResponse(url: request.url, status: 200)
    }
    web.serve("https://fast.example.com/feed", body: Fixtures.simpleRSS(title: "Fast"))
    let started = Date()
    let timed = await makeRefresher(web, timeout: 0.2).refreshAll([source(1, .feed, "https://slow.example.com/feed"), source(2, .feed, "https://fast.example.com/feed")])
    report.expect(timed.first?.error == .timedOut && timed.last?.items.count == 1, "a feed slower than the limit fails as timed out; its neighbour is unaffected")
    report.expect(Date().timeIntervalSince(started) < 2, "the refresh does not wait for the slow server", detail: "\(Date().timeIntervalSince(started)) s")
    report.expectEqual(HTTPClient.timeout, 15, "the real limit is 15 s")

    report.section("Refresher: conditional GET")
    web = MockWeb()
    web.serve("https://etag.example.com/feed") { request in
        if request.headers["If-None-Match"] == "\"v1\"", request.headers["If-Modified-Since"] == "Mon, 21 Sep 2026 07:00:00 GMT" {
            return HTTPResponse(url: request.url, status: 304)
        }
        return HTTPResponse(url: request.url, status: 200, headers: ["etag": "\"v1\"", "Last-Modified": "Mon, 21 Sep 2026 07:00:00 GMT"],
                            body: Data(Fixtures.simpleRSS(title: "Validated", items: 2).utf8))
    }
    web.serve("https://broken.example.com/feed", headers: ["ETag": "\"bad\""], body: Fixtures.bareHTMLPage)
    let refresher = makeRefresher(web)
    let validated = source(7, .feed, "https://etag.example.com/feed"), broken = source(8, .feed, "https://broken.example.com/feed")
    let firstPass = await refresher.refreshAll([validated, broken])
    let secondPass = await refresher.refreshAll([validated, broken])
    report.expectEqual(firstPass.first?.items.count, 2, "first fetch: full body")
    report.expect({ if case .notModified = secondPass.first?.outcome { return true } else { return false } }(), "second fetch echoes ETag and Last-Modified and gets 304: not modified")
    report.expect(web.requests.filter { $0.url.host == "broken.example.com" }.allSatisfy { $0.headers["If-None-Match"] == nil }, "validators of a response that did not parse are never echoed")
    let readded = await refresher.refreshAll([source(99, .feed, "https://etag.example.com/feed")])
    report.expectEqual(readded.first?.items.count, 2, "the same address under a new source id is fetched in full (removed, then added again)")

    report.section("Refresher: adapters by kind")
    web = MockWeb()
    web.serve("https://hn.algolia.com/api/v1/search?tags=front_page&hitsPerPage=30", body: Fixtures.hackerNews)
    web.serve("https://export.arxiv.org/api/query?search_query=cat:cs.LG&sortBy=submittedDate&sortOrder=descending&max_results=100", body: Fixtures.arxiv)
    web.serve("https://www.reddit.com/r/swift/.rss", body: Fixtures.reddit)
    web.serve("https://github.com/ml-explore/mlx/releases.atom", body: Fixtures.githubReleases)
    let arxivFeed = Arxiv.feedURL(category: "cs.LG")?.absoluteString ?? ""
    let byKind = await makeRefresher(web).refreshAll([
        source(1, .hackerNews, HackerNews.feedURL.absoluteString), source(2, .arxiv, arxivFeed),
        source(3, .reddit, "https://www.reddit.com/r/swift/.rss"), source(4, .githubReleases, "https://github.com/ml-explore/mlx/releases.atom"),
    ])
    guard byKind.count == 4 else { return report.expect(false, "four kinds refresh") }
    report.expectEqual(byKind[0].items.count, 2, "Hacker News: the whole front page is asked for (hitsPerPage=30) and decoded")
    report.expect(web.requests.first { $0.url.host == "hn.algolia.com" }?.headers["Accept"] == "application/json", "Hacker News: asks for JSON")

    let paper = byKind[1].items.first
    report.expectEqual(paper?.guid, "https://arxiv.org/abs/2609.01234", "arXiv: identity drops the version, so a revision is an edit")
    report.expectEqual(paper?.url?.absoluteString, "https://arxiv.org/abs/2609.01234v2", "arXiv: the link moves to https")
    report.expectEqual(paper?.title, "Sparse Attention on Unified Memory: A Study", "arXiv: line breaks inside a title collapse")
    report.expect((paper?.snippet.count ?? 0) <= 300 && (paper?.content?.count ?? 0) > 600, "arXiv: snippet capped, the whole abstract kept as content")
    report.expectEqual(paper?.published, Date(timeIntervalSince1970: 1_789_750_800), "arXiv: sorted by submission date, not by revision")

    let posts = byKind[2].items
    report.expectEqual(posts.first?.snippet, "Is structured concurrency worth adopting in an old codebase?", "Reddit: \"submitted by /u/… [link] [comments]\" is not part of the post")
    report.expect(posts.count == 2 && posts[1].snippet.isEmpty && posts[1].content == nil, "Reddit: a link post has a title and nothing else", detail: "\(posts.last?.snippet ?? "")")
    report.expect(web.requests.first { $0.url.host == "www.reddit.com" } != nil, "Reddit: fetched through its gate")

    report.expect(byKind[3].repoName == "mlx" && byKind[0].repoName == nil, "GitHub: the result names the repository; others do not")
}
