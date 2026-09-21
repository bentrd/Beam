import BeamModels
import Foundation

/// The one-click sources in the Add Source popover, and the three a fresh install starts with.
///
/// Short on purpose: a catalog is a suggestion of what Beam is good for, not a directory. Every address here was
/// fetched and parsed with this lane's own code before it was listed (`check-feeds --catalog` does it again), and
/// Reddit entries are listed only because they passed (PRODUCT.md MUST 2).
public enum Catalog {
    public static let entries: [CatalogEntry] = starters + machineLearning + apple + programming + games + music + design + french

    /// Hacker News front page, MLX releases, Apple Machine Learning Research (PRODUCT.md addendum). All removable.
    public static let starters: [CatalogEntry] = [
        CatalogEntry(candidate: HackerNews.candidate, blurb: "The front page", isStarter: true),
        release("ml-explore", "mlx", title: "MLX releases", blurb: "Apple's array framework for machine learning on Apple silicon", isStarter: true),
        feed("Apple Machine Learning Research", "https://machinelearning.apple.com/rss.xml", site: "https://machinelearning.apple.com/",
             blurb: "Papers and posts from Apple's machine learning teams", isStarter: true),
    ]

    /// What the popover shows while its field holds `query`: every word must appear in the title, the blurb or the
    /// address, in any order and without regard to case or accents. An empty query shows everything.
    public static func entries(matching query: String) -> [CatalogEntry] {
        let words = folded(query).split(separator: " ")
        guard !words.isEmpty else { return entries }
        return entries.filter { entry in
            let haystack = folded([entry.candidate.title, entry.blurb, entry.candidate.feedURL.absoluteString,
                                   entry.candidate.siteURL?.absoluteString ?? ""].joined(separator: " "))
            return words.allSatisfy { haystack.contains($0) }
        }
    }

    private static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    // MARK: Entries by subject

    private static let machineLearning: [CatalogEntry] = [
        arxiv("cs.LG", blurb: "New machine learning papers"),
        arxiv("cs.CL", blurb: "New papers on language models and computation"),
        feed("Simon Willison's Weblog", "https://simonwillison.net/atom/everything/", site: "https://simonwillison.net/",
             blurb: "Language models, tools and the open web, daily"),
        feed("Hugging Face Blog", "https://huggingface.co/blog/feed.xml", site: "https://huggingface.co/blog",
             blurb: "Open models, datasets and machine learning libraries"),
    ]

    private static let apple: [CatalogEntry] = [
        feed("Daring Fireball", "https://daringfireball.net/feeds/main", site: "https://daringfireball.net/",
             blurb: "John Gruber on Apple and the Mac"),
        feed("Apple Developer News", "https://developer.apple.com/news/rss/news.rss", site: "https://developer.apple.com/news/",
             blurb: "Announcements for Apple platform developers"),
        feed("Michael Tsai", "https://mjtsai.com/blog/feed/", site: "https://mjtsai.com/blog/",
             blurb: "Mac and iOS development, quoted and linked"),
        feed("Six Colors", "https://sixcolors.com/feed/", site: "https://sixcolors.com/",
             blurb: "Apple news and reviews by Jason Snell and Dan Moren"),
    ]

    private static let programming: [CatalogEntry] = [
        feed("Lobsters", "https://lobste.rs/rss", site: "https://lobste.rs/", blurb: "Programming links from an invitation-only community"),
        feed("Swift.org", "https://www.swift.org/atom.xml", site: "https://www.swift.org/blog/", blurb: "The Swift language blog"),
        feed("Julia Evans", "https://jvns.ca/atom.xml", site: "https://jvns.ca/", blurb: "Programming tools and systems, explained plainly"),
        youtube("3Blue1Brown", "UCYO_jab_esuFRV4b17AJtAw", blurb: "Mathematics, animated"),
    ]

    private static let games: [CatalogEntry] = [
        feed("Rock Paper Shotgun", "https://www.rockpapershotgun.com/feed", site: "https://www.rockpapershotgun.com/",
             blurb: "PC games news and reviews"),
        feed("ModDB", "https://rss.moddb.com/articles/feed/rss.xml", site: "https://www.moddb.com/", blurb: "Game mods: news and releases"),
        feed("Game Developer", "https://www.gamedeveloper.com/rss.xml", site: "https://www.gamedeveloper.com/",
             blurb: "The craft and business of making games"),
        subreddit("skyrimmods", blurb: "Skyrim modding community on Reddit"),
    ]

    private static let music: [CatalogEntry] = [
        feed("CDM", "https://cdm.link/feed/", site: "https://cdm.link/", blurb: "Music technology, instruments and live visuals"),
        feed("Synthtopia", "https://www.synthtopia.com/feed/", site: "https://www.synthtopia.com/", blurb: "Synthesizers and electronic music gear"),
        feed("Bedroom Producers Blog", "https://bedroomproducersblog.com/feed/", site: "https://bedroomproducersblog.com/",
             blurb: "Free and affordable music production software"),
    ]

    private static let design: [CatalogEntry] = [
        feed("Smashing Magazine", "https://www.smashingmagazine.com/feed/", site: "https://www.smashingmagazine.com/",
             blurb: "Web design and front-end practice"),
        feed("Pixel Envy", "https://pxlnv.com/feed/", site: "https://pxlnv.com/", blurb: "Nick Heer on technology and design"),
        feed("Design Observer", "https://designobserver.com/feed/", site: "https://designobserver.com/", blurb: "Essays on design and visual culture"),
    ]

    private static let french: [CatalogEntry] = [
        feed("Next", "https://next.ink/feed/", site: "https://next.ink/", blurb: "French tech news, independent and ad-free"),
        feed("Korben", "https://korben.info/feed", site: "https://korben.info/", blurb: "French tech finds, tools and tinkering"),
        feed("MacGeneration", "https://www.macg.co/news/feed", site: "https://www.macg.co/", blurb: "Apple news in French"),
        feed("LinuxFr.org", "https://linuxfr.org/news.atom", site: "https://linuxfr.org/", blurb: "Free software news in French"),
    ]

    // MARK: Builders

    private static func feed(_ title: String, _ address: StaticString, site: StaticString, blurb: String, isStarter: Bool = false) -> CatalogEntry {
        let candidate = SourceCandidate(kind: .feed, title: title, feedURL: URL(literal: address), siteURL: URL(literal: site))
        return CatalogEntry(candidate: candidate, blurb: blurb, isStarter: isStarter)
    }

    private static func release(_ owner: String, _ repository: String, title: String, blurb: String, isStarter: Bool = false) -> CatalogEntry {
        guard var candidate = GitHubReleases.candidate(owner: owner, repository: repository) else {
            preconditionFailure("Invalid catalog repository: \(owner)/\(repository)")
        }
        candidate.title = title
        return CatalogEntry(candidate: candidate, blurb: blurb, isStarter: isStarter)
    }

    private static func arxiv(_ category: String, blurb: String) -> CatalogEntry {
        guard let candidate = Arxiv.candidate(category: category) else { preconditionFailure("Invalid catalog category: \(category)") }
        return CatalogEntry(candidate: candidate, blurb: blurb)
    }

    private static func youtube(_ title: String, _ channelID: String, blurb: String) -> CatalogEntry {
        guard var candidate = YouTube.candidate(channelID: channelID) else { preconditionFailure("Invalid catalog channel: \(channelID)") }
        candidate.title = title
        return CatalogEntry(candidate: candidate, blurb: blurb)
    }

    private static func subreddit(_ name: String, blurb: String) -> CatalogEntry {
        guard let candidate = Reddit.candidate(subreddit: name) else { preconditionFailure("Invalid catalog subreddit: \(name)") }
        return CatalogEntry(candidate: candidate, blurb: blurb)
    }
}
