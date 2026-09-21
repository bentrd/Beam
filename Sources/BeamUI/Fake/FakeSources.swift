import BeamModels
import Foundation

/// The sources of the captured session, and the one-click catalog the Add Source popover filters.
enum FakeSources {
    private struct Seed { let kind: SourceKind; let title, feed, site, blurb: String; var isStarter = false }

    private static let subscribed: [Seed] = [
        Seed(kind: .hackerNews, title: "Hacker News", feed: "https://hn.algolia.com/api/v1/search?tags=front_page",
             site: "https://news.ycombinator.com", blurb: "The front page", isStarter: true),
        Seed(kind: .feed, title: "Lobsters", feed: "https://lobste.rs/rss", site: "https://lobste.rs", blurb: "Computing, link by link"),
        Seed(kind: .feed, title: "Simon Willison", feed: "https://simonwillison.net/atom/everything/",
             site: "https://simonwillison.net", blurb: "Notes on language models and the web"),
        Seed(kind: .reddit, title: "r/macapps", feed: "https://www.reddit.com/r/macapps/.rss",
             site: "https://www.reddit.com/r/macapps/", blurb: "Mac apps, by the people who make and use them"),
        Seed(kind: .githubReleases, title: "MLX releases", feed: "https://github.com/ml-explore/mlx/releases.atom",
             site: "https://github.com/ml-explore/mlx/releases", blurb: "Apple's array framework for Apple silicon", isStarter: true),
        Seed(kind: .arxiv, title: "arXiv cs.LG",
             feed: "https://export.arxiv.org/api/query?search_query=cat:cs.LG&sortBy=submittedDate&max_results=100",
             site: "https://arxiv.org/list/cs.LG/recent", blurb: "New machine learning papers"),
        Seed(kind: .feed, title: "Apple Machine Learning Research", feed: "https://machinelearning.apple.com/rss.xml",
             site: "https://machinelearning.apple.com", blurb: "Papers and posts from Apple's researchers", isStarter: true),
    ]

    private static let offered: [Seed] = [
        Seed(kind: .feed, title: "Daring Fireball", feed: "https://daringfireball.net/feeds/main",
             site: "https://daringfireball.net", blurb: "John Gruber on Apple"),
        Seed(kind: .feed, title: "Swift.org", feed: "https://www.swift.org/atom.xml", site: "https://www.swift.org/blog/",
             blurb: "The Swift project's blog"),
        Seed(kind: .feed, title: "Julia Evans", feed: "https://jvns.ca/atom.xml", site: "https://jvns.ca", blurb: "How computers really work"),
        Seed(kind: .reddit, title: "r/swift", feed: "https://www.reddit.com/r/swift/.rss", site: "https://www.reddit.com/r/swift/",
             blurb: "Swift questions and projects"),
        Seed(kind: .arxiv, title: "arXiv cs.CL",
             feed: "https://export.arxiv.org/api/query?search_query=cat:cs.CL&sortBy=submittedDate&max_results=100",
             site: "https://arxiv.org/list/cs.CL/recent", blurb: "New computation and language papers"),
        Seed(kind: .githubReleases, title: "Swift releases", feed: "https://github.com/swiftlang/swift/releases.atom",
             site: "https://github.com/swiftlang/swift/releases", blurb: "Toolchain releases"),
    ]

    /// The session's sources. r/macapps has been refused for two days (Reddit answers a second request with 429,
    /// see EVIDENCE.md), which is the one case that earns the sidebar's warning glyph.
    static func starting(now: Date) -> [Source] {
        subscribed.enumerated().compactMap { index, seed -> Source? in
            guard let found = candidate(seed) else { return nil }
            var source = Source(id: Int64(index + 1), kind: found.kind, title: found.title, feedURL: found.feedURL,
                                siteURL: found.siteURL, position: index, lastFetch: now.addingTimeInterval(-600))
            if source.kind == .reddit {
                source.lastError = "HTTP 429"
                source.failingSince = now.addingTimeInterval(-2 * 86_400)
                source.lastFetch = source.failingSince
            }
            return source
        }
    }

    static let catalog: [CatalogEntry] = (subscribed + offered).compactMap { seed in
        candidate(seed).map { CatalogEntry(candidate: $0, blurb: seed.blurb, isStarter: seed.isStarter) }
    }

    private static func candidate(_ seed: Seed) -> SourceCandidate? {
        guard let feed = URL(string: seed.feed) else { return nil }
        return SourceCandidate(kind: seed.kind, title: seed.title, feedURL: feed, siteURL: URL(string: seed.site))
    }

    /// Hacker News rows carry the linked domain as their snippet; every other row opens its source's site.
    static func link(for record: ListFile.Row, in source: Source?) -> URL? {
        if source?.kind == .hackerNews, record.snippet.contains("."), let url = URL(string: "https://\(record.snippet)") { return url }
        return source?.siteURL
    }

    /// "38m", "7h", "2d" as captured.
    static func seconds(fromAge age: String) -> TimeInterval {
        guard let unit = age.last, let count = Double(age.dropLast()) else { return 0 }
        switch unit {
        case "m": return count * 60
        case "h": return count * 3_600
        case "d": return count * 86_400
        default: return 0
        }
    }
}
