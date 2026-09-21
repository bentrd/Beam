import BeamModels
import BeamUI
import Observation
import SwiftUI

/// A stand-in for the backend: one captured article, with judgments that arrive over two seconds, viewport first.
@MainActor @Observable
final class DemoModel {
    let options: DemoOptions
    let controller = ReaderController()
    private(set) var snapshot: ReaderSnapshot?
    var textSize: CGFloat

    private let fixture: ReaderFixture
    private let judge: DemoJudge
    private var run: Task<Void, Never>?
    private var viewport = 0...14
    private var question: String?
    private var checks: [Int: Check] = [:]
    private var isSaturated = false
    private var failsSomeJudgments: Bool

    /// Forty beats of 50 ms: faster than the reader's own 100 ms beat, so the reader's pacing is what shows.
    private static let beats = 40
    private static let beat = Duration.milliseconds(50)

    init(options: DemoOptions) throws {
        self.options = options
        textSize = options.textSize.map { size in
            ReaderTextSize.steps.min { abs($0 - size) < abs($1 - size) } ?? ReaderTextSize.standard
        } ?? ReaderTextSize.standard
        let lit = try ReaderFixture.load(.lit)
        let saturated = try ReaderFixture.load(.saturated)
        fixture = options.scene == .saturated ? saturated : lit
        judge = DemoJudge(fixtures: [lit, saturated])
        failsSomeJudgments = options.scene == .unchecked
        switch options.scene {
        case .lit, .saturated, .unchecked: open()
        case .loading: startLoading()
        case .unavailable: snapshot = base(.unavailable)
        case .preview: snapshot = base(.preview, foot: DemoFeet.returnToRead)
        }
    }

    var actions: ReaderActions {
        ReaderActions(find: { [weak self] in self?.find($0) },
                      viewportChanged: { [weak self] first, last in self?.viewport = first...max(first, last) },
                      footAction: { [weak self] in if $0 == .retry { self?.retry() } },
                      openOriginal: { [fixture] in if let url = fixture.item.url { NSWorkspace.shared.open(url) } })
    }

    var isPreview: Bool { snapshot?.phase == .preview }

    /// Return on a previewed row: a slow load (long enough to see "Getting the article"), then the article.
    func openPreviewed() {
        guard isPreview else { return }
        startLoading(arrivingIn: .milliseconds(1600))
    }

    /// The title and byline are there at once; a load that takes more than a second says so, and a quicker one
    /// says nothing. Without an arrival the article never comes, which is the `loading` scene.
    private func startLoading(arrivingIn arrival: Duration? = nil) {
        snapshot = base(.loading)
        run = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, self?.snapshot?.phase == .loading else { return }
            self?.snapshot = self?.base(.loading, foot: DemoFeet.gettingArticle)
            guard let arrival else { return }
            try? await Task.sleep(for: arrival - .seconds(1))
            if !Task.isCancelled { self?.open() }
        }
    }

    // MARK: The run

    private var sentence: String { question ?? fixture.sentence }
    private var judgeable: [Int] { fixture.passages.indices.filter { fixture.passages[$0].isJudgeable } }

    private func open() {
        question = nil
        startRun(over: judgeable)
    }

    /// What Return in the ask field does; also scripted by `-ask`.
    func ask(_ question: String) { find(question) }

    private func find(_ question: String?) {
        guard snapshot?.phase == .ready else { return }
        self.question = question
        if question == nil {
            // The carried sentence was judged already: its marks come back from the cache at once.
            run?.cancel()
            isSaturated = false
            checks = Dictionary(uniqueKeysWithValues: judgeable.map { ($0, Check.judged(probability(at: $0))) })
            publish(isRunning: false)
        } else {
            startRun(over: judgeable)
        }
    }

    private func retry() {
        failsSomeJudgments = false
        startRun(over: judgeable.filter { !(checks[$0]?.isChecked ?? false) }, keepingChecks: true)
    }

    private func startRun(over waiting: [Int], keepingChecks: Bool = false) {
        run?.cancel()
        if !keepingChecks {
            checks = [:]
            isSaturated = false
        }
        for index in waiting { checks[index] = .pending }
        publish(isRunning: true)
        run = Task { [weak self] in await self?.judge(waiting) }
    }

    private func judge(_ waiting: [Int]) async {
        var waiting = waiting
        let size = max((waiting.count + Self.beats - 1) / Self.beats, 1)
        while !waiting.isEmpty {
            try? await Task.sleep(for: Self.beat)
            guard !Task.isCancelled else { return }
            // Viewport first: what is on screen is answered before the rest of the article.
            let next = Array((waiting.filter(viewport.contains) + waiting.filter { !viewport.contains($0) }).prefix(size))
            waiting.removeAll(where: next.contains)
            for index in next {
                checks[index] = failsSomeJudgments && index % 7 == 3 ? .failed : .judged(probability(at: index))
            }
            publish(isRunning: !waiting.isEmpty)
        }
    }

    private func probability(at index: Int) -> Double {
        judge.probability(of: fixture.passages[index], at: index, about: sentence)
    }

    // MARK: Snapshots

    private func base(_ phase: ReaderPhase, foot: Foot = .blank) -> ReaderSnapshot {
        ReaderSnapshot(item: fixture.item, sourceTitle: fixture.sourceTitle, phase: phase, foot: foot)
    }

    private func publish(isRunning: Bool) {
        let judged = checks.compactMapValues(\.probability)
        let found = judged.values.filter { Bands.passage($0) == .found }.count
        let unsure = judged.values.filter { Bands.passage($0) == .unsure }.count
        let isDecidable = judged.count >= min(Bands.saturationMinimumChecked, judgeable.count)
        let isOver = isDecidable && Double(found) / Double(max(judged.count, 1)) > Bands.saturationShare
        // Sticky while the run lasts; decided for good when it settles.
        isSaturated = isRunning ? (isSaturated || isOver) : isOver

        var snapshot = base(.ready)
        snapshot.passages = fixture.passages
        snapshot.checks = checks
        snapshot.omittedImages = fixture.omittedImages
        snapshot.sentence = sentence
        snapshot.isFindActive = question != nil
        snapshot.isSaturated = isSaturated
        snapshot.isRunning = isRunning
        if !isSaturated {
            snapshot.hits = judgeable.filter { judged[$0].map { Bands.passage($0) != .nothing } ?? false }
        }
        snapshot.foot = isRunning
            ? DemoFeet.checking(judgeable.count)
            : DemoFeet.settled(found: found, unsure: unsure, checked: judged.count, judgeable: judgeable.count, saturated: isSaturated,
                               hasCode: fixture.passages.contains { $0.kind == .code })
        self.snapshot = snapshot
    }
}
