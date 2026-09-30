import BeamModels
import Foundation

/// Turns a run into the one immutable thing the list draws. Pure: given the same run it says the same thing,
/// which is what lets `beam-eval` check the order, the bands and the exact copy.
@MainActor
enum ListSnapshotMaker {
    static func snapshot(_ run: ListRun, context: EngineContext) -> ListSnapshot {
        var snapshot = ListSnapshot(request: run.request, isRunning: run.isRunning)
        let listing = rows(run, context: context)
        snapshot.rows = listing.rows
        snapshot.lastNewRowID = listing.lastNewRowID
        snapshot.foot = foot(run, context: context, rowCount: listing.rows.count)
        if listing.rows.isEmpty {
            let empty = emptiness(run, context: context)
            snapshot.emptyMessage = empty.0
            snapshot.emptyAction = empty.1
        }
        return snapshot
    }

    // MARK: Rows

    /// Searches: everything at p >= 0.45, by probability rounded to 0.05, then date; the 4 × 12 pt mark at p >= 0.60.
    /// Pins: found rows by date alone, unmarked, with the separator under the last one new since the pin was viewed.
    /// No sentence: by date, and in All Items this week's pin hits come first, marked.
    static func rows(_ run: ListRun, context: EngineContext) -> (rows: [Row], lastNewRowID: Int64?) {
        guard let framed = run.framed else { return (chronological(run, context: context), nil) }

        let banded = run.items.compactMap { item -> (item: Item, probability: Double)? in
            guard let raw = run.probabilities[item.id] else { return nil }
            return (item, framed.cappedForList(raw))
        }
        if let pin = run.pin {
            let found = banded.filter { Bands.list($0.probability) == .found }.sorted { $0.item.sortDate > $1.item.sortDate }
            let rows = found.map { row($0.item, context: context, check: .judged($0.probability), marked: false) }
            // The rows are newest first, so the last one that is new is the oldest arrival since the pin was viewed.
            let lastNew = found.last { $0.item.sortDate > (pin.lastViewed ?? .distantPast) }?.item.id
            return (rows, lastNew)
        }
        let listed = banded
            .filter { $0.probability >= Bands.listUnsure }
            .sorted { a, b in
                let (left, right) = (rounded(a.probability), rounded(b.probability))
                return left != right ? left > right : a.item.sortDate > b.item.sortDate
            }
        return (listed.map { row($0.item, context: context, check: .judged($0.probability),
                               marked: Bands.list($0.probability) == .found) }, nil)
    }

    /// Probabilities are rounded to 0.05 before they order anything: 0.71 and 0.68 are the same answer, and the
    /// newer of the two should win.
    private static func rounded(_ probability: Double) -> Double { (probability * 20).rounded() }

    private static func chronological(_ run: ListRun, context: EngineContext) -> [Row] {
        var shown = run.items
        if run.request.hidesRead { shown.removeAll { $0.read && !run.keptWhileHidingRead.contains($0.id) } }
        guard run.request.scope == .all, !run.pinHits.isEmpty else { return shown.map { row($0, context: context) } }
        // "All Items with pin hits first is the morning": this week's hits, marked, then everything else by date.
        let thisWeek = context.now().addingTimeInterval(-7 * 86_400)
        let isHit: (Item) -> Bool = { run.pinHits.contains($0.id) && $0.sortDate > thisWeek }
        return shown.filter(isHit).map { row($0, context: context, marked: true) }
             + shown.filter { !isHit($0) }.map { row($0, context: context) }
    }

    private static func row(_ item: Item, context: EngineContext, check: Check? = nil, marked: Bool = false) -> Row {
        Row(item: item, sourceTitle: context.sourceTitle(item.sourceID), check: check, isMarked: marked)
    }

    // MARK: Foot

    /// One message at a time, in the priority order of DESIGN.md section 4.
    static func foot(_ run: ListRun, context: EngineContext, rowCount: Int) -> Foot {
        guard !context.sources.isEmpty else { return .blank }

        if run.isRanked {
            switch context.keyStatus {
            case .missing: return Feet.addKey
            case .rejected: return Feet.keyRejected
            case .storageError: return Feet.keyStorageError
            case .valid, .unreachable: break
            }
            switch run.outcome {
            case .dailyLimit: return Feet.dailyLimit
            case .offline: return Feet.offline
            case .stopped: return Feet.stopped
            default: break
            }
            if !run.isRunning, run.notChecked > 0 { return Feet.notChecked(run.notChecked) }
        }
        if case let .source(id) = run.request.scope, let source = context.source(id), let error = source.lastError {
            return Feet.couldNotRefresh(error)
        }
        guard run.isRanked else {
            if case let .source(id) = run.request.scope { return Feet.items(rowCount, in: context.sourceTitle(id)) }
            return Feet.items(rowCount)
        }
        if let note = run.sentence?.unjudgeable { return Foot(note) }

        let covered = min(run.judgeWindow, run.items.count)
        if run.isRunning { return run.showsProgress ? Feet.progress(run.checked, of: covered) : Feet.checking(covered) }
        if covered < run.total { return Feet.newest(covered, of: run.total, older: min(Windows.older, run.total - covered)) }
        return Feet.checked(run.checked)
    }

    // MARK: Empty

    /// The one centred line of an empty list, and the single text button it may carry.
    static func emptiness(_ run: ListRun, context: EngineContext) -> (String?, FootAction?) {
        if context.sources.isEmpty { return (Feet.noSources, .addSource) }
        if context.isRefreshing, run.items.isEmpty { return (Feet.gettingSources, nil) }
        guard run.isRanked else { return (run.items.isEmpty ? Feet.noItems : nil, nil) }
        // "Nothing found" is only ever said about what was actually checked, and only once the run has settled.
        guard !run.isRunning, context.canSend, run.outcome == nil || run.outcome == .completed else { return (nil, nil) }
        return (Feet.nothingFound(inItems: run.checked), nil)
    }
}
