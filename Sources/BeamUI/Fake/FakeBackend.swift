import BeamModels
import Foundation

/// A complete `BeamBackend` over a captured session (`FakeData`), so the whole interface can be built, reviewed and
/// screenshotted with no network, no key and no engine. It keeps the engine's promises that the views rely on:
/// list snapshots about every 200 ms over a 1.5 s run, reader judgments viewport-first on a 100 ms tick over about 2 s,
/// "not checked" never shown as "nothing", and the exact sentences of DESIGN.md section 6.
///
/// Two sentences are real: the one the list was captured with lights twelve paragraphs of the long article, and
/// "large language models" saturates it. Any other sentence is scored by `FakeJudge`, which is plausible, not right.
///
/// In Settings or the key sheet, a key starting with "reject" is rejected and one starting with "offline" is unreachable,
/// so both status lines can be seen; any other text is accepted.
@MainActor
public final class FakeBackend: BeamBackend {
    struct UndoEntry { let title: String; let restore: () -> Void }

    let scenario: FakeScenario
    let library: FakeLibrary
    var sources: [Source]
    var items: [Item]
    var pins: [Pin] = []
    var status: KeyStatus
    var spent = 0.04
    /// Judged items by normalised sentence: the fake's judgment cache.
    var itemChecks: [String: [Int64: Double]] = [:]
    var passageChecks: [PassageKey: [Int: Double]] = [:]
    var undoStack: [UndoEntry] = []
    var sidebarContinuation: AsyncStream<SidebarSnapshot>.Continuation?
    var listRun: ListRun?
    var listEpoch = 0
    var readerRun: ReaderRun?
    var readerEpoch = 0
    /// Items the staged cold start has not delivered yet.
    var undelivered: [Item] = []
    private var nextID: Int64 = 1_000

    public var prejudgesTopResults = false
    public var undoTitle: String? { undoStack.last?.title }

    public init(options: FakeOptions = FakeOptions()) throws {
        let library = try FakeLibrary.load()
        self.library = library
        scenario = options.scenario
        status = options.keyStatus
        sources = library.sources
        items = library.items
        itemChecks[library.listSentence] = library.listChecks

        let now = Date()
        let pinned: [(String, TimeInterval?)] = [(library.listSentence, 12 * 3_600), ("game modding", 2 * 86_400),
                                                 ("trucs sur la vie privée et la surveillance", nil)]
        for (position, (sentence, sinceViewed)) in pinned.enumerated() {
            pins.append(Pin(id: newID(), sentence: sentence, position: position, created: now.addingTimeInterval(-30 * 86_400),
                            lastViewed: sinceViewed.map { now.addingTimeInterval(-$0) }))
            judgeEverything(about: sentence)
        }
        if scenario == .coldStart { deliverItemsLate() }
    }

    func newID() -> Int64 { nextID += 1; return nextID }

    // MARK: Key, privacy, spend

    public func keyStatus() async -> KeyStatus { status }

    public func setKey(_ key: String?) async -> KeyStatus {
        let trimmed = (key ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            status = .missing
        } else {
            try? await Task.sleep(for: .milliseconds(600))          // long enough to read "Checking…"
            status = trimmed.lowercased().hasPrefix("reject") ? .rejected : (trimmed.lowercased().hasPrefix("offline") ? .unreachable : .valid)
        }
        publishList()
        return status
    }

    public func dollarsToday() async -> Double { spent }

    // MARK: Judging

    /// The probability for one item, from the capture when the sentence is the captured one.
    func probability(of item: Item, about sentence: String) -> Double {
        if sentence == library.listSentence, let captured = library.listChecks[item.id] { return captured }
        let p = FakeJudge.probability(of: item.title + " " + item.snippet, about: sentence)
        // Exclusions, amounts and dates are capped at unsure: the judge is literal and cannot weigh them.
        return FakeJudge.asksForExclusionAmountOrDate(sentence) ? min(p, Bands.listFound - 0.01) : p
    }

    /// Pins stay current in the background, so a pin's list is always fully checked.
    func judgeEverything(about sentence: String) {
        let key = FakeJudge.normalise(sentence)
        var checks = itemChecks[key] ?? [:]
        for item in items + undelivered where checks[item.id] == nil { checks[item.id] = probability(of: item, about: key) }
        itemChecks[key] = checks
    }

    // MARK: Undo and refresh

    public func undo() async -> String? {
        guard let entry = undoStack.popLast() else { return nil }
        entry.restore()
        publishEverything()
        return entry.title
    }

    public func refresh() async {
        try? await Task.sleep(for: .milliseconds(600))
        for index in sources.indices { sources[index].lastError = nil; sources[index].failingSince = nil; sources[index].lastFetch = Date() }
        publishSidebar()
        retryList()
        retryReader()
    }

    func publishEverything() { publishSidebar(); publishList() }

    /// Releases the library a source at a time from 2.5 s, so "Getting your sources" and the first rows can be watched.
    private func deliverItemsLate() {
        undelivered = items
        items = []
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(2_500))
            while let self, let sourceID = self.undelivered.first?.sourceID {
                self.items = (self.items + self.undelivered.filter { $0.sourceID == sourceID }).sorted { $0.sortDate > $1.sortDate }
                self.undelivered.removeAll { $0.sourceID == sourceID }
                self.publishEverything()
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
    }
}
