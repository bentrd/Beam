import BeamModels
import Foundation

/// The feeds and pages the offline checks run against.
///
/// They are built rather than saved, because what they have to be is precise: a known number of items, a known
/// number of them relevant, dates that order them, and exactly the dirt PRODUCT.md MUST 2 names.
enum Fixtures {
    /// The sentence the offline checks search for. Its words are what the stub judge scores against.
    static let sentence = "on-device machine learning"

    /// How relevant one generated item is meant to be.
    enum Relevance {
        /// Every word of the sentence: the stub answers 0.9, which is found.
        case found
        /// One word of three: 0.5, which is unsure.
        case unsure
        /// None: 0.05, which is counted and not listed.
        case nothing

        var title: String {
            switch self {
            case .found: return "Running device machine learning models on a laptop"
            case .unsure: return "A learning curve for new engineers"
            case .nothing: return "Gardening tips for a small autumn balcony"
            }
        }
    }

    /// A well-formed RSS feed of `count` items, the first `found` of them relevant and the next `unsure` partly so.
    static func rss(title: String, site: String, count: Int, found: Int = 0, unsure: Int = 0,
                    from day: Int = 1, guidPrefix: String = "item") -> String {
        let items = (0..<count).map { index -> String in
            let relevance: Relevance = index < found ? .found : (index < found + unsure ? .unsure : .nothing)
            return item(guid: "\(guidPrefix)-\(index)", title: "\(relevance.title) \(index)",
                        snippet: "A paragraph about \(index) things.", link: "\(site)/\(guidPrefix)-\(index)",
                        date: rfc822(day: day, minute: count - index))
        }
        return feed(title: title, site: site, items: items)
    }

    /// One feed carrying everything a parser is supposed to survive (PRODUCT.md MUST 2): a byte-order mark,
    /// entities that are not XML's, CDATA, six date formats, a repeated GUID and a repeated link.
    static var dirty: String {
        // Six formats, and deliberately six different instants: a format that was not parsed at all, or that
        // silently borrowed another's value, can only be caught by the dates coming out distinct. "08:00 +0200"
        // is already 06:00 UTC, so the plain ISO literal is half an hour off it rather than the same moment.
        let dates = [
            "Tue, 15 Sep 2026 08:00:00 GMT",                // RFC 822
            "Tue, 15 Sep 2026 08:00:00 +0200",              // RFC 822 with an offset
            "15 Sep 2026 07:00:00 GMT",                     // RFC 822 without a weekday
            "2026-09-15T06:30:00Z",                         // ISO 8601
            "2026-09-15T05:00:00.123+02:00",                // ISO 8601 with fractions
            "2026-09-15 04:00:00",                          // the one feeds invent
        ]
        var items = dates.enumerated().map { position, date in
            item(guid: "dirty-\(position)", title: "Caf&eacute;&nbsp;news \(position)",
                 snippet: "<![CDATA[Some <b>bold</b> text &amp; an entity]]>",
                 link: "https://dirty.example/\(position)", date: date, escapeSnippet: false)
        }
        // The same entry twice by GUID, then a different GUID with a link that is already listed.
        items.append(item(guid: "dirty-0", title: "Caf&eacute; news 0 again", snippet: "A repeat",
                          link: "https://dirty.example/0", date: dates[0]))
        items.append(item(guid: "dirty-fresh", title: "A new guid, an old link", snippet: "A repeat by link",
                          link: "https://dirty.example/1", date: dates[1]))
        return "\u{FEFF}" + feed(title: "Dirty feed", site: "https://dirty.example", items: items)
    }

    /// A site that advertises its feed, which is how a blog homepage resolves.
    static func homepage(feed: String) -> String {
        """
        <!doctype html><html><head><title>A Blog</title>
        <link rel="alternate" type="application/rss+xml" title="A Blog" href="\(feed)">
        </head><body><h1>A Blog</h1><p>Posts.</p></body></html>
        """
    }

    /// YouTube's own shape: Atom with the `media:` namespace carrying the description.
    static func youtube(channelID: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom" xmlns:media="http://search.yahoo.com/mrss/" xmlns:yt="http://www.youtube.com/xml/schemas/2015">
          <title>A Channel</title>
          <link rel="alternate" href="https://www.youtube.com/channel/\(channelID)"/>
          <entry>
            <id>yt:video:abc123</id>
            <title>Device machine learning on a laptop</title>
            <link rel="alternate" href="https://www.youtube.com/watch?v=abc123"/>
            <published>2026-09-15T10:00:00+00:00</published>
            <media:group><media:description>What the video is about.</media:description></media:group>
          </entry>
        </feed>
        """
    }

    /// A GitHub releases feed: the titles are bare tags, which is why release items are judged with their repo name.
    static func releases(repository: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Release notes from \(repository)</title>
          <link rel="alternate" href="https://github.com/ml-explore/\(repository)/releases"/>
          <entry>
            <id>tag:github.com,2008:Repository/1/v0.30.6</id>
            <title>v0.30.6</title>
            <link rel="alternate" href="https://github.com/ml-explore/\(repository)/releases/tag/v0.30.6"/>
            <updated>2026-09-15T12:00:00Z</updated>
            <content type="html">Faster device machine learning kernels.</content>
          </entry>
        </feed>
        """
    }

    /// A page with a known shape: one heading and paragraphs whose relevance is known one by one, so a check can
    /// say exactly which of them should light up.
    static func article(title: String, paragraphs: [Relevance]) -> String {
        let body = paragraphs.enumerated().map { index, relevance -> String in
            "<p>\(sentence(relevance, number: index))</p>"
        }.joined(separator: "\n")
        return """
        <!doctype html><html><head><title>\(title)</title></head>
        <body><article><h1>\(title)</h1><h2>The section</h2>
        \(body)
        </article></body></html>
        """
    }

    /// Long enough to be a passage of its own (40 characters), and never the same twice.
    static func sentence(_ relevance: Relevance, number: Int) -> String {
        switch relevance {
        case .found:
            return "Running device machine learning models on a small laptop is practical now, as example \(number) shows."
        case .unsure:
            return "A learning curve is steep for anyone new to this trade, and example \(number) is no exception at all."
        case .nothing:
            return "Autumn balconies need watering less often than summer ones, which example \(number) makes plain enough."
        }
    }

    /// A page that says it is behind a paywall and shows a teaser: the reader must fall back, not pretend.
    static let paywalled = """
    <!doctype html><html><head><title>Members only</title>
    <meta name="article:content_tier" content="locked"></head>
    <body><article><p>The first paragraph is free to read, and it is the only one.</p>
    <p>Subscribe to continue reading this story.</p></article></body></html>
    """

    /// A page with nothing to read: the failed state, not an empty article.
    static let thin = "<!doctype html><html><head><title>Nothing</title></head><body><div id=\"app\"></div></body></html>"

    // MARK: Building blocks

    static func feed(title: String, site: String, items: [String]) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0"><channel>
        <title>\(title)</title><link>\(site)</link><description>A feed</description>
        \(items.joined(separator: "\n"))
        </channel></rss>
        """
    }

    static func item(guid: String, title: String, snippet: String, link: String, date: String,
                     escapeSnippet: Bool = true) -> String {
        let description = escapeSnippet ? snippet : snippet
        return """
        <item><guid isPermaLink="false">\(guid)</guid><title>\(title)</title>
        <link>\(link)</link><pubDate>\(date)</pubDate><description>\(description)</description></item>
        """
    }

    /// Distinct, ordered dates, newest first as `minute` grows.
    static func rfc822(day: Int, minute: Int) -> String {
        let base = DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(identifier: "GMT"),
                                  year: 2026, month: 9, day: min(max(day, 1), 28), hour: 0, minute: 0).date ?? Date()
        let date = base.addingTimeInterval(Double(minute) * 60)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter.string(from: date)
    }

    /// The GitHub Terms of Service, as the extract lane saved it: 137 paragraphs, one of which answers
    /// "which jurisdiction's law governs disputes".
    static var githubTerms: Data? {
        guard let folder = Bundle.module.url(forResource: "Fixtures", withExtension: nil) else { return nil }
        return try? Data(contentsOf: folder.appendingPathComponent("github-terms.html"))
    }
}
