import BeamJev
import BeamModels
import Foundation

/// One call of `list(_:)`: what was asked for, what has been loaded, and how far the run has got.
///
/// A run is replaced, never edited: a new sentence, scope or Hide Read Items ends this one and starts another.
struct ListRun {
    let request: ListRequest
    let continuation: AsyncStream<ListSnapshot>.Continuation
    /// The sentence being ranked by: what was typed, or the selected pin's own.
    let sentence: Sentence?
    let framed: FramedSentence?
    /// Whether this run may send anything. A list with no sentence sends nothing, and neither does clicking a
    /// source during a search: that filters what is already checked, locally and in the same order (DESIGN.md section 4).
    var sendsRequests: Bool
    let pin: Pin?

    /// The items the run can show, newest first.
    var items: [Item] = []
    /// `Item.textHash` by item id, computed once: hashing 2,000 items on every snapshot would be felt.
    var hashes: [Int64: String] = [:]
    /// Every item the scope holds, which is what "of 6,200" counts.
    var total = 0
    /// Raw probabilities of the active sentence, by item id. Raw, because the cache stores raw; bands see the capped value.
    var probabilities: [Int64: Double] = [:]
    /// Items of the window that came back with nothing usable.
    var failed: Set<Int64> = []
    /// Pin hits of a plain All Items list: item ids found by any pin, from the cache alone.
    var pinHits: Set<Int64> = []
    /// How many of the newest items this run judges. "Check 1,200 older" widens it.
    var judgeWindow: Int
    var isRunning = false
    var outcome: JudgePassOutcome?
    /// The foot does not tick. A count appears only after a 3 s stall or a failure (DESIGN.md section 5).
    var showsProgress = false
    /// Hide Read Items: rows that were unread when the list was asked for stay until it is asked for again,
    /// so opening a row never pulls it from under the pointer.
    var keptWhileHidingRead: Set<Int64> = []
    var hasRetried = false
    /// The first load captures what was unread; later loads must not move that line.
    var hasLoaded = false
    /// Set while a run is in flight and the library changed under it.
    var needsReload = false
    var task: Task<Void, Never>?

    var isPin: Bool { pin != nil }
    /// A ranked run is one that orders by meaning: a search, or a pin.
    var isRanked: Bool { sentence != nil }

    /// The items this run judges, newest first.
    var window: ArraySlice<Item> { items.prefix(judgeWindow) }

    /// How many of the window have an answer for the active sentence.
    var checked: Int { window.reduce(0) { $0 + (probabilities[$1.id] == nil ? 0 : 1) } }
    var notChecked: Int { min(judgeWindow, items.count) - checked }
}
