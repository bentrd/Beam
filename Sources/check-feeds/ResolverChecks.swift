import BeamFeeds
import BeamModels
import Foundation

/// A resolver on a canned internet, with gates that never really wait.
private func makeResolver(_ web: MockWeb, clock: FakeClock = FakeClock()) -> SourceResolver {
    SourceResolver(fetch: web.fetch, arxivGate: HostGate(minimumInterval: 3, clock: clock.pacing),
                   redditGate: HostGate(minimumInterval: 2, clock: clock.pacing))
}

func checkResolver(_ report: inout CheckReport) async {
    report.section("Resolver: host rules")

    var web = MockWeb()
    web.serve("https://github.com/ml-explore/mlx/releases.atom", body: Fixtures.githubReleases)
    for input in ["https://github.com/ml-explore/mlx", "github.com/ml-explore/mlx/tree/main/python", "https://github.com/ml-explore/mlx.git"] {
        let found = await makeResolver(web).resolve(input)
        report.expectEqual(found.first?.feedURL.absoluteString, "https://github.com/ml-explore/mlx/releases.atom", "GitHub: \(input)")
        report.expect(found.first?.kind == .githubReleases && found.first?.title == "mlx releases", "GitHub: kind and title", detail: "\(found)")
        report.expectEqual(found.first.flatMap { GitHubReleases.repoName(feedURL: $0.feedURL) }, "mlx", "GitHub: the candidate carries its repoName")
    }
    let missingRepository = await makeResolver(web).resolve("https://github.com/ml-explore/nonexistent")
    report.expect(missingRepository.isEmpty, "GitHub: a repository that does not answer is not offered")

    web = MockWeb()
    web.serve("https://www.youtube.com/feeds/videos.xml?channel_id=UCYO_jab_esuFRV4b17AJtAw", body: Fixtures.youtube)
    let channel = await makeResolver(web).resolve("https://www.youtube.com/channel/UCYO_jab_esuFRV4b17AJtAw/videos")
    report.expectEqual(channel.first?.feedURL.absoluteString, "https://www.youtube.com/feeds/videos.xml?channel_id=UCYO_jab_esuFRV4b17AJtAw", "YouTube: /channel/UC… becomes videos.xml?channel_id=")
    report.expect(channel.first?.kind == .youtube && channel.first?.title == "3Blue1Brown", "YouTube: kind, and the channel's name from its feed", detail: "\(channel)")

    web = MockWeb()
    web.serve("https://www.reddit.com/r/swift/.rss", body: Fixtures.reddit)
    for input in ["https://www.reddit.com/r/swift/", "old.reddit.com/r/swift/top?t=week", "r/swift"] {
        let found = await makeResolver(web).resolve(input)
        report.expect(found.first?.feedURL.absoluteString == "https://www.reddit.com/r/swift/.rss" && found.first?.kind == .reddit && found.first?.title == "r/swift",
                      "Reddit: \(input)", detail: "\(found)")
    }
    web = MockWeb()
    web.serve("https://www.reddit.com/r/swift/.rss", status: 429, headers: ["X-Ratelimit-Reset": "48"])
    let throttled = await makeResolver(web).resolve("reddit.com/r/swift")
    report.expectEqual(throttled.first?.title, "r/swift", "Reddit: offered unverified when Reddit says to slow down")
    report.expectEqual(web.requests.count, 1, "Reddit: a 48 s wait is not sat through while someone watches")
    let missingSubreddit = await makeResolver(MockWeb()).resolve("reddit.com/r/doesnotexist")
    report.expect(missingSubreddit.isEmpty, "Reddit: a subreddit that is not there is not offered")

    web = MockWeb()
    let arxivAddress = "https://export.arxiv.org/api/query?search_query=cat:cs.LG&sortBy=submittedDate&sortOrder=descending"
    for input in ["cs.LG", "cs.lg", "https://arxiv.org/list/cs.LG/recent", "arxiv.org/list/cs.LG/new"] {
        let found = await makeResolver(web).resolve(input)
        report.expect(found.first?.feedURL.absoluteString == arxivAddress && found.first?.kind == .arxiv && found.first?.title == "arXiv cs.LG", "arXiv: \(input)", detail: "\(found)")
    }
    let hackerNews = await makeResolver(web).resolve("https://news.ycombinator.com/newest")
    report.expect(hackerNews == [HackerNews.candidate] && hackerNews.first?.feedURL.absoluteString == "https://hn.algolia.com/api/v1/search?tags=front_page",
                  "Hacker News: any news.ycombinator.com address is the Algolia front page")
    report.expectEqual(web.requests.count, 0, "arXiv and Hacker News rules need no network")

    report.section("Resolver: discovery")
    web = MockWeb()
    web.serve("https://example.com/feed.xml", headers: ["Content-Type": "application/rss+xml"], body: Fixtures.simpleRSS(title: "Direct Feed"))
    let direct = await makeResolver(web).resolve("example.com/feed.xml")
    report.expect(direct.count == 1 && direct.first?.feedURL.absoluteString == "https://example.com/feed.xml" && direct.first?.title == "Direct Feed" && direct.first?.kind == .feed,
                  "the body is already a feed; a bare host gets https://", detail: "\(direct)")
    report.expectEqual(direct.first?.siteURL?.absoluteString, "https://example.com/", "the site link comes from the feed")
    let feedScheme = await makeResolver(web).resolve("feed://example.com/feed.xml")
    report.expectEqual(feedScheme.first?.title, "Direct Feed", "feed:// addresses are understood")

    web = MockWeb()
    web.serve("https://example.com/blog/journal/", body: Fixtures.htmlPage)
    web.serve("https://example.com/blog/atom.xml?lang=en&full=1", body: Fixtures.simpleRSS(title: "The Journal"))
    web.serve("https://example.com/comments/feed/", body: Fixtures.simpleRSS(title: "Comments on the Journal"))
    let advertised = await makeResolver(web).resolve("https://example.com/blog/journal/")
    report.expectEqual(advertised.map(\.feedURL.absoluteString), ["https://example.com/blog/atom.xml?lang=en&full=1"],
                       "<link rel=alternate>: relative href with &amp;, any attribute order or quoting; comments feed and JSON left out")
    report.expectEqual(advertised.first?.title, "The Journal", "an advertised feed is fetched and names itself")
    report.expect(!web.requestedURLs.contains("https://example.com/feed.json"), "only RSS and Atom links are followed")

    web = MockWeb()
    web.serve("https://twice.example.com/", body: #"<link rel="alternate" type="application/rss+xml" href="/rss.xml"><link rel="alternate" type="application/atom+xml" href="/atom.xml"><link rel="alternate" type="application/rss+xml" title="Links" href="/links.xml">"#)
    web.serve("https://twice.example.com/rss.xml", body: Fixtures.simpleRSS(title: "Twice"))
    web.serve("https://twice.example.com/atom.xml", body: Fixtures.simpleRSS(title: "Twice"))
    web.serve("https://twice.example.com/links.xml", body: Fixtures.simpleRSS(title: "Twice: Links"))
    let twice = await makeResolver(web).resolve("twice.example.com")
    report.expectEqual(twice.map(\.feedURL.lastPathComponent), ["rss.xml", "links.xml"], "one feed offered as RSS and as Atom is one candidate; a different feed is another")

    web = MockWeb()
    web.serve("https://quiet.example.com/", body: Fixtures.bareHTMLPage)
    web.serve("https://quiet.example.com/index.xml", body: Fixtures.simpleRSS(title: ""))
    web.serve("https://quiet.example.com/feed.xml", body: Fixtures.simpleRSS(title: "Later in the list"))
    let guessed = await makeResolver(web).resolve("quiet.example.com")
    report.expectEqual(guessed.map(\.feedURL.absoluteString), ["https://quiet.example.com/index.xml"], "common paths: the first that answers with a feed, in the listed order")
    report.expectEqual(guessed.first?.title, "No feeds advertised", "a feed without a title takes the page's")
    report.expect(["/feed", "/rss", "/atom.xml", "/index.xml", "/feed.xml"].allSatisfy { web.requestedURLs.contains("https://quiet.example.com" + $0) }, "all five common paths are tried")

    web = MockWeb()
    web.serve("https://walled.example.com/notes", status: 403)
    web.serve("https://walled.example.com/notes/feed", body: Fixtures.simpleRSS(title: "Notes"))
    let walled = await makeResolver(web).resolve("https://walled.example.com/notes")
    report.expectEqual(walled.first?.feedURL.absoluteString, "https://walled.example.com/notes/feed", "a page that refuses us can still have a feed beside it")

    web = MockWeb()
    web.serve("https://nothing.example.com/", body: Fixtures.bareHTMLPage)
    let nothing = await makeResolver(web).resolve("https://nothing.example.com/")
    report.expect(nothing.isEmpty, "no feed anywhere: nothing is offered")
    for junk in ["", "   ", "not a url at all", "ftp://example.com/feed", "justaword"] {
        let before = web.requests.count
        let found = await makeResolver(web).resolve(junk)
        report.expect(found.isEmpty && web.requests.count == before, "\"\(junk)\" resolves to nothing without touching the network")
    }

    web = MockWeb()
    web.serve("https://export.arxiv.org/api/query?search_query=cat:stat.ML&sortBy=submittedDate&max_results=100", body: Fixtures.arxiv)
    let clock = FakeClock()
    let pasted = await makeResolver(web, clock: clock).resolve("https://export.arxiv.org/api/query?search_query=cat:stat.ML&sortBy=submittedDate")
    report.expect(pasted.first?.kind == .arxiv && pasted.first?.feedURL.absoluteString == "https://export.arxiv.org/api/query?search_query=cat:stat.ML&sortBy=submittedDate",
                  "a pasted arXiv query keeps its address and is read through the arXiv adapter", detail: "\(pasted)")
}
