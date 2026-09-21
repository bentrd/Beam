import BeamModels
import Foundation

/// Decides which rows the list shows while a ranked run streams in (DESIGN.md section 5, "List streaming").
///
/// The backend sends a fully sorted snapshot about every 200 ms. Showing each one would make rows jump under
/// the reader's eyes, so: the old list holds until the first paint; the first paint waits for 8 listable rows or 350 ms;
/// after it, a new row shows at once only when it ranks below everything on screen; every other row is held and merged
/// in one snapshot when the run settles. Rows on screen therefore move once at most. A plain list (no sentence)
/// and a cached sentence repaint at once.
public struct ListStreaming {
    public enum Change: Equatable {
        case none
        /// Repaint at once, unanimated: a plain list, a cached sentence.
        case replace
        /// The first rows of a streamed run: cross-fade over 180 ms.
        case firstPaint
        /// Rows added below everything on screen: they fade in over 150 ms, nothing else moves.
        case append(Set<Int64>)
        /// The run settled: one unanimated merge; the rows that were held fade in.
        case merge(Set<Int64>)
    }

    public static let firstPaintRows = 8
    public static let firstPaintDelay = Duration.milliseconds(350)

    /// What the list draws.
    public private(set) var rows: [Row] = []
    /// The newest snapshot, shown or not. The foot always comes from here: it never waits for rows.
    public private(set) var latest: ListSnapshot?
    private var isRanked = false
    private var hasPainted = true
    private var hasStreamed = false
    private var deadlinePassed = false
    private var holdsUntilSettled = false

    public init() {}

    /// The centred line of an empty list. Never shown over rows, and never while an older list is still holding.
    public var emptyMessage: String? { rows.isEmpty && hasPainted ? latest?.emptyMessage : nil }
    public var emptyAction: FootAction? { emptyMessage == nil ? nil : latest?.emptyAction }
    public var lastNewRowID: Int64? { hasPainted ? latest?.lastNewRowID : nil }

    /// A new request starts. `rows` keeps the previous list: it holds at full strength until the new one paints.
    /// - Parameter holdsUntilSettled: with VoiceOver on, the whole list applies as one snapshot when the run settles.
    public mutating func begin(ranked: Bool, holdsUntilSettled: Bool) {
        isRanked = ranked
        hasPainted = !ranked
        hasStreamed = false
        deadlinePassed = false
        self.holdsUntilSettled = holdsUntilSettled
        latest = nil
    }

    public mutating func receive(_ snapshot: ListSnapshot) -> Change {
        latest = snapshot
        guard isRanked, snapshot.isRunning else { return settle(with: snapshot) }
        hasStreamed = true
        guard !holdsUntilSettled else { return .none }
        guard hasPainted else { return paintIfReady() }

        // Rows on screen take the snapshot's newer content (read state) in place, and never reorder.
        let incoming = Dictionary(uniqueKeysWithValues: snapshot.rows.map { ($0.id, $0) })
        rows = rows.map { incoming[$0.id] ?? $0 }
        let shown = Set(rows.map(\.id))
        let lowestShown = snapshot.rows.lastIndex { shown.contains($0.id) } ?? -1
        let below = snapshot.rows[(lowestShown + 1)...].filter { !shown.contains($0.id) }
        guard !below.isEmpty else { return .none }
        rows += below
        return .append(Set(below.map(\.id)))
    }

    /// Call `firstPaintDelay` after `begin`. With nothing listable yet, the first listable row will paint when it comes.
    public mutating func firstPaintDeadlinePassed() -> Change {
        deadlinePassed = true
        guard isRanked, !hasPainted, !holdsUntilSettled, latest?.isRunning == true else { return .none }
        return paintIfReady()
    }

    private mutating func paintIfReady() -> Change {
        guard let snapshot = latest, snapshot.rows.count >= Self.firstPaintRows || (deadlinePassed && !snapshot.rows.isEmpty) else { return .none }
        rows = snapshot.rows
        hasPainted = true
        return .firstPaint
    }

    private mutating func settle(with snapshot: ListSnapshot) -> Change {
        let shown = Set(rows.map(\.id))
        let wasPainted = hasPainted
        rows = snapshot.rows
        hasPainted = true
        guard isRanked, hasStreamed else { return .replace }
        return wasPainted ? .merge(Set(snapshot.rows.map(\.id)).subtracting(shown)) : .firstPaint
    }
}
