import BeamJev
import BeamModels
import BeamStore
import Foundation

/// The list: one run at a time, cache first, then one request per item carrying every active sentence.
///
/// Every call of `list(_:)` ends the previous run and cancels its outstanding requests, which is how "a new
/// Return is the stop" is implemented. Snapshots leave here at most every 200 ms, fully ordered; what fades and
/// what waits is the view's business (DESIGN.md section 5).
@MainActor
final class ListController {
    private let context: EngineContext
    private var run: ListRun?
    private var throttle: SnapshotThrottle!
    /// Bumped by every start, so an answer from a run that has been replaced is dropped rather than shown.
    private var epoch = 0

    /// Called whenever a ranked run settles, so the engine can pre-judge the top results if Ben allows it.
    var onSettled: ((ListRun) -> Void)?

    init(context: EngineContext) {
        self.context = context
        throttle = SnapshotThrottle(every: Windows.listTick) { [weak self] in self?.publishNow() }
    }

    // MARK: What the engine asks of it

    func list(_ request: ListRequest) -> AsyncStream<ListSnapshot> {
        end()
        let (stream, continuation) = AsyncStream<ListSnapshot>.makeStream()
        let pin = pin(of: request.scope)
        let typed = pin?.sentence ?? request.sentence
        let sentence = typed.map(Sentence.init).flatMap { $0.isEmpty ? nil : $0 }
        run = ListRun(request: request, continuation: continuation, sentence: sentence,
                      framed: sentence.map(FramedSentence.item),
                      // Clicking a source during a search filters what is already checked and sends nothing.
                      sendsRequests: sentence != nil && !isLocalFilter(request),
                      pin: pin, judgeWindow: sentence == nil ? 0 : Windows.newest)
        start()
        return stream
    }

    /// "Check 1,200 older": the same run, over a wider window. It is a deliberate ask, so it sends even in a
    /// scope that was only filtering locally.
    func checkOlder() {
        guard run?.isRanked == true else { return }
        run?.judgeWindow += Windows.older
        run?.sendsRequests = true
        start()
    }

    /// The Retry of "31 not checked" and of "Stopped after repeated errors".
    func retry() {
        guard run != nil else { return }
        run?.failed = []
        run?.outcome = nil
        run?.hasRetried = true
        let isRanked = run?.isRanked == true
        run?.sendsRequests = isRanked
        start()
    }

    /// New or changed items arrived. A run in flight is left alone and reloads when it settles: a refresh must
    /// never cancel the search the user is watching.
    func reload() {
        guard let current = run else { return }
        if current.isRunning { run?.needsReload = true } else { start() }
    }

    /// Read and unread change the title colour and, with Hide Read Items on, what is listed. Applied in place:
    /// marking a row read must not restart a run or drop a row from under the pointer.
    func applyRead(_ read: Bool, ids: Set<Int64>) {
        guard run != nil, !ids.isEmpty else { return }
        for index in run!.items.indices where ids.contains(run!.items[index].id) { run!.items[index].read = read }
        throttle.flush()
    }

    func end() {
        run?.task?.cancel()
        run?.continuation.finish()
        throttle.cancel()
        run = nil
    }

    /// The item behind a selected row, for the preview that sends and fetches nothing.
    func item(_ id: Int64) -> Item? { run?.items.first { $0.id == id } }

    /// The rows the list is showing that are still unread: what ⌘K marks in a pin, whose scope is decided by
    /// judgments rather than by a column.
    func unreadRowIDs() -> [Int64] {
        guard let current = run else { return [] }
        return ListSnapshotMaker.rows(current, context: context).rows.filter { !$0.item.read }.map(\.id)
    }

    /// The sentence a row carries into the reader when it opens.
    var carriedSentence: String? { run?.sentence?.raw }

    /// The best found rows of the settled run, for pre-judging.
    func topFound(_ count: Int) -> [Item] {
        guard let current = run, current.framed != nil else { return [] }
        return ListSnapshotMaker.rows(current, context: context).rows.filter(\.isMarked).prefix(count).map(\.item)
    }

    // MARK: The run

    private func start() {
        run?.task?.cancel()
        epoch += 1
        let epoch = self.epoch
        run?.task = Task { [weak self] in await self?.perform(epoch: epoch) }
    }

    private func perform(epoch: Int) async {
        guard let request = run?.request else { return }
        await loadItems(for: request, epoch: epoch)
        guard isCurrent(epoch), let current = run else { return }

        let sentences = context.rankingSentences(searching: current.sentence)
        let known = await context.cache.answers(textHashes: current.items.map { current.hashes[$0.id] ?? "" },
                                                sentences: sentences, model: context.models.current)
        guard isCurrent(epoch) else { return }
        apply(known, sentences: sentences)

        // A run that is about to send says so before it sends, so it never looks settled for an instant; a run
        // with nothing to send is already settled, and settling publishes it. One settled snapshot per settling
        // is what lets the list act on it: "Check 1,200 older" must widen this run, not the one it replaced.
        let targets = self.targets(missing: sentences, known: known)
        let isRunning = run?.sendsRequests == true && context.canSend && !targets.isEmpty
        run?.isRunning = isRunning
        guard isRunning else { return settle(nil, epoch: epoch) }
        throttle.flush()

        countAfterAStall(epoch: epoch)
        let outcome = await context.itemPass().run(
            targets: targets, sentences: sentences, known: known,
            answered: { [weak self] id, probabilities in self?.answered(id, probabilities, epoch: epoch) },
            failed: { [weak self] id in self?.failed(id, epoch: epoch) })
        guard isCurrent(epoch) else { return }
        settle(outcome, epoch: epoch)
    }

    private func loadItems(for request: ListRequest, epoch: Int) async {
        let scope = Self.itemScope(of: request.scope)
        let limit = loadLimit()
        var items: [Item] = []
        var total = 0
        do {
            items = try await context.database.newestItems(in: scope, limit: limit)
            total = try await context.database.itemCount(in: scope)
        } catch {
            EngineLog.failure("reading the list", error)
        }
        guard isCurrent(epoch), run != nil else { return }
        run!.items = items
        run!.total = total
        run!.hashes = Dictionary(items.map { ($0.id, $0.textHash) }, uniquingKeysWith: { first, _ in first })
        if !run!.hasLoaded {
            run!.hasLoaded = true
            // Hide Read Items hides what was read before the list was asked for, not what is read while reading it.
            if request.hidesRead { run!.keptWhileHidingRead = Set(items.filter { !$0.read }.map(\.id)) }
        }
    }

    /// A ranked run loads only what it can judge (plus what a pin found on earlier days); a chronological one
    /// loads a readable stretch of the newest, and the foot counts the rest.
    private func loadLimit() -> Int {
        guard let current = run else { return Windows.chronological }
        guard current.isRanked else { return Windows.chronological }
        return current.isPin ? max(Windows.pinList, current.judgeWindow) : current.judgeWindow
    }

    private func apply(_ known: [String: [String: Double]], sentences: [FramedSentence]) {
        guard var current = run else { return }
        if let framed = current.framed {
            for item in current.items {
                guard let hash = current.hashes[item.id], let probability = known[hash]?[framed.hash] else { continue }
                current.probabilities[item.id] = probability
            }
        } else if current.request.scope == .all {
            // A plain All Items list puts this week's pin hits first. It reads the cache and sends nothing.
            var hits: Set<Int64> = []
            for item in current.items {
                guard let hash = current.hashes[item.id], let answers = known[hash] else { continue }
                let isFound = sentences.contains { framed in
                    guard let probability = answers[framed.hash] else { return false }
                    return Bands.list(framed.cappedForList(probability)) == .found
                }
                if isFound { hits.insert(item.id) }
            }
            current.pinHits = hits
        }
        run = current
    }

    /// The window, in the order the requests leave: round-robin across sources, so one huge feed cannot hold up
    /// every other source's first row.
    private func targets(missing sentences: [FramedSentence], known: [String: [String: Double]]) -> [JudgeTarget<Int64>] {
        guard let current = run, !sentences.isEmpty else { return [] }
        return Self.roundRobin(Array(current.window))
            .compactMap { item in
                guard let hash = current.hashes[item.id] else { return nil }
                guard sentences.contains(where: { known[hash]?[$0.hash] == nil }) else { return nil }
                return JudgeTarget(id: item.id, textHash: hash, state: item.judgedText)
            }
    }

    static func roundRobin(_ items: [Item]) -> [Item] {
        var bySource: [Int64: [Item]] = [:]
        var order: [Int64] = []
        for item in items {
            if bySource[item.sourceID] == nil { order.append(item.sourceID) }
            bySource[item.sourceID, default: []].append(item)
        }
        var mixed: [Item] = []
        mixed.reserveCapacity(items.count)
        var index = 0
        while mixed.count < items.count {
            for sourceID in order where index < bySource[sourceID]!.count { mixed.append(bySource[sourceID]![index]) }
            index += 1
        }
        return mixed
    }

    // MARK: Answers

    private func answered(_ id: Int64, _ probabilities: [String: Double], epoch: Int) {
        guard isCurrent(epoch), let framed = run?.framed else { return }
        guard let probability = probabilities[framed.hash] else { return failed(id, epoch: epoch) }
        run?.probabilities[id] = probability
        run?.failed.remove(id)
        throttle.touch()
    }

    private func failed(_ id: Int64, epoch: Int) {
        guard isCurrent(epoch) else { return }
        run?.failed.insert(id)
        // A failure is the one thing that makes the foot count: the wait is no longer what it looked like.
        run?.showsProgress = true
        throttle.touch()
    }

    private func settle(_ outcome: JudgePassOutcome?, epoch: Int) {
        guard isCurrent(epoch), let current = run else { return }
        if outcome == .cancelled { return }
        run?.isRunning = false
        run?.outcome = outcome
        if outcome == .keyRejected { context.keyStatus = .rejected }
        throttle.flush()
        if current.needsReload {
            run?.needsReload = false
            return start()
        }
        if let settled = run { onSettled?(settled) }
    }

    /// The foot does not tick while a run behaves. After three seconds it owes the reader a number.
    private func countAfterAStall(epoch: Int) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, self.isCurrent(epoch), self.run?.isRunning == true else { return }
            self.run?.showsProgress = true
            self.throttle.flush()
        }
    }

    // MARK: Publishing

    private func publishNow() {
        guard let current = run else { return }
        current.continuation.yield(ListSnapshotMaker.snapshot(current, context: context))
    }

    private func isCurrent(_ epoch: Int) -> Bool { epoch == self.epoch && run != nil }

    private func pin(of scope: ListScope) -> Pin? {
        guard case let .pin(id) = scope else { return nil }
        return context.pins.first { $0.id == id }
    }

    /// A source click during a search: the same sentence, a narrower scope, nothing sent.
    private func isLocalFilter(_ request: ListRequest) -> Bool {
        if case .source = request.scope { return request.sentence != nil }
        return false
    }

    static func itemScope(of scope: ListScope) -> ItemScope {
        if case let .source(id) = scope { return .source(id) }
        return .all
    }
}
