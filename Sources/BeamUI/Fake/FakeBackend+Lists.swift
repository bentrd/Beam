import BeamModels
import Foundation

/// One `list(_:)` call: the request, its stream, and how far its run has got.
struct ListRun {
    var request: ListRequest
    let continuation: AsyncStream<ListSnapshot>.Continuation
    var task: Task<Void, Never>?
    /// When this list was asked for: the first-fetch line waits a second before it appears.
    let started = Date()
    /// How many of the newest items the run covers. "Check 53 older" widens it.
    var window: Int
    var isRunning = false
    var failed: Set<Int64> = []
    var hasRetried = false
    var stoppedAfterErrors = false
    var reachedDailyLimit = false
    /// A running count may show only after a 3 s stall or a failure; otherwise the foot does not tick.
    var showsProgress = false
    /// Hide Read Items: rows stay until the list is asked for again, so opening a row never pulls it from under the pointer.
    var keptWhileHidingRead: Set<Int64> = []

    /// A pin scope supplies its own sentence and is always fully checked.
    var isPinList: Bool { if case .pin = request.scope { return true }; return false }
}

extension FakeBackend {
    /// The capture holds 203 items; checking the newest 150 first keeps "Check 53 older" within reach of a review.
    private static let firstWindow = 150
    private static let ticks = 8
    private static let tick = Duration.milliseconds(190)
    /// How long a first fetch may take before Beam says it is fetching.
    private static let firstFetchNotice: TimeInterval = 1

    // MARK: BeamBackend

    public func list(_ request: ListRequest) -> AsyncStream<ListSnapshot> {
        listRun?.task?.cancel()
        listRun?.continuation.finish()
        let (stream, continuation) = AsyncStream<ListSnapshot>.makeStream()
        var run = ListRun(request: request, continuation: continuation, window: Self.firstWindow)
        if request.hidesRead { run.keptWhileHidingRead = Set(items.filter { !$0.read }.map(\.id)) }
        listRun = run
        startListRun()
        // Nothing has arrived yet: come back in a second to say so, since no snapshot is due before then.
        if !undelivered.isEmpty { sayFetchingAfterASecond(of: run) }
        return stream
    }

    private func sayFetchingAfterASecond(of run: ListRun) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.firstFetchNotice))
            guard let self, self.listRun?.started == run.started else { return }
            self.publishList()
        }
    }

    public func checkOlder() {
        listRun?.window = items.count
        startListRun()
    }

    public func retryList() {
        guard listRun != nil else { return }
        listRun?.failed = []
        listRun?.hasRetried = true
        listRun?.stoppedAfterErrors = false
        startListRun()
    }

    public func setRead(_ read: Bool, itemIDs: [Int64]) async {
        let wanted = Set(itemIDs)
        for index in items.indices where wanted.contains(items[index].id) { items[index].read = read }
        publishEverything()
    }

    public func markAllRead(in scope: ListScope) async {
        let changed = Set(scopedItems(scope).filter { !$0.read }.map(\.id))
        guard !changed.isEmpty else { return }
        for index in items.indices where changed.contains(items[index].id) { items[index].read = true }
        undoStack.append(UndoEntry(title: "Undo Mark All as Read") { [weak self] in
            guard let self else { return }
            for index in self.items.indices where changed.contains(self.items[index].id) { self.items[index].read = false }
        })
        publishEverything()
    }

    // MARK: The run

    func publishList() {
        guard let run = listRun else { return }
        run.continuation.yield(snapshot(for: run))
    }

    /// The sentence a request ranks by: the typed one, or the pin's own.
    func sentence(of request: ListRequest) -> String? {
        if case .pin(let id) = request.scope { return pins.first { $0.id == id }.map { FakeJudge.normalise($0.sentence) } }
        return request.sentence.map(FakeJudge.normalise).flatMap { $0.isEmpty ? nil : $0 }
    }

    private var canJudge: Bool { status == .valid && scenario != .offline }

    private func startListRun() {
        listRun?.task?.cancel()
        listEpoch += 1
        let epoch = listEpoch
        guard let run = listRun, let sentence = sentence(of: run.request), canJudge, !run.reachedDailyLimit else {
            listRun?.isRunning = false
            return publishList()
        }
        let waiting = unchecked(sentence, window: run.window)
        guard !waiting.isEmpty else {
            listRun?.isRunning = false
            return publishList()
        }
        listRun?.isRunning = true
        publishList()
        listRun?.task = Task { [weak self] in await self?.judge(waiting, about: sentence, epoch: epoch) }
    }

    /// Newest first, but judged in a scattered order: answers never come back in rank order, and the list must cope.
    private func unchecked(_ sentence: String, window: Int) -> [Item] {
        let known = itemChecks[sentence] ?? [:]
        return items.prefix(window).filter { known[$0.id] == nil }.sorted { FakeJudge.hash($0.guid) < FakeJudge.hash($1.guid) }
    }

    private func judge(_ waiting: [Item], about sentence: String, epoch: Int) async {
        let size = max((waiting.count + Self.ticks - 1) / Self.ticks, 1)
        let batches = stride(from: 0, to: waiting.count, by: size).map { Array(waiting[$0..<min($0 + size, waiting.count)]) }
        var consecutiveFailures = 0

        for (number, batch) in batches.enumerated() {
            guard await pause(Self.tick, epoch: epoch) else { return }
            if scenario == .stall, number == batches.count / 2 {
                guard await pause(.seconds(3), epoch: epoch) else { return }
                listRun?.showsProgress = true
                publishList()
                guard await pause(.seconds(1), epoch: epoch) else { return }
            }
            if scenario == .limit, number >= batches.count / 3 {
                listRun?.reachedDailyLimit = true
                break
            }
            for item in batch {
                if fails(item, batch: number) {
                    listRun?.failed.insert(item.id)
                    listRun?.showsProgress = true
                    consecutiveFailures += 1
                } else {
                    itemChecks[sentence, default: [:]][item.id] = probability(of: item, about: sentence)
                    spent += 0.000_025                                   // about 600 tokens an item (EVIDENCE.md)
                    consecutiveFailures = 0
                }
                if consecutiveFailures >= 10 { listRun?.stoppedAfterErrors = true; break }
            }
            if listRun?.stoppedAfterErrors == true { break }
            publishList()
        }
        listRun?.isRunning = false
        publishList()
    }

    private func fails(_ item: Item, batch: Int) -> Bool {
        guard listRun?.hasRetried == false else { return false }
        switch scenario {
        case .failures: return FakeJudge.hash(item.guid) % 7 == 0
        case .stopped: return batch >= 2
        default: return false
        }
    }

    /// Sleeps, then says whether this run is still the current one.
    private func pause(_ duration: Duration, epoch: Int) async -> Bool {
        do { try await Task.sleep(for: duration) } catch { return false }
        return epoch == listEpoch
    }

    // MARK: Snapshots

    func scopedItems(_ scope: ListScope) -> [Item] {
        switch scope {
        case .all: return items
        case .source(let id): return items.filter { $0.sourceID == id }
        case .pin(let id):
            guard let pin = pins.first(where: { $0.id == id }) else { return [] }
            let checks = itemChecks[FakeJudge.normalise(pin.sentence)] ?? [:]
            return items.filter { (checks[$0.id] ?? 0) >= Bands.listFound }
        }
    }

    private func snapshot(for run: ListRun) -> ListSnapshot {
        var snapshot = ListSnapshot(request: run.request, isRunning: run.isRunning || !undelivered.isEmpty)
        let sentence = sentence(of: run.request)
        let titles = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0.title) })
        func row(_ item: Item, check: Double? = nil, marked: Bool = false) -> Row {
            Row(item: item, sourceTitle: titles[item.sourceID] ?? "", check: check.map(Check.judged), isMarked: marked)
        }

        if case .pin(let id) = run.request.scope, let pin = pins.first(where: { $0.id == id }) {
            // Found rows by date, unmarked; the full-width separator runs under the last row that is new.
            let found = scopedItems(run.request.scope)
            let checks = itemChecks[FakeJudge.normalise(pin.sentence)] ?? [:]
            snapshot.rows = found.map { row($0, check: checks[$0.id]) }
            snapshot.lastNewRowID = found.last { $0.sortDate > (pin.lastViewed ?? .distantPast) }?.id
        } else if let sentence {
            let checks = itemChecks[sentence] ?? [:]
            snapshot.rows = scopedItems(run.request.scope)
                .compactMap { item in checks[item.id].map { (item, $0) } }
                .filter { $0.1 >= Bands.listUnsure }
                .sorted { a, b in
                    let (ra, rb) = ((a.1 * 20).rounded(), (b.1 * 20).rounded())          // probability rounded to 0.05, then date
                    return ra != rb ? ra > rb : a.0.sortDate > b.0.sortDate
                }
                .map { row($0.0, check: $0.1, marked: $0.1 >= Bands.listFound) }
        } else {
            snapshot.rows = plainRows(run, row: row)
        }

        snapshot.foot = foot(for: run, sentence: sentence, rowCount: snapshot.rows.count)
        if snapshot.rows.isEmpty { (snapshot.emptyMessage, snapshot.emptyAction) = emptiness(for: run, sentence: sentence) }
        return snapshot
    }

    /// No sentence: by date. All Items puts this week's pin hits first, marked, with no divider.
    private func plainRows(_ run: ListRun, row: (Item, Double?, Bool) -> Row) -> [Row] {
        var shown = scopedItems(run.request.scope)
        if run.request.hidesRead { shown.removeAll { $0.read && !run.keptWhileHidingRead.contains($0.id) } }
        guard run.request.scope == .all else { return shown.map { row($0, nil, false) } }
        let weekAgo = Date().addingTimeInterval(-7 * 86_400)
        let pinChecks = pins.compactMap { itemChecks[FakeJudge.normalise($0.sentence)] }
        let isHit: (Item) -> Bool = { item in item.sortDate > weekAgo && pinChecks.contains { ($0[item.id] ?? 0) >= Bands.listFound } }
        return shown.filter(isHit).map { row($0, nil, true) } + shown.filter { !isHit($0) }.map { row($0, nil, false) }
    }

    /// One message at a time, in DESIGN.md's priority order.
    private func foot(for run: ListRun, sentence: String?, rowCount: Int) -> Foot {
        guard !sources.isEmpty else { return .blank }
        let failingSource: Source? = { if case .source(let id) = run.request.scope { return sources.first { $0.id == id && $0.lastError != nil } }; return nil }()
        // There is one order, and it is the list foot's. A pin is a ranked list like a search, so a missing or
        // rejected key, the daily limit, offline, a stopped run and "N not checked" are said under a pin too.
        let isRanked = sentence != nil

        if isRanked {
            if status == .missing { return FakeFeet.addKey }
            if status == .rejected { return FakeFeet.keyRejected }
            if run.reachedDailyLimit { return FakeFeet.dailyLimit }
            if scenario == .offline || status == .unreachable { return FakeFeet.offline }
            if run.stoppedAfterErrors { return FakeFeet.stopped }
            if !run.isRunning, !run.failed.isEmpty { return FakeFeet.notChecked(run.failed.count) }
        }
        if let failingSource { return FakeFeet.couldNotRefresh(failingSource.lastError ?? "") }
        guard let sentence else {
            if case .source(let id) = run.request.scope { return FakeFeet.items(rowCount, in: sources.first { $0.id == id }?.title) }
            return FakeFeet.items(rowCount)
        }
        // Only a sentence just typed earns the note: a pin's was vetted when it was pinned.
        if !run.isPinList, FakeJudge.asksForExclusionAmountOrDate(sentence) { return FakeFeet.exclusions }

        let covered = run.isPinList ? items.count : min(run.window, items.count)
        let checked = items.prefix(covered).filter { itemChecks[sentence]?[$0.id] != nil }.count
        if run.isRunning { return run.showsProgress ? FakeFeet.progress(checked, of: covered) : FakeFeet.checking(covered) }
        if covered < items.count { return FakeFeet.newest(covered, of: items.count, older: items.count - covered) }
        return FakeFeet.checked(checked)
    }

    private func emptiness(for run: ListRun, sentence: String?) -> (String?, FootAction?) {
        if sources.isEmpty { return (FakeFeet.noSources, .addSource) }
        if !undelivered.isEmpty {
            // Nothing is said about a fetch that answers within a second.
            return (Date().timeIntervalSince(run.started) >= Self.firstFetchNotice ? FakeFeet.gettingSources : nil, nil)
        }
        if run.isPinList { return (FakeFeet.nothingFound(in: items.count), nil) }
        guard let sentence else {
            // Every row hidden as read is not an empty source: only a source with nothing fetched says so.
            return (scopedItems(run.request.scope).isEmpty ? FakeFeet.noItems : nil, nil)
        }
        // "Nothing found" is only ever said about what was checked, once the run has settled.
        guard !run.isRunning, canJudge else { return (nil, nil) }
        let checked = items.prefix(run.window).filter { itemChecks[sentence]?[$0.id] != nil }.count
        return (FakeFeet.nothingFound(in: checked), nil)
    }
}
