import BeamModels
import Foundation

/// What a server said about the version of a feed it sent, to be echoed back next time (conditional GET).
struct Validators: Sendable, Hashable {
    var etag: String?
    var lastModified: String?
    var isEmpty: Bool { etag == nil && lastModified == nil }
}

/// A feed of any kind, fetched and read.
struct LoadedFeed: Sendable {
    var title: String
    var siteURL: URL?
    var items: [FeedItem]
    var validators: Validators
}

/// Fetches one source the way its kind requires. Shared by `Refresher` (which refreshes stored sources) and
/// `SourceResolver` (which must prove a candidate works before offering it), so both treat a host identically.
struct SourceLoader: Sendable {
    let fetch: HTTPFetch
    let arxivGate: HostGate
    let redditGate: HostGate
    /// How long to wait for a paced host's permission; see `HostGate.send`.
    let patience: TimeInterval

    /// - Returns: nil when the server answered 304 Not Modified to the validators sent.
    func load(kind: SourceKind, feedURL: URL, validators: Validators? = nil) async throws -> LoadedFeed? {
        var request = HTTPRequest(url: feedURL, headers: ["Accept": kind == .hackerNews ? Accept.json : Accept.feed])
        switch kind {
        case .hackerNews: request.url = HackerNews.requestURL(for: feedURL)
        case .arxiv: request.url = Arxiv.requestURL(for: feedURL)
        case .feed, .reddit, .githubReleases, .youtube: break
        }
        if let etag = validators?.etag { request.headers["If-None-Match"] = etag }
        if let lastModified = validators?.lastModified { request.headers["If-Modified-Since"] = lastModified }

        let response = try await send(request, kind: kind)
        if response.status == 304 { return nil }
        if let delay = HostGate.requestedDelay(in: response, now: Date()) { throw FeedError.rateLimited(retryAfter: delay) }
        guard response.isSuccess else { throw FeedError.http(status: response.status) }

        let fresh = Validators(etag: response.header("ETag"), lastModified: response.header("Last-Modified"))
        if kind == .hackerNews {
            let items = try HackerNews.items(fromSearchResponse: response.body)
            return LoadedFeed(title: HackerNews.candidate.title, siteURL: HackerNews.siteURL, items: items, validators: fresh)
        }
        let feed = try FeedParser.parse(response.body, feedURL: response.url, charsetHint: response.charset)
        var items = feed.items
        if kind == .arxiv { items = Arxiv.refine(items) }
        if kind == .reddit { items = Reddit.refine(items) }
        return LoadedFeed(title: feed.title, siteURL: feed.siteURL, items: items, validators: fresh)
    }

    private func send(_ request: HTTPRequest, kind: SourceKind) async throws -> HTTPResponse {
        do {
            switch kind {
            case .arxiv: return try await arxivGate.send(request, using: fetch, patience: patience)
            case .reddit: return try await redditGate.send(request, using: fetch, patience: patience)
            case .feed, .hackerNews, .githubReleases, .youtube: return try await fetch(request)
            }
        } catch {
            throw try FeedError.wrapping(error)
        }
    }
}
