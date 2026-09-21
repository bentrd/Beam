import BeamExtract
import BeamFeeds
import BeamJev
import BeamModels
import Foundation

/// Everything the engine talks to that a check may want to replace: the file it stores in, the transport under
/// each of the three networks it uses (TypeSafe, feeds, article pages), the catalog it seeds from, and the clock.
///
/// The defaults are the product. `beam-eval` changes the parts it needs and leaves the rest alone, so what it
/// checks is the engine the app runs, not a rehearsal of it.
public struct EngineEnvironment: Sendable {
    /// Where the one SQLite file lives. nil opens a private in-memory database that vanishes with the engine.
    public var databaseURL: URL?
    /// The key, from the login Keychain with a `BEAM_KEY` / `TYPESAFE_API_KEY` fallback for dev builds.
    public var keyProvider: KeyProvider
    /// The TypeSafe client. Pass one with a transport to count or fail requests without a network.
    public var jevClient: JevClient
    /// The transport feeds are fetched and resolved through.
    public var feedFetch: HTTPFetch
    /// The transport article pages are downloaded through.
    public var pageFetcher: any PageFetching
    /// What the Add Source popover offers.
    public var catalog: [CatalogEntry]
    /// What a first launch starts with: Hacker News, MLX releases, Apple Machine Learning Research.
    public var starters: [CatalogEntry]
    /// The silent daily breaker and the slice of it kept for reading.
    public var spendCeiling: Double
    public var readerReserve: Double
    /// The one global cap on requests in flight, shared by search, pins, the reader and pre-judging.
    /// 96, which EVIDENCE.md measured against the live service without a single rate-limit refusal. Every wave
    /// costs about 300 ms, so the cap is what decides how soon a sparse hit in a 300-item library is reached.
    public var maxInFlight: Int
    /// Whether launching fetches every source. Off in checks that want to control when the network is touched.
    public var refreshesOnLaunch: Bool
    /// How often pins are brought up to date, or nil for never (checks drive the pass by hand).
    public var pinRefresh: Duration?
    /// Whether waking the Mac brings pins up to date.
    public var refreshesOnWake: Bool
    public var now: @Sendable () -> Date

    public init(databaseURL: URL? = Engine.defaultDatabaseURL,
                keyProvider: KeyProvider = KeyProvider(),
                jevClient: JevClient = JevClient(),
                feedFetch: @escaping HTTPFetch = HTTPClient.live,
                pageFetcher: any PageFetching = PageFetcher(),
                catalog: [CatalogEntry] = Catalog.entries,
                starters: [CatalogEntry] = Catalog.starters,
                spendCeiling: Double = SpendMeter.dailyCeiling,
                readerReserve: Double = SpendMeter.readerReserve,
                maxInFlight: Int = 96,
                refreshesOnLaunch: Bool = true,
                pinRefresh: Duration? = Windows.pinRefresh,
                refreshesOnWake: Bool = true,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.databaseURL = databaseURL
        self.keyProvider = keyProvider
        self.jevClient = jevClient
        self.feedFetch = feedFetch
        self.pageFetcher = pageFetcher
        self.catalog = catalog
        self.starters = starters
        self.spendCeiling = spendCeiling
        self.readerReserve = readerReserve
        self.maxInFlight = maxInFlight
        self.refreshesOnLaunch = refreshesOnLaunch
        self.pinRefresh = pinRefresh
        self.refreshesOnWake = refreshesOnWake
        self.now = now
    }

    /// A self-contained engine: in-memory store, no launch refresh, no timers. What every offline check starts from.
    public static func check(jevClient: JevClient = JevClient(transport: { _ in throw JevError.unreachable("no transport in checks") }),
                             feedFetch: @escaping HTTPFetch = { _ in throw FeedError.network("no network in checks") },
                             pageFetcher: any PageFetching = UnreachablePages(),
                             keyProvider: KeyProvider = KeyProvider(service: "dev.beam.check", environment: [:])) -> EngineEnvironment {
        EngineEnvironment(databaseURL: nil, keyProvider: keyProvider, jevClient: jevClient, feedFetch: feedFetch,
                          pageFetcher: pageFetcher, catalog: [], starters: [], refreshesOnLaunch: false,
                          pinRefresh: nil, refreshesOnWake: false)
    }
}

/// The page fetcher a check gets unless it asks for another: every article is simply not there.
public struct UnreachablePages: PageFetching {
    public init() {}
    public func fetch(_ url: URL) async throws -> FetchedPage { throw FetchFailure.transport("No network in checks") }
}
