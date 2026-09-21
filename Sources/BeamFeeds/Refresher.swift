import BeamModels
import Foundation

/// The result of refreshing one source. Beam never lets one bad feed fail a refresh, so failure is a value here.
public struct SourceRefresh: Sendable {
    public enum Outcome: Sendable {
        /// Everything the feed currently lists, in feed order. Telling new from edited from known is the store's job.
        case items([FeedItem])
        /// The server confirmed nothing has changed since this `Refresher` last read the feed.
        case notModified
        case failed(FeedError)
    }

    public let source: Source
    public let outcome: Outcome

    /// Set for GitHub release feeds: copy it to `Item.repoName` so releases are judged as "mlx v0.30.6"
    /// (`FeedItem` has no field for it).
    public var repoName: String? {
        source.kind == .githubReleases ? GitHubReleases.repoName(feedURL: source.feedURL) : nil
    }

    public var items: [FeedItem] {
        if case .items(let items) = outcome { return items }
        return []
    }

    public var error: FeedError? {
        if case .failed(let error) = outcome { return error }
        return nil
    }
}

/// Fetches many sources at once: at most six requests on the wire, fifteen seconds each, arXiv and Reddit paced
/// through their process-wide gates, and conditional GET so an unchanged feed costs a 304.
///
/// It returns values and stores nothing. The only state is the validators (`ETag`, `Last-Modified`) of feeds this
/// instance has read; they are keyed by source id as well as address, so a source that is removed and added again
/// (a new id, an empty item table) is fetched in full rather than answered with "not modified". Keep one instance
/// for the life of the app.
public actor Refresher {
    private let loader: SourceLoader
    private var validators: [String: Validators] = [:]

    /// Nobody is watching a background refresh, so it sits out a paced host's queue: a dozen arXiv categories at
    /// three seconds each, or Reddit's minute between subreddits. Results stream, so nothing else waits on them.
    private static let patience: TimeInterval = 120

    public init(fetch: @escaping HTTPFetch = HTTPClient.live, maxConcurrentRequests: Int = 6,
                timeout: TimeInterval = HTTPClient.timeout, arxivGate: HostGate = .arxiv, redditGate: HostGate = .reddit) {
        let limit = ConcurrencyLimit(maxConcurrentRequests)
        let bounded: HTTPFetch = { request in
            try await limit.run { try await withTimeout(timeout) { try await fetch(request) } }
        }
        loader = SourceLoader(fetch: bounded, arxivGate: arxivGate, redditGate: redditGate, patience: Self.patience)
    }

    /// One result per source, in the order they finish, so the list can fill while slow feeds are still loading.
    /// Ending the iteration early cancels the requests still in flight.
    public nonisolated func refresh(_ sources: [Source]) -> AsyncStream<SourceRefresh> {
        AsyncStream { continuation in
            let work = Task {
                await withTaskGroup(of: SourceRefresh?.self) { group in
                    for source in sources { group.addTask { await self.refreshOne(source) } }
                    for await result in group {
                        if let result { continuation.yield(result) }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in work.cancel() }
        }
    }

    /// The same, collected and returned in the order the sources were given.
    public func refreshAll(_ sources: [Source]) async -> [SourceRefresh] {
        var byFeed: [String: SourceRefresh] = [:]
        for await result in refresh(sources) { byFeed[Self.key(for: result.source)] = result }
        return sources.compactMap { byFeed[Self.key(for: $0)] }
    }

    /// Runs off the actor: parsing is the expensive part, and six feeds should parse side by side.
    /// - Returns: nil only when the refresh was cancelled.
    private nonisolated func refreshOne(_ source: Source) async -> SourceRefresh? {
        let key = Self.key(for: source)
        do {
            guard let feed = try await loader.load(kind: source.kind, feedURL: source.feedURL, validators: await validators[key]) else {
                return SourceRefresh(source: source, outcome: .notModified)
            }
            // Remembered only now that the body has parsed: a broken response must not be answered with 304 forever after.
            await remember(feed.validators, for: key)
            return SourceRefresh(source: source, outcome: .items(feed.items))
        } catch is CancellationError {
            return nil
        } catch {
            let failure = (error as? FeedError) ?? .network(error.localizedDescription)
            return SourceRefresh(source: source, outcome: .failed(failure))
        }
    }

    private func remember(_ fresh: Validators, for key: String) {
        validators[key] = fresh.isEmpty ? nil : fresh
    }

    private static func key(for source: Source) -> String { "\(source.id) \(source.feedURL.absoluteString)" }
}
