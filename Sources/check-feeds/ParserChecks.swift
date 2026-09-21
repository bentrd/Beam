import BeamFeeds
import BeamModels
import Foundation

/// 21 September 2026, 12:00 UTC: "now" for every parse, so the future-date rule is tested against a fixed day.
private let referenceNow = Date(timeIntervalSince1970: 1_789_992_000)

private func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date? {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? calendar.timeZone
    return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))
}

private func parse(_ xml: String, from address: String, _ report: inout CheckReport) -> ParsedFeed? {
    parse(Data(xml.utf8), from: address, &report)
}

private func parse(_ data: Data, from address: String, charsetHint: String? = nil, _ report: inout CheckReport) -> ParsedFeed? {
    guard let url = URL(string: address) else { return nil }
    do { return try FeedParser.parse(data, feedURL: url, charsetHint: charsetHint, now: referenceNow) } catch {
        report.expect(false, "parses \(address)", detail: "\(error)")
        return nil
    }
}

func checkDates(_ report: inout CheckReport) {
    report.section("Dates: six formats")
    let expected = utc(2026, 9, 21, 7, 30, 0)
    let cases: [(String, String)] = [
        ("RFC 822, four-digit year, numeric zone", "Mon, 21 Sep 2026 09:30:00 +0200"),
        ("RFC 822, two-digit year, named zone", "Mon, 21 Sep 26 03:30:00 EDT"),
        ("RFC 822 without weekday", "21 Sep 2026 07:30:00 GMT"),
        ("RFC 822 without seconds", "Mon, 21 Sep 2026 07:30 Z"),
        ("ISO 8601 with fractional seconds", "2026-09-21T09:30:00.000+02:00"),
        ("ISO 8601 without fractions", "2026-09-21T07:30:00Z"),
    ]
    for (name, text) in cases { report.expectEqual(FeedDate.parse(text), expected, name) }
    report.expectEqual(FeedDate.parse("2026-09-21T07:30:00.250Z")?.timeIntervalSince1970, expected.map { $0.timeIntervalSince1970 + 0.25 },
                       "fractions of a second are kept")
    report.expectEqual(FeedDate.parse("2026-09-21 07:30:00"), expected, "a missing zone means UTC")
    report.expectEqual(FeedDate.parse("Monday, 21 September 2026 00:30:00 -0700 (PDT)"), expected, "long names and a trailing comment")
    report.expectEqual(FeedDate.parse("2024-02-29"), utc(2024, 2, 29), "date only, leap day")
    for bad in ["", "yesterday", "2026-02-30T00:00:00Z", "Mon, 32 Sep 2026 09:30:00 GMT", "2026-09-21T07:30:00+25:00", "Mon, 21 Sep 2026 09:30:00 MARS"] {
        report.expect(FeedDate.parse(bad) == nil, "rejects \"\(bad)\"")
    }
}

func checkText(_ report: inout CheckReport) {
    report.section("Snippets: plain text, 300 characters")
    let html = "<p>Tags&nbsp;are <b>stripped</b>,</p><p>entities &amp; &#8220;quotes&#x201D; decoded.</p><style>p{color:red}</style><!-- > hidden --><br/>AT&T and 1 < 2 survive."
    report.expectEqual(HTMLText.plainText(fromHTML: html), "Tags are stripped, entities & “quotes” decoded. AT&T and 1 < 2 survive.", "tags, entities, comments, style")
    let long = String(repeating: "word ", count: 100)
    let snippet = HTMLText.snippet(fromHTML: "<div>\(long)</div>")
    report.expect(snippet.count <= 300 && snippet.count > 280, "cut to at most 300 characters", detail: "\(snippet.count)")
    report.expect(snippet.hasSuffix("word…"), "cut at a word boundary with an ellipsis", detail: String(snippet.suffix(12)))
    report.expectEqual(HTMLText.snippet(fromHTML: String(repeating: "x", count: 400)).count, 300, "one unbroken token still fits the cap")
    report.expectEqual(HTMLText.snippet(fromHTML: "short &eacute;"), "short é", "short text is left alone")
    report.expectEqual(HTMLText.decodeEntities("&hellip;&notanentity;&#xZZ;&"), "…&notanentity;&#xZZ;&", "unknown references stay as typed")
}

func checkRSS(_ report: inout CheckReport) {
    report.section("RSS 2.0, dirty")
    guard let feed = parse(Fixtures.dirtyRSS, from: "https://blog.example.com/feed", &report) else { return }
    report.expectEqual(feed.format, .rss, "recognised as RSS behind a BOM and a blank line")
    report.expectEqual(feed.title, "Café & Code — R&D notes", "feed title: &eacute; &mdash; and a bare ampersand")
    report.expectEqual(feed.siteURL?.absoluteString, "https://blog.example.com/", "site link is the channel's, not the image's or atom:link's")
    report.expectEqual(feed.items.count, 7, "seven items: the repeated GUID collapses")
    guard feed.items.count == 7 else { return }

    let first = feed.items[0]
    report.expectEqual(first.title, "Ben & Jerry’s guide to AT&T's <dialog> element, really", "title: &rsquo; &nbsp; AT&T, inline markup gone, <dialog> kept")
    report.expectEqual(first.url?.absoluteString, "https://blog.example.com/posts/dialog?a=1&b=2", "root-relative link with a bare & resolves")
    report.expectEqual(first.guid, "post-1", "GUID wins as identity")
    report.expectEqual(first.published, utc(2026, 9, 21, 7, 30), "pubDate")
    report.expectEqual(first.snippet, "First paragraph with a link & an entity. Second paragraph.", "CDATA snippet: script, control character and WordPress footer gone")
    report.expect((first.content ?? "").contains("Long body sentence") && (first.content ?? "").count > 1_200, "content:encoded kept as content")
    report.expect((first.content ?? "").contains("First&nbsp;paragraph"), "CDATA passes through untouched")

    let noGUID = feed.items[1]
    report.expectEqual(noGUID.url?.absoluteString, "https://blog.example.com/posts/no-guid", "path-relative link resolves against the feed")
    report.expectEqual(noGUID.guid, "https://blog.example.com/posts/no-guid", "no GUID: identity falls back to the link")
    report.expectEqual(noGUID.published, utc(2026, 9, 20, 8), "dc:date")
    report.expectEqual(noGUID.snippet, "Plain escaped markup, 1 < 2 and &unknownentity; stay readable.", "escaped markup stripped; unknown entity survives")
    report.expect(noGUID.content == nil, "no content when the feed says nothing beyond the snippet")

    let bare = feed.items[2]
    report.expect(bare.url == nil && bare.guid.hasPrefix("sha256:"), "no GUID, no link: identity is a hash of title and date", detail: bare.guid)
    let again = parse(Fixtures.dirtyRSS, from: "https://blog.example.com/feed", &report)
    report.expectEqual(again?.items[2].guid, bare.guid, "the hash is stable from parse to parse")

    let untitled = feed.items[3]
    report.expectEqual(untitled.url?.absoluteString, "https://blog.example.com/posts/untitled", "a permalink GUID doubles as the link")
    report.expect(untitled.title.hasPrefix("An untitled note") && untitled.title.hasSuffix("…") && untitled.title.count <= 100, "an untitled item borrows its opening words", detail: untitled.title)

    report.expectEqual(feed.items[4].url?.absoluteString, "https://blog.example.com/posts/tracked?id=7", "utm_ campaign parameters are removed from links; the rest of the query stays")
    report.expectEqual(feed.items[4].snippet, "A teaser that stops short.…", "a trailing \"Read More <title>\" is not part of the excerpt")
    report.expectEqual(feed.items[5].snippet, "", "a description that is only a \"Comments\" link says nothing, so the snippet is empty")
    report.expect(feed.items[6].published == nil, "a date twelve years ahead is dropped")
}

func checkAtomAndRDF(_ report: inout CheckReport) {
    report.section("Atom")
    if let feed = parse(Fixtures.atom, from: "https://notes.example.org/atom.xml", &report), feed.items.count == 2 {
        report.expectEqual(feed.format, .atom, "recognised as Atom")
        report.expectEqual(feed.title, "Notes & Queries", "type=\"html\" title decoded twice and stripped")
        report.expectEqual(feed.siteURL?.absoluteString, "https://notes.example.org/", "site link: rel=alternate, relative")
        let entry = feed.items[0]
        report.expectEqual(entry.title, "When a < b: comparing things", "a text title keeps its literal <")
        report.expectEqual(entry.url?.absoluteString, "https://notes.example.org/entries/1.html", "rel=alternate beats the enclosure; relative href resolves")
        report.expectEqual(entry.guid, "tag:notes.example.org,2026:/entries/1", "atom:id is the identity")
        report.expectEqual(entry.published?.timeIntervalSince1970, utc(2026, 9, 20, 16, 45, 12).map { $0.timeIntervalSince1970 + 0.345 }, "published beats updated; fraction and offset read")
        report.expectEqual(entry.snippet, "A summary with markup and an entity.", "HTML summary becomes the snippet")
        report.expect((entry.content ?? "").contains("<em>real</em>") && (entry.content ?? "").contains("&amp; an ampersand"), "XHTML content is written back as HTML", detail: entry.content ?? "nil")
        report.expect(!(entry.content ?? "").contains("xmlns"), "namespace declarations are not copied into the HTML")
        report.expectEqual(feed.items[1].published, utc(2026, 9, 19, 6), "updated stands in when published is missing")
        report.expectEqual(feed.items[1].snippet, "Short.", "content stands in when there is no summary")
    } else {
        report.expect(false, "Atom fixture yields two entries")
    }

    report.section("RDF (RSS 1.0)")
    if let feed = parse(Fixtures.rdf, from: "https://rdf.example.net/index.rdf", &report), feed.items.count == 2 {
        report.expectEqual(feed.format, .rdf, "recognised as RDF")
        report.expectEqual(feed.title, "RDF Site", "channel title")
        report.expectEqual(feed.items[0].guid, "https://rdf.example.net/a", "rdf:about is the identity")
        report.expectEqual(feed.items[0].published, utc(2026, 9, 18, 12), "dc:date with an offset")
        report.expectEqual(feed.items[1].url?.absoluteString, "https://rdf.example.net/b", "rdf:about stands in for a missing link")
        report.expectEqual(feed.items[1].published, utc(2026, 9, 17), "date-only dc:date")
    } else {
        report.expect(false, "RDF fixture yields two items")
    }

    report.section("YouTube (Media RSS)")
    if let feed = parse(Fixtures.youtube, from: "https://www.youtube.com/feeds/videos.xml?channel_id=UCYO_jab_esuFRV4b17AJtAw", &report), let video = feed.items.first {
        report.expectEqual(feed.title, "3Blue1Brown", "channel name")
        report.expectEqual(feed.siteURL?.absoluteString, "https://www.youtube.com/channel/UCYO_jab_esuFRV4b17AJtAw", "channel page")
        report.expectEqual(video.url?.absoluteString, "https://www.youtube.com/watch?v=abc123DEF45", "watch link")
        report.expectEqual(video.snippet, "Visualizing the most important tool for differential equations. Lessons are funded by viewers: https://3b1b.co/support Timestamps: 0:00 - Intro, 2:10 - s-plane",
                           "snippet from media:group/media:description, line breaks collapsed")
        report.expectEqual(video.published, utc(2026, 9, 12, 15, 0, 6), "published")
    } else {
        report.expect(false, "YouTube fixture yields a video")
    }
}

func checkEncodingsAndDamage(_ report: inout CheckReport) {
    report.section("Encodings")
    let latin1 = parse(Fixtures.latin1RSS, from: "https://fr.example.com/rss", &report)
    report.expectEqual(latin1?.title, "Actualités", "declared ISO-8859-1: feed title")
    report.expectEqual(latin1?.items.first?.title, "Été à Besançon : ça coûte cher ?", "declared ISO-8859-1: item title")
    let cp1252 = parse(Fixtures.windows1252RSS, from: "https://cp1252.example.com/rss", charsetHint: "windows-1252", &report)
    report.expectEqual(cp1252?.items.first?.title, "“Smart” quotes — it’s fine", "windows-1252 named only by the HTTP header")
    let guessed = parse(Fixtures.windows1252RSS, from: "https://cp1252.example.com/rss", &report)
    report.expectEqual(guessed?.items.first?.title, "“Smart” quotes — it’s fine", "undeclared, not UTF-8: falls back to windows-1252")
    let utf16 = parse(Fixtures.utf16RSS, from: "https://wide.example.com/rss", &report)
    report.expectEqual(utf16?.items.first?.title, "Sixteen bits — naïve café", "UTF-16 with a byte-order mark")

    report.section("Damage")
    let sloppy = parse(Fixtures.undeclaredPrefix, from: "https://sloppy.example.com/rss", &report)
    report.expectEqual(sloppy?.items.first?.snippet, "Body under a prefix nobody declared.", "an undeclared content: prefix still yields the body")
    let truncated = parse(Fixtures.truncated, from: "https://cut.example.com/rss", &report)
    report.expectEqual(truncated?.items.map(\.title), ["Complete"], "a feed cut off mid-item keeps the items before the cut")
    for (name, body) in [("an HTML page", Fixtures.htmlPage), ("JSON", Fixtures.hackerNews), ("nothing", "")] {
        let url = URL(string: "https://example.com/") ?? URL(fileURLWithPath: "/")
        var thrown: Error?
        do { _ = try FeedParser.parse(Data(body.utf8), feedURL: url) } catch { thrown = error }
        report.expect(thrown as? FeedError == .notAFeed, "\(name) is refused as not a feed", detail: "\(String(describing: thrown))")
    }
    report.expect(FeedParser.looksLikeFeed(Data(Fixtures.dirtyRSS.utf8)) && FeedParser.looksLikeFeed(Fixtures.utf16RSS), "sniffing recognises feeds, BOM or not")
    report.expect(!FeedParser.looksLikeFeed(Data(Fixtures.htmlPage.utf8)), "sniffing is not fooled by a page that mentions <rss")
}

func checkAdapters(_ report: inout CheckReport) {
    report.section("Adapters")
    do {
        let items = try HackerNews.items(fromSearchResponse: Data(Fixtures.hackerNews.utf8))
        report.expectEqual(items.count, 2, "Hacker News: a hit without a title is skipped")
        report.expectEqual(items.first?.snippet, "example.dev", "Hacker News: the snippet is the linked domain, without www.")
        report.expectEqual(items.first?.guid, "45000001", "Hacker News: identity is the story id")
        report.expectEqual(items.first?.published, Date(timeIntervalSince1970: 1_790_000_000), "Hacker News: created_at_i")
        report.expectEqual(items.last?.url?.absoluteString, "https://news.ycombinator.com/item?id=45000002", "Ask HN: the discussion is the link")
        report.expectEqual(items.last?.snippet, "I'm curious what people use. RSS still works for me.", "Ask HN: the snippet is the post's own text")
        report.expectEqual(items.last?.title, "Ask HN: How do you read the web in 2026?", "titles have whitespace collapsed")
    } catch {
        report.expect(false, "Hacker News fixture decodes", detail: "\(error)")
    }
    var refused: Error?
    do { _ = try HackerNews.items(fromSearchResponse: Data("<html>".utf8)) } catch { refused = error }
    report.expect(refused as? FeedError == .notAFeed, "Hacker News: a non-JSON body is an error, not an empty list")

    report.expectEqual(GitHubReleases.repoName(feedURL: URL(string: "https://github.com/ml-explore/mlx/releases.atom") ?? HackerNews.feedURL), "mlx", "GitHub: repoName from the feed address")
    report.expect(GitHubReleases.repoName(feedURL: HackerNews.feedURL) == nil, "GitHub: no repoName for other feeds")
    if let release = parse(Fixtures.githubReleases, from: "https://github.com/ml-explore/mlx/releases.atom", &report)?.items.first {
        let item = Item(sourceID: 1, guid: release.guid, url: release.url, title: release.title, snippet: release.snippet, repoName: "mlx")
        report.expectEqual(item.judgedText["title"], "mlx v0.30.6", "GitHub: with repoName an item is judged as \"<repo> <tag>\"")
        report.expectEqual(release.snippet, "Highlights Faster quantized matmul on M-series GPUs Fix a crash in mx.compile", "GitHub: release notes become the snippet")
    }

    report.expectEqual(Arxiv.category(named: "cs.lg"), "cs.LG", "arXiv: category spelling is normalised")
    report.expectEqual(Arxiv.category(named: "cond-mat.mes-hall"), "cond-mat.mes-hall", "arXiv: long subject classes")
    report.expect(Arxiv.category(named: "example.com") == nil && Arxiv.category(named: "cs.") == nil, "arXiv: a domain name is not a category")
    report.expectEqual(Arxiv.feedURL(category: "cs.LG")?.absoluteString,
                       "https://export.arxiv.org/api/query?search_query=cat:cs.LG&sortBy=submittedDate&sortOrder=descending", "arXiv: export API address")
    report.expectEqual(SourceKind(feedURL: HackerNews.feedURL), .hackerNews, "a feed address tells its kind: Hacker News")
    report.expectEqual(URL(string: "https://www.youtube.com/feeds/videos.xml?channel_id=UCx").map(SourceKind.init(feedURL:)), .youtube, "a feed address tells its kind: YouTube")
    report.expectEqual(URL(string: "https://daringfireball.net/feeds/main").map(SourceKind.init(feedURL:)), .feed, "a feed address tells its kind: plain feed")
}
