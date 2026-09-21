import BeamModels

/// What the reader can navigate, derived once from a snapshot and shared by the pane, the page and the foot.
struct ReaderHitState: Equatable {
    var itemID: Int64?
    var phase: ReaderPhase?
    var sentence: String?
    /// Found and unsure passages in reading order, as far as they are on the page: empty while marks are held or saturated.
    var hits: [Int] = []
    var isSaturated = false
    var isRunning = false

    var isArticleOpen: Bool { phase == .ready }
    var canNavigate: Bool { isArticleOpen && !isSaturated && !hits.isEmpty }

    init(snapshot: ReaderSnapshot?) {
        guard let snapshot else { return }
        itemID = snapshot.item.id
        phase = snapshot.phase
        sentence = snapshot.sentence
        isSaturated = snapshot.isSaturated
        isRunning = snapshot.isRunning
        guard snapshot.phase == .ready, !snapshot.isSaturated, !ReaderMarkPlan.isHoldingHits(snapshot) else { return }
        hits = snapshot.hits
    }
}

/// Everything the foot shows, decided in one place.
///
/// The left side is the status sentence (or the ask field, which the view swaps in). The right side is the counter slot:
/// "2 of 5" with its chevrons after the first jump, or, while the ask field covers the status, a short form of it.
struct ReaderFootModel: Equatable {
    enum Button: Equatable {
        case foot(FootAction)
        /// The failed-article line ends in "Open Original.", which is the reader's own action, not a foot action.
        case openOriginal
    }

    var status = ""
    var isProminent = false
    var help: String?
    var buttonTitle: String?
    var button: Button?
    /// The counter slot's text, or nil when the slot is empty.
    var counter: String?
    var counterHelp: String?
    /// Whether the chevrons accompany the counter text.
    var showsChevrons = false

    init(snapshot: ReaderSnapshot?, hits: ReaderHitState, currentHit: Int?, isAskOpen: Bool) {
        guard let snapshot else { return }
        switch snapshot.phase {
        case .preview, .loading, .external:
            // Whatever the engine is saying: "Return to read", "Return to open in your browser", or, once a load has
            // taken more than a second, "Getting the article". A load that answers sooner says nothing.
            status = snapshot.foot.readerSentence
        case .unavailable:
            // The one sentence the engine cannot send: its tail is Open Original, which is not a `FootAction`.
            status = ReaderCopy.unavailable
            isProminent = true
            buttonTitle = ReaderCopy.openOriginalSentence
            button = .openOriginal
        case .ready:
            readyStatus(snapshot, hits: hits, currentHit: currentHit)
            counterSlot(snapshot, hits: hits, currentHit: currentHit, isAskOpen: isAskOpen)
        }
    }

    private mutating func readyStatus(_ snapshot: ReaderSnapshot, hits: ReaderHitState, currentHit: Int?) {
        if let currentHit, hits.hits.indices.contains(currentHit), snapshot.band(at: hits.hits[currentHit]) == .unsure {
            status = ReaderCopy.unsure
            return
        }
        status = snapshot.foot.readerSentence
        isProminent = snapshot.foot.isProminent || snapshot.foot.action != nil
        help = snapshot.foot.help
        if let title = snapshot.foot.actionTitle, let action = snapshot.foot.action {
            buttonTitle = title
            button = .foot(action)
        }
    }

    /// "2 of 5" once a jump has been made. While the ask field covers the status, the engine's sentence moves here
    /// instead: it arrives in its short form ("Checking", "3 found, 2 unsure"), which is what fits beside the field.
    private mutating func counterSlot(_ snapshot: ReaderSnapshot, hits: ReaderHitState, currentHit: Int?, isAskOpen: Bool) {
        if hits.canNavigate, let currentHit {
            counter = ReaderCopy.counter(currentHit + 1, of: hits.hits.count)
            showsChevrons = true
        } else if isAskOpen, hits.sentence != nil {
            counter = snapshot.foot.readerSentence
            // The paragraph count of a saturated article lives in the help tag, wherever its sentence is showing.
            counterHelp = snapshot.foot.help
        }
    }
}

extension Foot {
    /// The sentence without its button's words, whether or not the engine repeated them at the end of `text`.
    var readerSentence: String {
        guard let actionTitle, !actionTitle.isEmpty, text.hasSuffix(actionTitle) else { return text }
        return String(text.dropLast(actionTitle.count)).trimmingCharacters(in: .whitespaces)
    }
}
