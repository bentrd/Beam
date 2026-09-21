import AppKit
import BeamExtract
import BeamFeeds
import BeamJev
import BeamModels
import BeamStore
import Foundation

/// Everything between the pixels and the world: one SQLite file, one judge, one feed refresher, one extractor.
///
/// The window talks to `BeamBackend` and nothing else, so the same interface runs against `FakeBackend` for
/// design reviews and against this for real. What the app promises is kept here: with no key Beam is a plain
/// chronological reader that sends nothing at all; with one, every list and every article is ranked against one
/// sentence, cache first, and every sentence Beam says is the exact copy of DESIGN.md section 6.
@MainActor
public final class Engine: BeamBackend {
    /// ~/Library/Application Support/Beam/beam.sqlite. Open it once per process: a second database on the same
    /// file would end the first one's Undo.
    public nonisolated static var defaultDatabaseURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("Beam", isDirectory: true).appendingPathComponent("beam.sqlite")
    }

    static let seededKey = "sources.seeded"
    static let prejudgeKey = "settings.prejudgesTopResults"

    let environment: EngineEnvironment
    let context: EngineContext
    let refresher: Refresher
    let resolver: SourceResolver
    let lists: ListController
    let reader: ReaderController
    let prejudge: Prejudge
    let undoStack = UndoStack()

    var sidebarContinuation: AsyncStream<SidebarSnapshot>.Continuation?
    var unread = UnreadCounts()
    var pinSummaries: [PinSummary] = []
    /// Set when a pass over the pins left items unjudged after its retries: the pin rows then warn.
    var pinsHaveUnchecked = false
    var launchTask: Task<Void, Never>?
    var validation: Task<KeyStatus, Never>?
    var pinTimer: Task<Void, Never>?
    var wakeObserver: (any NSObjectProtocol)?

    private var prejudgesTopResultsStorage = false
    public var prejudgesTopResults: Bool {
        get { prejudgesTopResultsStorage }
        set {
            guard newValue != prejudgesTopResultsStorage else { return }
            prejudgesTopResultsStorage = newValue
            let database = context.database
            Task { try? await database.setMeta(Self.prejudgeKey, to: newValue ? "1" : "0") }
            if !newValue { prejudge.cancel() }
        }
    }

    public var undoTitle: String? { undoStack.title }

    // MARK: Building one

    public convenience init(databaseURL: URL = Engine.defaultDatabaseURL) throws {
        try self.init(environment: EngineEnvironment(databaseURL: databaseURL))
    }

    public init(environment: EngineEnvironment) throws {
        self.environment = environment
        let database = try environment.databaseURL.map { try Database(fileURL: $0) } ?? Database.inMemory()
        let spend = SpendMeter(ceiling: environment.spendCeiling, readerReserve: environment.readerReserve,
                               persistence: SpendLedger(database: database), now: environment.now)
        let keyProvider = environment.keyProvider
        let judge = Judge(keyProvider: { keyProvider.key() }, spend: spend,
                          maxInFlight: environment.maxInFlight, client: environment.jevClient)
        context = EngineContext(database: database, judge: judge, spend: spend, cache: JudgmentCache(database: database),
                                models: ModelRegistry(database: database),
                                articles: ArticleLoader(fetcher: environment.pageFetcher),
                                maxInFlight: environment.maxInFlight, now: environment.now)
        refresher = Refresher(fetch: environment.feedFetch)
        resolver = SourceResolver(fetch: environment.feedFetch)
        lists = ListController(context: context)
        reader = ReaderController(context: context)
        prejudge = Prejudge(context: context)

        // Optimistic: a key that is there is assumed to work until the launch check says otherwise, so the first
        // search of a launch does not wait on a round trip. A refusal corrects it and the foot says so.
        context.keyStatus = keyProvider.key() == nil ? .missing : .valid
        lists.onSettled = { [weak self] run in self?.listSettled(run) }
        reader.onOpened = { [weak self] itemID in self?.opened(itemID) }
        launchTask = Task { [weak self] in await self?.launch() }
    }

    deinit {
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }

    /// Returns once the first launch has seeded, read its settings and validated the key. The app never needs
    /// this; checks do, so that they can say what they measured.
    public func launched() async {
        await launchTask?.value
    }

    private func launch() async {
        await context.models.load()
        prejudgesTopResultsStorage = (try? await context.database.meta(Self.prejudgeKey)) == "1"
        await seedStarterSources()
        await reloadSidebar()
        validateKey()
        if environment.refreshesOnLaunch { await refresh() }
        startPinTimer()
        watchForWaking()
    }

    // MARK: Key, privacy, spend

    public func keyStatus() async -> KeyStatus {
        if let validation { return await validation.value }
        return context.keyStatus
    }

    /// The key sheet and Settings. An empty key removes the stored one; anything else is checked with one
    /// constant-string request that carries nothing of the user's before it is stored.
    public func setKey(_ key: String?) async -> KeyStatus {
        let typed = (key ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else {
            do { try environment.keyProvider.remove() } catch { EngineLog.failure("removing the key", error) }
            context.keyStatus = .missing
            validation = nil
            lists.reload()
            return .missing
        }
        let status = await context.judge.validate(key: typed)
        if status == .valid {
            do { try environment.keyProvider.set(typed) } catch { EngineLog.failure("storing the key", error) }
        }
        context.keyStatus = status
        validation = Task { status }
        // "On success the sheet closes and the waiting sentence runs."
        if status == .valid { lists.retry() }
        return status
    }

    public func dollarsToday() async -> Double {
        await context.spend.dollarsToday
    }

    private func validateKey() {
        guard environment.keyProvider.key() != nil else {
            context.keyStatus = .missing
            validation = Task { .missing }
            return
        }
        validation = Task { [context] in
            let status = await context.judge.validateKey()
            // An unreachable service is not a bad key: keep sending, and let the run say "Offline" if it is.
            if status != .unreachable { context.keyStatus = status }
            return status
        }
    }

    // MARK: Undo

    public func undo() async -> String? {
        let title = await undoStack.undo()
        guard title != nil else { return nil }
        await reloadSidebar()
        lists.reload()
        return title
    }

    // MARK: Reader

    /// A selected row: title, snippet and "Return to read". It reads what the list already has in memory, so it
    /// fetches nothing and sends nothing.
    public func preview(itemID: Int64) -> ReaderSnapshot? {
        guard let item = lists.item(itemID) else { return nil }
        return ReaderSnapshot(item: item, sourceTitle: context.sourceTitle(item.sourceID), phase: .preview,
                              foot: opensInBrowser(item) ? Feet.returnToOpenInBrowser : Feet.returnToRead)
    }

    public func open(itemID: Int64, carrying sentence: String?) -> AsyncStream<ReaderSnapshot> {
        reader.open(itemID: itemID, carrying: sentence ?? lists.carriedSentence)
    }

    public func find(_ sentence: String?) { reader.find(sentence) }
    public func setViewport(firstVisible: Int, lastVisible: Int) { reader.setViewport(firstVisible: firstVisible, lastVisible: lastVisible) }
    public func retryReader() { reader.retry() }
    public func closeReader() { reader.close() }

    /// A YouTube row has nothing to read in Beam; Return sends it to the browser.
    private func opensInBrowser(_ item: Item) -> Bool {
        if context.sourceKind(item.sourceID) == .youtube { return true }
        guard let host = item.url?.host?.lowercased() else { return false }
        return host == "youtu.be" || host == "youtube.com" || host.hasSuffix(".youtube.com")
    }

    /// Opening an item is what makes it read; arrowing past it never does.
    private func opened(_ itemID: Int64) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.context.database.markOpened(itemID: itemID, at: self.environment.now())
            } catch {
                EngineLog.failure("marking item \(itemID) read", error)
            }
            self.lists.applyRead(true, ids: [itemID])
            await self.reloadUnread()
        }
    }

    // MARK: Lists

    public func list(_ request: ListRequest) -> AsyncStream<ListSnapshot> {
        prejudge.cancel()
        return lists.list(request)
    }

    public func checkOlder() { lists.checkOlder() }
    public func retryList() { lists.retry() }

    public func setRead(_ read: Bool, itemIDs: [Int64]) async {
        guard !itemIDs.isEmpty else { return }
        do {
            let changed = try await context.database.setRead(read, itemIDs: itemIDs)
            lists.applyRead(read, ids: Set(changed))
        } catch {
            EngineLog.failure("changing read state", error)
        }
        await reloadUnread()
    }

    /// ⌘K, on the current list scope, undoable. A pin's scope is decided by judgments, so its rows are named one by one.
    public func markAllRead(in scope: ListScope) async {
        var changed: [Int64] = []
        do {
            if case .pin = scope {
                changed = try await context.database.setRead(true, itemIDs: lists.unreadRowIDs())
            } else {
                changed = try await context.database.markAllRead(in: ListController.itemScope(of: scope))
            }
        } catch {
            EngineLog.failure("marking everything read", error)
        }
        guard !changed.isEmpty else { return }
        lists.applyRead(true, ids: Set(changed))
        await reloadUnread()
        undoStack.push("Undo Mark All as Read") { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.context.database.setRead(false, itemIDs: changed)
                self.lists.applyRead(false, ids: Set(changed))
            } catch {
                EngineLog.failure("undoing Mark All as Read", error)
            }
            await self.reloadUnread()
        }
    }

    /// A settled search is where pre-judging starts, if Ben allows it.
    private func listSettled(_ run: ListRun) {
        guard prejudgesTopResults, let sentence = run.sentence, !run.isPin else { return }
        prejudge.start(items: lists.topFound(Windows.prejudgedRows), sentence: sentence)
    }
}
