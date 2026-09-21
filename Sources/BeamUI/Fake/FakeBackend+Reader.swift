import BeamModels
import Foundation

/// Passage judgments are cached per article and sentence, so Find by Meaning can hand the carried marks back at once.
struct PassageKey: Hashable {
    let itemID: Int64
    let sentence: String
}

/// One `open(itemID:carrying:)` call.
struct ReaderRun {
    let itemID: Int64
    let continuation: AsyncStream<ReaderSnapshot>.Continuation
    var task: Task<Void, Never>?
    var phase = ReaderPhase.loading
    var passages: [Passage] = []
    var omittedImages = 0
    /// As typed. `find` wins while Find by Meaning is active.
    var carried: String?
    var find: String?
    var matchedByTitle = false
    /// Until the reader reports what is on screen, assume the top of the article.
    var viewport = 0...14
    var isRunning = false
    var isSaturated = false
    var failed: Set<Int> = []
    var hasRetried = false
    var reachedDailyLimit = false

    var sentence: String? { find ?? carried }
    var judgeable: [Int] { passages.indices.filter { passages[$0].isJudgeable } }
}

extension FakeBackend {
    private static let readerTicks = 20
    private static let readerTick = Duration.milliseconds(100)

    // MARK: BeamBackend

    public func preview(itemID: Int64) -> ReaderSnapshot? {
        guard let item = items.first(where: { $0.id == itemID }) else { return nil }
        let opensInBrowser = content(for: item) == .external
        return ReaderSnapshot(item: item, sourceTitle: sourceTitle(of: item), phase: .preview,
                              foot: opensInBrowser ? FakeFeet.returnToOpenInBrowser : FakeFeet.returnToRead)
    }

    public func open(itemID: Int64, carrying sentence: String?) -> AsyncStream<ReaderSnapshot> {
        closeReader()
        let (stream, continuation) = AsyncStream<ReaderSnapshot>.makeStream()
        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            continuation.finish()
            return stream
        }
        items[index].read = true
        items[index].opened = Date()
        publishEverything()

        var run = ReaderRun(itemID: itemID, continuation: continuation)
        run.carried = sentence.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        run.matchedByTitle = run.carried.map { (itemChecks[FakeJudge.normalise($0)]?[itemID] ?? 0) >= Bands.listFound } ?? false
        readerRun = run
        publishReader()

        let epoch = readerEpoch
        readerRun?.task = Task { [weak self] in
            guard let self, await self.pauseReader(.milliseconds(250), epoch: epoch),                     // fetch and extract
                  let item = self.items.first(where: { $0.id == itemID }) else { return }
            self.load(self.content(for: item))
        }
        return stream
    }

    public func find(_ sentence: String?) {
        guard readerRun?.phase == .ready else { return }
        readerRun?.find = sentence.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        readerRun?.failed = []
        readerRun?.isSaturated = false
        startReaderRun()
    }

    public func setViewport(firstVisible: Int, lastVisible: Int) {
        readerRun?.viewport = firstVisible...max(firstVisible, lastVisible)
    }

    public func retryReader() {
        guard readerRun?.phase == .ready, readerRun?.failed.isEmpty == false else { return }
        readerRun?.failed = []
        readerRun?.hasRetried = true
        startReaderRun()
    }

    public func closeReader() {
        readerRun?.task?.cancel()
        readerRun?.continuation.finish()
        readerRun = nil
        readerEpoch += 1
    }

    // MARK: Content

    /// Only one article was captured in full. Rows with a real snippet open as that snippet (what arXiv falls back to);
    /// links to YouTube open in the browser; the rest have no text here and show the failed state.
    func content(for item: Item) -> ArticleContent {
        if item.id == library.article.itemID {
            return .ready(passages: library.article.passages, images: library.article.omittedImages, tables: 0)
        }
        let kind = sources.first { $0.id == item.sourceID }?.kind
        if kind == .youtube || item.url?.host?.contains("youtube.com") == true { return .external }
        if item.snippet.count >= 120 { return .ready(passages: [Passage(kind: .paragraph, text: item.snippet)], images: 0, tables: 0) }
        return .unavailable(reason: "Only the title and the domain were captured for this item.")
    }

    private func sourceTitle(of item: Item) -> String { sources.first { $0.id == item.sourceID }?.title ?? "" }

    private func load(_ content: ArticleContent) {
        switch content {
        case .ready(let passages, let images, _):
            readerRun?.phase = .ready
            readerRun?.passages = passages
            readerRun?.omittedImages = images
            startReaderRun()
        case .unavailable: readerRun?.phase = .unavailable; publishReader()
        case .external: readerRun?.phase = .external; publishReader()
        }
    }

    // MARK: The run

    private func startReaderRun() {
        readerRun?.task?.cancel()
        readerEpoch += 1
        let epoch = readerEpoch
        guard let run = readerRun, let sentence = run.sentence, status == .valid, scenario != .offline else {
            readerRun?.isRunning = false
            return publishReader()
        }
        let key = PassageKey(itemID: run.itemID, sentence: FakeJudge.normalise(sentence))
        let waiting = run.judgeable.filter { passageChecks[key]?[$0] == nil }
        guard !waiting.isEmpty else {
            readerRun?.isRunning = false
            return publishReader()
        }
        readerRun?.isRunning = true
        publishReader()
        readerRun?.task = Task { [weak self] in await self?.judge(passages: waiting, key: key, epoch: epoch) }
    }

    private func judge(passages waiting: [Int], key: PassageKey, epoch: Int) async {
        var waiting = waiting
        let size = max((waiting.count + Self.readerTicks - 1) / Self.readerTicks, 1)
        let stopAt = scenario == .limit ? waiting.count * 2 / 3 : 0

        while !waiting.isEmpty {
            guard await pauseReader(Self.readerTick, epoch: epoch), let run = readerRun else { return }
            if scenario == .limit, waiting.count <= stopAt {
                readerRun?.reachedDailyLimit = true
                break
            }
            // Viewport first: what is on screen is answered before the rest of the article.
            let next = Array((waiting.filter(run.viewport.contains) + waiting.filter { !run.viewport.contains($0) }).prefix(size))
            waiting.removeAll(where: next.contains)
            for index in next {
                if scenario == .failures, !run.hasRetried, index % 7 == 3 {
                    readerRun?.failed.insert(index)
                } else {
                    passageChecks[key, default: [:]][index] = probability(ofPassage: index, in: run, key: key)
                    spent += 0.000_015
                }
            }
            publishReader()
        }
        readerRun?.isRunning = false
        publishReader()
    }

    private func probability(ofPassage index: Int, in run: ReaderRun, key: PassageKey) -> Double {
        if run.itemID == library.article.itemID, let captured = library.article.checks[key.sentence]?[index] { return captured }
        return FakeJudge.probability(of: run.passages[index].text, about: key.sentence)
    }

    private func pauseReader(_ duration: Duration, epoch: Int) async -> Bool {
        do { try await Task.sleep(for: duration) } catch { return false }
        return epoch == readerEpoch
    }

    // MARK: Snapshots

    func publishReader() {
        guard var run = readerRun, let item = items.first(where: { $0.id == run.itemID }) else { return }
        var snapshot = ReaderSnapshot(item: item, sourceTitle: sourceTitle(of: item), phase: run.phase, passages: run.passages,
                                      omittedImages: run.omittedImages, sentence: run.sentence, isFindActive: run.find != nil,
                                      isRunning: run.isRunning)
        if run.phase == .external { snapshot.foot = FakeFeet.returnToOpenInBrowser }
        guard run.phase == .ready else {
            run.continuation.yield(snapshot)
            return
        }

        let judgeable = run.judgeable
        let judged = run.sentence.flatMap { passageChecks[PassageKey(itemID: run.itemID, sentence: FakeJudge.normalise($0))] } ?? [:]
        // No marks before 24 paragraphs are checked (or all of them): saturation cannot be told from fewer.
        let isRevealed = judged.count >= min(Bands.saturationMinimumChecked, judgeable.count)
        if run.sentence != nil {
            for index in judgeable {
                if isRevealed, let p = judged[index] { snapshot.checks[index] = .judged(p) }
                else { snapshot.checks[index] = run.failed.contains(index) && !run.isRunning ? .failed : .pending }
            }
        }
        let found = judged.values.filter { Bands.passage($0) == .found }.count
        let unsure = judged.values.filter { Bands.passage($0) == .unsure }.count
        let isOverThreshold = isRevealed && !judged.isEmpty && Double(found) / Double(judged.count) > Bands.saturationShare
        // Sticky while the run lasts; decided for good when it settles.
        run.isSaturated = run.isRunning ? (run.isSaturated || isOverThreshold) : isOverThreshold
        readerRun?.isSaturated = run.isSaturated

        snapshot.isSaturated = run.isSaturated
        if isRevealed, !run.isSaturated {
            snapshot.hits = judgeable.filter { judged[$0].map { Bands.passage($0) != .nothing } ?? false }
        }
        snapshot.foot = readerFoot(run, judgeable: judgeable.count, checked: judged.count, found: found, unsure: unsure)
        run.continuation.yield(snapshot)
    }

    private func readerFoot(_ run: ReaderRun, judgeable: Int, checked: Int, found: Int, unsure: Int) -> Foot {
        let hasCode = run.passages.contains { $0.kind == .code }
        guard run.sentence != nil, judgeable > 0 else { return hasCode && judgeable == 0 ? Foot(FakeFeet.codeNotChecked) : .blank }
        let isAsking = run.find != nil

        if run.isRunning {
            if isAsking { return FakeFeet.askChecking }
            return run.failed.isEmpty ? FakeFeet.checkingParagraphs(judgeable) : FakeFeet.paragraphProgress(checked, of: judgeable, retry: false)
        }
        if run.reachedDailyLimit { return FakeFeet.dailyLimit }
        if status != .valid { return status == .rejected ? FakeFeet.keyRejected : (status == .missing ? FakeFeet.addKey : FakeFeet.offline) }
        if scenario == .offline, checked < judgeable { return FakeFeet.offline }
        if checked < judgeable { return FakeFeet.paragraphProgress(checked, of: judgeable, retry: true) }
        if run.isSaturated { return isAsking ? FakeFeet.askSaturated(found: found, of: checked) : FakeFeet.saturated(found: found, of: checked) }

        if found + unsure == 0, isAsking { return FakeFeet.askNothingFound(in: checked) }
        let sentence = found + unsure == 0 ? FakeFeet.nothingFound(inParagraphs: checked, matchedByTitle: run.matchedByTitle)
                                           : FakeFeet.found(found, unsure: unsure)
        return Foot(hasCode ? sentence + ". " + FakeFeet.codeNotChecked : sentence)
    }
}
