import BeamEngine
import BeamFeeds
import BeamJev
import BeamModels
import BeamStore
import BeamUI
import Foundation

/// The recorder either replays the bundled design session or uses the real engine and live TypeSafe answers.
/// Live mode stores only captured public sample content in a temporary library and keeps its credential in memory.
@MainActor
final class BeamDemoBackend {
    let backend: any BeamBackend
    let isLive: Bool
    private let directory: URL?
    private let feedFixture: DemoFeedFixture?
    private let articleFixture: ReaderFixture?
    private let metrics = DemoLiveMetrics()
    private var hasPrepared = false

    var sourceDescription: String {
        isLive
            ? "Real BeamEngine and live TypeSafe Jev judgments over captured public sample feeds and article text; isolated temporary library; \(metrics.summary)"
            : "Beam views with bundled FakeBackend fixtures"
    }

    init(live: Bool) throws {
        isLive = live
        if !live {
            directory = nil
            feedFixture = nil
            articleFixture = nil
            backend = try FakeBackend(options: FakeOptions(keyStatus: .missing))
            return
        }
        guard let credential = ProcessInfo.processInfo.environment["BEAM_KEY"],
              !credential.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BeamDemoFailure(description: "--live requires BEAM_KEY in the launch environment")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BeamLiveDemo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.directory = directory
        let fixture = DemoFeedFixture()
        feedFixture = fixture
        articleFixture = try ReaderFixture.load(.lit)
        let meter = metrics
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.httpMaximumConnectionsPerHost = 32
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration)
        let client = JevClient(transport: { request in
            meter.started()
            let answer = try await session.data(for: request)
            meter.received(answer.0, response: answer.1)
            return answer
        })
        let provider = KeyProvider(environment: [:], storage: DemoMemoryKey())
        let environment = EngineEnvironment(databaseURL: directory.appendingPathComponent("demo.sqlite"),
                                            keyProvider: provider, jevClient: client, feedFetch: fixture.fetch,
                                            pageFetcher: UnreachablePages(), catalog: [], starters: [],
                                            maxInFlight: 32, refreshesOnLaunch: false, pinRefresh: nil, refreshesOnWake: false)
        backend = try Engine(environment: environment)
    }

    /// Loads source text only. Captured probabilities and the developer's real library are never copied.
    func prepare() async throws {
        guard !hasPrepared else { return }
        hasPrepared = true
        guard let engine = backend as? Engine, let directory, let feedFixture, let articleFixture else { return }
        await engine.launched()
        let captured = try FakeBackend(options: FakeOptions(keyStatus: .missing))
        var rows: [Row] = []
        for await snapshot in captured.list(ListRequest(scope: .all, sentence: nil)) {
            rows = snapshot.rows
            break
        }
        guard !rows.isEmpty else { throw BeamDemoFailure(description: "the public sample feed capture was empty") }
        var sample = Array(rows.prefix(24))
        if !sample.contains(where: { $0.item.url == articleFixture.item.url }),
           let article = rows.first(where: { $0.item.url == articleFixture.item.url }) {
            sample.append(article)
        }
        guard sample.contains(where: { $0.item.url == articleFixture.item.url }) else {
            throw BeamDemoFailure(description: "the public sample article was missing from its feed capture")
        }
        // The captured post's first paragraph is a year-in-review introduction. Use its genuine local-model
        // excerpt as this sample feed's description, so the live narrow search can select it by its own words.
        if let excerpt = articleFixture.passages.first(where: { $0.isJudgeable && $0.text.contains("GPT-4 class model on my laptop") }),
           let position = sample.firstIndex(where: { $0.item.url == articleFixture.item.url }) {
            sample[position].item.snippet = String(excerpt.text.prefix(300))
        }
        let sources = feedFixture.install(sample)
        for source in sources {
            guard case .added = await engine.addSource(source) else {
                throw BeamDemoFailure(description: "could not seed the isolated public sample feed")
            }
        }
        // Seed the extracted public text directly into this disposable library. Its old judgment values are
        // deliberately absent; opening and Find by Meaning both call the real TypeSafe service.
        let database = try Database(fileURL: directory.appendingPathComponent("demo.sqlite"))
        let items = try await database.newestItems(in: .all, limit: 100)
        guard let article = items.first(where: { $0.url == articleFixture.item.url }) else {
            throw BeamDemoFailure(description: "the isolated sample article was not stored")
        }
        var passages = articleFixture.passages
        if passages.first?.kind == .heading, passages.first?.text == articleFixture.item.title { passages.removeFirst() }
        try await database.putArticle(.ready(passages: passages, images: articleFixture.omittedImages, tables: 0), itemID: article.id)
    }

    /// The key is never put into the view's draft field, preferences, recorder manifest or filesystem.
    func connect(model: AppModel) async -> KeyStatus {
        if !isLive { return await model.setKey("demo-fixture-key") }
        guard let credential = ProcessInfo.processInfo.environment["BEAM_KEY"] else { return .missing }
        return await model.setKey(credential)
    }

    func cleanup() {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }
}

private final class DemoMemoryKey: KeyStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var credential: String?
    func read() throws -> String? { lock.withLock { credential } }
    func write(_ key: String) throws { lock.withLock { credential = key } }
    func remove() throws { lock.withLock { credential = nil } }
}

/// Serves captured public feed bytes to the normal parser; it has no TypeSafe transport or judgment cache.
private final class DemoFeedFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var bodies: [URL: Data] = [:]
    var fetch: HTTPFetch {
        { [self] request in
            guard let body = lock.withLock({ bodies[request.url] }) else {
                throw FeedError.network("This sample source is not in the isolated showcase")
            }
            return HTTPResponse(url: request.url, status: 200, headers: ["Content-Type": "application/rss+xml; charset=utf-8"], body: body)
        }
    }

    func install(_ rows: [Row]) -> [SourceCandidate] {
        let titles = Array(Set(rows.map(\.sourceTitle))).sorted()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        var sources: [SourceCandidate] = []
        for (index, title) in titles.enumerated() {
            let address = URL(string: "https://showcase.beam.invalid/captured/\(index).xml")!
            let posts = rows.filter { $0.sourceTitle == title }.map { row in
                let item = row.item
                return "<item><guid>\(Self.xml(item.guid))</guid><title>\(Self.xml(item.title))</title><link>\(Self.xml(item.url?.absoluteString ?? ""))</link><description>\(Self.xml(item.snippet))</description><pubDate>\(formatter.string(from: item.sortDate))</pubDate></item>"
            }.joined()
            let xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><rss version=\"2.0\"><channel><title>\(Self.xml(title))</title><link>\(Self.xml(rows.first(where: { $0.sourceTitle == title })?.item.url?.absoluteString ?? ""))</link><description>Captured public sample feed</description>\(posts)</channel></rss>"
            lock.withLock { bodies[address] = Data(xml.utf8) }
            sources.append(SourceCandidate(kind: .feed, title: title, feedURL: address,
                                           siteURL: rows.first(where: { $0.sourceTitle == title })?.item.url))
        }
        return sources
    }

    private static func xml(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}

/// Only usage metadata is recorded. Requests, authorization headers and user credentials are never retained here.
private final class DemoLiveMetrics: @unchecked Sendable {
    private let lock = NSLock()
    private var attempts = 0
    private var answers = 0
    private var tokens = 0
    private var models: Set<String> = []
    func started() { lock.withLock { attempts += 1 } }
    func received(_ body: Data, response: URLResponse) {
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let payload = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else { return }
        lock.withLock {
            answers += 1
            if let model = payload["model"] as? String { models.insert(model) }
            if let usage = payload["usage"] as? [String: Any], let count = usage["input_tokens"] as? Int { tokens += count }
        }
    }
    var summary: String {
        lock.withLock { "\(attempts) API attempts, \(answers) successful answers, \(tokens) input tokens, models \(models.sorted().joined(separator: ", "))" }
    }
}
