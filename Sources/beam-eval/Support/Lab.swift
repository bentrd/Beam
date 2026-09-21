import BeamEngine
import BeamFeeds
import BeamJev
import BeamModels
import Foundation

/// One engine, wired to whatever a check needs, with its own empty database.
///
/// Checks build a lab rather than an engine, because what makes a check worth anything is what it can see: how
/// many requests were sent, what the web answered, and how long each snapshot took to arrive.
@MainActor
struct Lab {
    let engine: Engine
    let jev: StubJev
    let web: StubWeb
    let pages: StubPages

    /// An engine with no network of its own: feeds, pages and TypeSafe all answer from fixtures.
    static func offline(starters: [SourceCandidate] = [], hasKey: Bool = true,
                        jev: StubJev = StubJev(), web: StubWeb = StubWeb(), pages: StubPages = StubPages(),
                        spendCeiling: Double = SpendMeter.dailyCeiling, readerReserve: Double = SpendMeter.readerReserve,
                        maxInFlight: Int = 64, refreshesOnLaunch: Bool = true) async throws -> Lab {
        var environment = EngineEnvironment.check(jevClient: jev.client, feedFetch: web.fetch, pageFetcher: pages,
                                                  keyProvider: keyProvider(hasKey ? "eval-key" : nil))
        environment.starters = starters.map { CatalogEntry(candidate: $0, blurb: "A fixture", isStarter: true) }
        environment.catalog = environment.starters
        environment.spendCeiling = spendCeiling
        environment.readerReserve = readerReserve
        environment.maxInFlight = maxInFlight
        environment.refreshesOnLaunch = refreshesOnLaunch
        let engine = try Engine(environment: environment)
        await engine.launched()
        return Lab(engine: engine, jev: jev, web: web, pages: pages)
    }

    /// Fixtures for the web, the real judge for the answers: what a check needs when the question is whether the
    /// model lights the right paragraph, not whether the plumbing works.
    static func judging(key: String, starters: [SourceCandidate] = [], web: StubWeb = StubWeb(),
                        pages: StubPages = StubPages()) async throws -> Lab {
        var environment = EngineEnvironment.check(jevClient: JevClient(), feedFetch: web.fetch, pageFetcher: pages,
                                                  keyProvider: keyProvider(key))
        environment.starters = starters.map { CatalogEntry(candidate: $0, blurb: "A fixture", isStarter: true) }
        environment.catalog = environment.starters
        let engine = try Engine(environment: environment)
        await engine.launched()
        return Lab(engine: engine, jev: StubJev(), web: web, pages: pages)
    }

    /// An engine on the real web, with the real key, still in its own database.
    /// The stubs come along so a check can say how little was asked of them.
    static func live(starters: [CatalogEntry], key: String, refreshesOnLaunch: Bool = true) async throws -> Lab {
        var environment = EngineEnvironment(databaseURL: nil, keyProvider: keyProvider(key))
        environment.starters = starters
        environment.catalog = Catalog.entries
        environment.refreshesOnLaunch = refreshesOnLaunch
        environment.pinRefresh = nil
        environment.refreshesOnWake = false
        let engine = try Engine(environment: environment)
        await engine.launched()
        return Lab(engine: engine, jev: StubJev(), web: StubWeb(), pages: StubPages())
    }

    /// Never the real Keychain item, and never the user's service name.
    static func keyProvider(_ key: String?) -> KeyProvider {
        KeyProvider(service: "dev.beam.eval", environment: key.map { ["BEAM_KEY": $0] } ?? [:])
    }

    // MARK: Conveniences

    func search(_ sentence: String?, scope: ListScope = .all, hidesRead: Bool = false,
                within limit: Duration = .seconds(30)) async -> Trace<ListSnapshot> {
        await Wait.list(engine, ListRequest(scope: scope, sentence: sentence, hidesRead: hidesRead), within: limit)
    }

    func read(_ itemID: Int64, carrying sentence: String? = nil, within limit: Duration = .seconds(30)) async -> Trace<ReaderSnapshot> {
        await Wait.reader(engine, itemID: itemID, carrying: sentence, within: limit)
    }

    /// The sidebar as it stands, in one snapshot.
    func sidebar() async -> SidebarSnapshot {
        for await snapshot in engine.sidebar() { return snapshot }
        return SidebarSnapshot()
    }

    static func candidate(_ title: String, _ address: String, site: String? = nil, kind: SourceKind = .feed) -> SourceCandidate {
        SourceCandidate(kind: kind, title: title, feedURL: URL(string: address)!, siteURL: site.flatMap(URL.init(string:)))
    }
}
