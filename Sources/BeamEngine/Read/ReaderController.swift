import BeamExtract
import BeamJev
import BeamModels
import BeamStore
import Foundation

/// The reader: open one article, get its text, and light the paragraphs that answer the sentence it carried in.
///
/// Opening marks the item read; arrowing past a row never reaches here. Extraction is cached in the store, so a
/// second open is instant, and so is closing Find by Meaning: the carried sentence's marks come back from memory.
@MainActor
final class ReaderController {
    private let context: EngineContext
    private var run: ReaderRun?
    private var openContinuation: AsyncStream<ReaderSnapshot>.Continuation?
    private var openingTask: Task<Void, Never>?
    private var throttle: SnapshotThrottle!
    private var epoch = 0

    init(context: EngineContext) {
        self.context = context
        throttle = SnapshotThrottle(every: Windows.readerTick) { [weak self] in self?.publishNow() }
    }

    // MARK: What the engine asks of it

    func open(itemID: Int64, carrying sentence: String?) -> AsyncStream<ReaderSnapshot> {
        close()
        let (stream, continuation) = AsyncStream<ReaderSnapshot>.makeStream()
        openContinuation = continuation
        epoch += 1
        let epoch = self.epoch
        openingTask = Task { [weak self] in
            guard let self else { return }
            await self.begin(itemID: itemID, carrying: sentence, continuation: continuation, epoch: epoch)
        }
        return stream
    }

    /// ⌘F. Return re-lights this article only; closing the field restores the carried sentence's marks at once.
    func find(_ sentence: String?) {
        guard run?.phase == .ready else { return }
        let asked = sentence.map(Sentence.init).flatMap { $0.isEmpty ? nil : $0 }
        run?.find = asked
        run?.failed = []
        run?.outcome = nil
        run?.isSaturated = false
        startJudging()
    }

    func setViewport(firstVisible: Int, lastVisible: Int) {
        let first = max(0, firstVisible)
        run?.viewport = first...max(first, lastVisible)
    }

    /// The Retry of "61 of 84 checked". On an article that could not be read it fetches the page again.
    func retry() {
        guard let current = run else { return }
        run?.failed = []
        run?.outcome = nil
        guard current.phase == .ready else { return reopen() }
        startJudging()
    }

    func close() {
        openingTask?.cancel()
        openingTask = nil
        run?.task?.cancel()
        run?.continuation.finish()
        openContinuation?.finish()
        openContinuation = nil
        throttle.cancel()
        run = nil
        epoch += 1
    }

    /// Keep readable text on screen while stopping requests from the previous credential.
    /// A page already loading finishes normally and consults the new key status before it is judged.
    func keyChanged() {
        guard run?.phase == .ready else { return }
        startJudging()
    }

    /// The article the reader is showing, for the engine's own bookkeeping.
    var openItemID: Int64? { run?.itemID }

    // MARK: Opening

    private func begin(itemID: Int64, carrying sentence: String?, continuation: AsyncStream<ReaderSnapshot>.Continuation,
                       epoch: Int) async {
        var item: Item?
        do {
            item = try await context.database.item(id: itemID)
        } catch {
            EngineLog.failure("reading item \(itemID)", error)
        }
        guard epoch == self.epoch else { return }
        guard let item else { return continuation.finish() }

        let carried = sentence.map(Sentence.init).flatMap { $0.isEmpty ? nil : $0 }
        var opened = ReaderRun(itemID: itemID, continuation: continuation, item: item,
                               sourceTitle: context.sourceTitle(item.sourceID), sourceKind: context.sourceKind(item.sourceID))
        opened.carried = carried
        run = opened
        openContinuation = nil
        throttle.flush()
        sayItIsLoadingIfItIsSlow(epoch: epoch)

        if let carried { await checkWhetherTheTitleMatched(item: item, sentence: carried, epoch: epoch) }
        await loadArticle(item: item, epoch: epoch, force: false)
    }

    /// "Getting the article" is worth saying only after a full second of waiting, and nothing else is said before it.
    private func sayItIsLoadingIfItIsSlow(epoch: Int) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, epoch == self.epoch, self.run?.phase == .loading else { return }
            self.run?.isSlowToLoad = true
            self.throttle.flush()
        }
    }

    /// Reopens the same article from scratch: Retry on "Beam couldn't get the article text."
    private func reopen() {
        guard let current = run else { return }
        openingTask?.cancel()
        openingTask = nil
        run?.task?.cancel()
        let itemID = current.itemID
        let item = current.item
        epoch += 1
        let epoch = self.epoch
        run?.phase = .loading
        run?.passages = []
        run?.answers = [:]
        throttle.flush()
        sayItIsLoadingIfItIsSlow(epoch: epoch)
        run?.task = Task { [weak self] in
            try? await self?.context.database.removeArticle(itemID: itemID)
            await self?.loadArticle(item: item, epoch: epoch, force: true)
        }
    }

    /// "Matched by title." is only said when the row itself was found on its title and the article holds nothing.
    private func checkWhetherTheTitleMatched(item: Item, sentence: Sentence, epoch: Int) async {
        let known = await context.cache.answers(textHashes: [item.textHash], sentences: [.item(sentence)],
                                                model: context.models.current)
        guard epoch == self.epoch else { return }
        let framed = FramedSentence.item(sentence)
        guard let probability = known[item.textHash]?[framed.hash] else { return }
        run?.matchedByTitle = Bands.list(framed.cappedForList(probability)) == .found
    }

    private func loadArticle(item: Item, epoch: Int, force: Bool) async {
        let content = await ArticleStore(context: context).article(for: item, force: force)
        guard epoch == self.epoch, run != nil else { return }
        switch content {
        case let .ready(passages, images, tables):
            run!.phase = .ready
            run!.passages = passages
            run!.images = images
            run!.tables = tables
            run!.hashes = Dictionary(passages.indices.filter { passages[$0].isJudgeable }.map { ($0, passages[$0].textHash) },
                                     uniquingKeysWith: { first, _ in first })
            // Said before the article is published, so the first snapshot of a carried sentence never claims the
            // article is settled a moment before its paragraphs are judged.
            run!.isRunning = run!.sentence != nil
            throttle.flush()
            startJudging()
        case .unavailable:
            run!.phase = .unavailable
            throttle.flush()
        case .external:
            run!.phase = .external
            throttle.flush()
        }
    }

    // MARK: Judging

    private func startJudging() {
        run?.task?.cancel()
        // Said now rather than when the task starts, so no snapshot can escape saying the article is settled
        // while it is about to be judged.
        let hasSentence = run?.sentence != nil
        run?.isRunning = hasSentence
        epoch += 1
        let epoch = self.epoch
        run?.task = Task { [weak self] in await self?.judgePassages(epoch: epoch) }
    }

    private func judgePassages(epoch: Int) async {
        guard let current = run, current.phase == .ready, let sentence = current.sentence else { return }
        let framed = FramedSentence.passage(sentence)
        let judgeable = current.judgeable
        guard !judgeable.isEmpty else { return settle(nil, epoch: epoch) }

        let known = await context.cache.answers(textHashes: judgeable.compactMap { current.hashes[$0] },
                                                sentences: [framed], model: context.models.current)
        guard epoch == self.epoch, run != nil else { return }
        var answers = run!.answers[framed.hash] ?? [:]
        for index in judgeable {
            guard let hash = run!.hashes[index], let probability = known[hash]?[framed.hash] else { continue }
            answers[index] = probability
        }
        run!.answers[framed.hash] = answers

        // One publication once it is known whether anything is running. A sentence answered entirely from the
        // cache is published by `settle` alone: flushing here as well would put a second, identical snapshot in
        // front of that one, and whoever acts on the first acts a snapshot early — ⌘F pressed there would be
        // answered by the marks it was meant to replace.
        var pending = judgeable.filter { answers[$0] == nil }
        let isRunning = !pending.isEmpty && context.canSend
        run!.isRunning = isRunning
        guard isRunning else { return settle(nil, epoch: epoch) }
        throttle.flush()

        // One chunk at a time, re-ordered by what is on screen each time: the viewport keeps its priority even
        // when the reader scrolls while the article is still being judged.
        var outcome = JudgePassOutcome.completed
        let pass = context.passagePass(for: .reading)
        while !pending.isEmpty {
            let chunk = Array(viewportFirst(pending).prefix(context.maxInFlight))
            let result = await pass.run(
                targets: targets(chunk, framed: framed), sentences: [framed], known: [:],
                answered: { [weak self] index, probabilities in self?.answered(index, probabilities, framed: framed, epoch: epoch) },
                failed: { [weak self] index in self?.failed(index, epoch: epoch) })
            guard epoch == self.epoch else { return }
            let done = Set(chunk)
            pending.removeAll { done.contains($0) }
            guard result == .completed else {
                outcome = result
                break
            }
        }
        settle(outcome == .completed ? nil : outcome, epoch: epoch)
    }

    private func targets(_ indices: [Int], framed: FramedSentence) -> [JudgeTarget<Int>] {
        guard let current = run else { return [] }
        return indices.compactMap { index in
            guard let hash = current.hashes[index], current.passages.indices.contains(index) else { return nil }
            return JudgeTarget(id: index, textHash: hash, state: current.passages[index].judgedText)
        }
    }

    private func viewportFirst(_ indices: [Int]) -> [Int] {
        guard let viewport = run?.viewport else { return indices }
        return indices.filter { viewport.contains($0) } + indices.filter { !viewport.contains($0) }
    }

    private func answered(_ index: Int, _ probabilities: [String: Double], framed: FramedSentence, epoch: Int) {
        guard epoch == self.epoch, run != nil else { return }
        guard let probability = probabilities[framed.hash] else { return failed(index, epoch: epoch) }
        run!.answers[framed.hash, default: [:]][index] = probability
        run!.failed.remove(index)
        throttle.touch()
    }

    private func failed(_ index: Int, epoch: Int) {
        guard epoch == self.epoch else { return }
        run?.failed.insert(index)
        throttle.touch()
    }

    private func settle(_ outcome: JudgePassOutcome?, epoch: Int) {
        guard epoch == self.epoch, run != nil else { return }
        if outcome == .cancelled { return }
        run!.isRunning = false
        run!.outcome = outcome
        if outcome == .keyRejected { context.keyStatus = .rejected }
        throttle.flush()
    }

    private func publishNow() {
        guard let current = run else { return }
        let made = ReaderSnapshotMaker.snapshot(current, context: context)
        run?.isSaturated = made.isSaturated
        current.continuation.yield(made.snapshot)
    }
}
