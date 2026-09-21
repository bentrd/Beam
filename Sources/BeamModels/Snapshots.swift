import Foundation

// Everything the UI renders arrives as one of these immutable snapshots. Views hold no logic:
// they draw a snapshot and call `BeamBackend`. All user-facing sentences are produced by the engine
// (so `beam-eval` can check the exact wording in DESIGN.md section 6) and carried in `Foot`.

// MARK: Feet

/// The trailing text button a foot sentence may carry.
public enum FootAction: String, Hashable, Codable, Sendable {
    case retry, openSettings, checkOlder, findNarrower, addSource
}

/// The single line at the bottom of the list and of the reader. One message at a time.
public struct Foot: Hashable, Sendable {
    public var text: String
    public var actionTitle: String?
    public var action: FootAction?
    /// Errors, and any sentence with a button, are drawn in `labelColor`; plain status is secondary.
    public var isProminent: Bool
    /// Extra detail for the help tag and the accessibility value (for example "94 of 159 paragraphs").
    public var help: String?

    public init(_ text: String = "", actionTitle: String? = nil, action: FootAction? = nil, isProminent: Bool = false, help: String? = nil) {
        self.text = text; self.actionTitle = actionTitle; self.action = action; self.isProminent = isProminent; self.help = help
    }
    public static let blank = Foot()
}

// MARK: Sidebar

public struct SourceSummary: Identifiable, Hashable, Sendable {
    public var source: Source
    public var unread: Int
    /// True once the source has been failing for more than 24 hours: the only case that earns a warning glyph.
    public var showsWarning: Bool
    public var id: Int64 { source.id }
    public init(source: Source, unread: Int, showsWarning: Bool = false) { self.source = source; self.unread = unread; self.showsWarning = showsWarning }
}

public struct PinSummary: Identifiable, Hashable, Sendable {
    public var pin: Pin
    /// Found items that arrived since the pin was last viewed.
    public var newFound: Int
    /// Items still unchecked after retries: the pin row shows the monochrome warning glyph.
    public var hasUnchecked: Bool
    public var id: Int64 { pin.id }
    public init(pin: Pin, newFound: Int, hasUnchecked: Bool = false) { self.pin = pin; self.newFound = newFound; self.hasUnchecked = hasUnchecked }
}

public struct SidebarSnapshot: Hashable, Sendable {
    public var unreadInAll: Int
    public var pins: [PinSummary]
    public var sources: [SourceSummary]
    public init(unreadInAll: Int = 0, pins: [PinSummary] = [], sources: [SourceSummary] = []) {
        self.unreadInAll = unreadInAll; self.pins = pins; self.sources = sources
    }
}

// MARK: Lists

public enum ListScope: Hashable, Codable, Sendable {
    case all
    case source(Int64)
    case pin(Int64)
}

public struct ListRequest: Hashable, Sendable {
    public var scope: ListScope
    /// The submitted sentence, or nil for a plain chronological list. A pin scope supplies its own sentence.
    public var sentence: String?
    /// View ▸ Hide Read Items. Ignored while a sentence is active (searches and pins always show read items).
    public var hidesRead: Bool
    public init(scope: ListScope = .all, sentence: String? = nil, hidesRead: Bool = false) {
        self.scope = scope; self.sentence = sentence; self.hidesRead = hidesRead
    }
}

public struct Row: Identifiable, Hashable, Sendable {
    public var item: Item
    public var sourceTitle: String
    /// nil when no sentence is active.
    public var check: Check?
    /// The 4 x 12 pt list mark: drawn only for p >= 0.60, at full strength, never graded.
    public var isMarked: Bool
    public var id: Int64 { item.id }
    public init(item: Item, sourceTitle: String, check: Check? = nil, isMarked: Bool = false) {
        self.item = item; self.sourceTitle = sourceTitle; self.check = check; self.isMarked = isMarked
    }
}

public struct ListSnapshot: Sendable {
    public var request: ListRequest
    public var rows: [Row]
    public var isRunning: Bool
    /// One centred secondary line when there are no rows ("Nothing found in 300 items checked", "No sources yet.", …).
    public var emptyMessage: String?
    public var emptyAction: FootAction?
    public var foot: Foot
    /// Pins only: the row under which the full-width "new since last viewed" separator runs.
    public var lastNewRowID: Int64?

    public init(request: ListRequest, rows: [Row] = [], isRunning: Bool = false, emptyMessage: String? = nil,
                emptyAction: FootAction? = nil, foot: Foot = .blank, lastNewRowID: Int64? = nil) {
        self.request = request; self.rows = rows; self.isRunning = isRunning; self.emptyMessage = emptyMessage
        self.emptyAction = emptyAction; self.foot = foot; self.lastNewRowID = lastNewRowID
    }
}

// MARK: Reader

public enum ReaderPhase: String, Hashable, Sendable {
    /// A row is selected but not opened: title, snippet, "Return to read". Nothing has been fetched or sent.
    case preview
    case loading
    case ready
    /// "Beam couldn't get the article text. Open Original."
    case unavailable
    /// Opens in the browser (YouTube).
    case external
}

public struct ReaderSnapshot: Sendable {
    public var item: Item
    public var sourceTitle: String
    public var phase: ReaderPhase
    public var passages: [Passage]
    /// Keyed by passage index. Headings and code never appear here.
    public var checks: [Int: Check]
    public var omittedImages: Int
    public var omittedTables: Int
    /// The sentence the marks belong to: the Find by Meaning sentence if one is active, else the carried one.
    public var sentence: String?
    public var isFindActive: Bool
    /// True when the sentence describes the whole article: draw no tints, bars or strip marks.
    public var isSaturated: Bool
    /// Found and unsure passage indexes in reading order. Empty when saturated.
    public var hits: [Int]
    public var foot: Foot
    public var isRunning: Bool

    public init(item: Item, sourceTitle: String, phase: ReaderPhase, passages: [Passage] = [], checks: [Int: Check] = [:],
                omittedImages: Int = 0, omittedTables: Int = 0, sentence: String? = nil, isFindActive: Bool = false,
                isSaturated: Bool = false, hits: [Int] = [], foot: Foot = .blank, isRunning: Bool = false) {
        self.item = item; self.sourceTitle = sourceTitle; self.phase = phase; self.passages = passages; self.checks = checks
        self.omittedImages = omittedImages; self.omittedTables = omittedTables; self.sentence = sentence
        self.isFindActive = isFindActive; self.isSaturated = isSaturated; self.hits = hits; self.foot = foot; self.isRunning = isRunning
    }

    public func band(at index: Int) -> Band {
        guard !isSaturated, let p = checks[index]?.probability else { return .nothing }
        return Bands.passage(p)
    }
    public func isUnchecked(at index: Int) -> Bool {
        guard passages.indices.contains(index), passages[index].isJudgeable, sentence != nil else { return false }
        return !(checks[index]?.isChecked ?? false)
    }
}
