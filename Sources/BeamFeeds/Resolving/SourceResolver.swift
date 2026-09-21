import BeamModels
import Foundation

/// Turns whatever was typed into the Add Source field into sources that are known to work.
///
/// Order, as PRODUCT.md MUST 2 lists it: host rules (GitHub, YouTube, Reddit, arXiv, Hacker News); then "is the
/// address already a feed?"; then the feeds the page advertises; then the usual paths. Every candidate that needs
/// the network is fetched and parsed before it is returned, so a typo becomes "No feed found at this address"
/// instead of a source that fails for ever. Whether a candidate is already in the sidebar is the caller's
/// business: this type never sees the store.
public struct SourceResolver: Sendable {
    private let fetch: HTTPFetch
    private let loader: SourceLoader

    /// Tried, in this order, when a site advertises nothing.
    static let commonPaths = ["/feed", "/rss", "/atom.xml", "/index.xml", "/feed.xml"]
    /// Someone is watching "Looking for a feed": one arXiv interval is bearable, Reddit's minute is not.
    private static let patience: TimeInterval = 4
    /// A page can advertise dozens of feeds (one per tag). The first few are the site's own.
    private static let mostAdvertisedFeedsChecked = 4

    public init(fetch: @escaping HTTPFetch = HTTPClient.live, arxivGate: HostGate = .arxiv, redditGate: HostGate = .reddit) {
        self.fetch = fetch
        loader = SourceLoader(fetch: fetch, arxivGate: arxivGate, redditGate: redditGate, patience: Self.patience)
    }

    /// - Returns: candidates, best first; empty when nothing at the address is a feed (or the network is down:
    ///   the popover has one sentence for both, "No feed found at this address").
    public func resolve(_ input: String) async -> [SourceCandidate] {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let category = Arxiv.category(named: text) { return [Arxiv.candidate(category: category)].compactMap { $0 } }
        if text.lowercased().hasPrefix("r/") || text.lowercased().hasPrefix("/r/"), let subreddit = Reddit.subreddit(in: text) {
            return await verifiedSubreddit(subreddit)
        }
        guard let url = Self.webAddress(from: text) else { return [] }
        if let byHost = await resolveByHost(url) { return byHost }
        return await discover(at: url)
    }

    // MARK: Input

    /// "example.com/blog", "feed://example.com/rss" and "feed:https://example.com/rss" are all web addresses.
    static func webAddress(from text: String) -> URL? {
        var address = text
        if address.lowercased().hasPrefix("feed:") {
            address = String(address.dropFirst("feed:".count))
            if address.hasPrefix("//") { address = "https:" + address }
        }
        if !address.contains("://") { address = "https://" + address }
        guard !address.contains(where: \.isWhitespace), var components = URLComponents(string: address),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host, host.contains(".") || host == "localhost" else { return nil }
        // "example.com" and "example.com/" are one page; settle on the form servers redirect to.
        if components.path.isEmpty { components.path = "/" }
        return components.url
    }

    // MARK: Host rules

    /// - Returns: nil when no rule claims the host. A rule that claims it has the last word, even when that is "nothing".
    private func resolveByHost(_ url: URL) async -> [SourceCandidate]? {
        if HackerNews.matches(url) { return [HackerNews.candidate] }
        if let category = Arxiv.category(inListingURL: url) { return [Arxiv.candidate(category: category)].compactMap { $0 } }
        // Any other GitHub feed pasted whole (commits, tags) is taken as given, not swapped for releases.
        let isAnotherGitHubFeed = url.pathExtension == "atom" && url.lastPathComponent != "releases.atom"
        if let repository = GitHubReleases.repository(in: url), !isAnotherGitHubFeed {
            guard let candidate = GitHubReleases.candidate(owner: repository.owner, repository: repository.name) else { return [] }
            return await [verified(candidate, adoptingFeedMetadata: false)].compactMap { $0 }
        }
        if let channelID = YouTube.channelID(in: url) {
            guard let candidate = YouTube.candidate(channelID: channelID) else { return [] }
            return await [verified(candidate, adoptingFeedMetadata: true)].compactMap { $0 }
        }
        if let subreddit = Reddit.subreddit(in: url.absoluteString) { return await verifiedSubreddit(subreddit) }
        return nil
    }

    /// Best-effort, like everything about Reddit: when it answers "slow down", the feed address is still right,
    /// so the subreddit is offered unverified rather than refused.
    private func verifiedSubreddit(_ subreddit: String) async -> [SourceCandidate] {
        guard let candidate = Reddit.candidate(subreddit: subreddit) else { return [] }
        do {
            _ = try await loader.load(kind: .reddit, feedURL: candidate.feedURL)
            return [candidate]
        } catch FeedError.rateLimited {
            return [candidate]
        } catch {
            return []
        }
    }

    /// Fetches and parses the candidate's feed. Nil when it does not work.
    /// - Parameter adoptingFeedMetadata: a feed's own title and site link beat anything guessed from outside it;
    ///   host rules that already know better (a repository's name) opt out.
    private func verified(_ candidate: SourceCandidate, adoptingFeedMetadata: Bool) async -> SourceCandidate? {
        guard let feed = try? await loader.load(kind: candidate.kind, feedURL: candidate.feedURL) else { return nil }
        guard adoptingFeedMetadata else { return candidate }
        var verified = candidate
        if !feed.title.isEmpty { verified.title = feed.title }
        verified.siteURL = feed.siteURL ?? candidate.siteURL
        return verified
    }

    // MARK: Discovery

    private func discover(at url: URL) async -> [SourceCandidate] {
        // A pasted feed address on a host with its own rules (an arXiv query, a YouTube feed) must be read the way
        // that host requires: paced, and through its adapter.
        let kind = SourceKind(feedURL: url)
        if kind != .feed {
            let pasted = SourceCandidate(kind: kind, title: url.bareHost ?? url.absoluteString, feedURL: url)
            return await [verified(pasted, adoptingFeedMetadata: true)].compactMap { $0 }
        }
        let page = try? await fetch(HTTPRequest(url: url, headers: ["Accept": Accept.page]))
        var pageTitle: String?
        if let page, page.isSuccess {
            if FeedParser.looksLikeFeed(page.body),
               let feed = try? FeedParser.parse(page.body, feedURL: page.url, charsetHint: page.charset) {
                return [candidate(feedURL: url, feedTitle: feed.title, fallbackTitle: nil, siteURL: feed.siteURL)]
            }
            let html = FeedText.decode(page.body, charsetHint: page.charset)
            pageTitle = FeedLinkFinder.pageTitle(inHTML: html)
            let advertised = await verifiedFeeds(FeedLinkFinder.feeds(inHTML: html, pageURL: page.url), pageTitle: pageTitle, pageURL: url)
            if !advertised.isEmpty { return advertised }
        }
        return await firstCommonPath(near: url, pageTitle: pageTitle)
    }

    private func verifiedFeeds(_ advertised: [FeedLinkFinder.Advertised], pageTitle: String?, pageURL: URL) async -> [SourceCandidate] {
        // A comments feed is never what someone adding a site wants, unless it is all the site offers.
        let articles = advertised.filter { !($0.title + $0.url.path).lowercased().contains("comment") }
        let wanted = Array((articles.isEmpty ? advertised : articles).prefix(Self.mostAdvertisedFeedsChecked))
        let candidates = wanted.map {
            candidate(feedURL: $0.url, feedTitle: "", fallbackTitle: $0.title.isEmpty ? pageTitle : $0.title, siteURL: pageURL)
        }
        // Sites offer the same feed as RSS and as Atom. Two rows with one name would be a question nobody can answer.
        var names = Set<String>()
        return await verifiedInOrder(candidates).filter { names.insert($0.title.lowercased()).inserted }
    }

    /// The paths relative to what was typed come first ("example.com/blog" most likely means "/blog/feed").
    private func firstCommonPath(near url: URL, pageTitle: String?) async -> [SourceCandidate] {
        var addresses: [URL] = []
        let directory = url.path.hasSuffix("/") ? url : url.appendingPathComponent("")
        if url.pathSegments.isEmpty == false {
            addresses += Self.commonPaths.compactMap { URL(string: String($0.dropFirst()), relativeTo: directory)?.absoluteURL }
        }
        addresses += Self.commonPaths.compactMap { URL(string: $0, relativeTo: url)?.absoluteURL }
        let candidates = addresses.map { candidate(feedURL: $0, feedTitle: "", fallbackTitle: pageTitle, siteURL: url) }
        return Array(await verifiedInOrder(candidates).prefix(1))
    }

    /// Checks all at once, answers in the order given.
    private func verifiedInOrder(_ candidates: [SourceCandidate]) async -> [SourceCandidate] {
        await withTaskGroup(of: (Int, SourceCandidate?).self) { group in
            for (index, candidate) in candidates.enumerated() {
                group.addTask { (index, await self.verified(candidate, adoptingFeedMetadata: true)) }
            }
            var verified: [Int: SourceCandidate] = [:]
            for await (index, candidate) in group { verified[index] = candidate }
            return candidates.indices.compactMap { verified[$0] }
        }
    }

    /// A feed names itself best; then the page that advertised it; then its host.
    private func candidate(feedURL: URL, feedTitle: String, fallbackTitle: String?, siteURL: URL?) -> SourceCandidate {
        let title = [feedTitle, fallbackTitle ?? "", feedURL.bareHost ?? feedURL.absoluteString].first { !$0.isEmpty } ?? ""
        return SourceCandidate(kind: SourceKind(feedURL: feedURL), title: title, feedURL: feedURL, siteURL: siteURL)
    }
}
