import BeamModels

/// What the reader can navigate, derived once from a snapshot and shared by the pane, the page and the foot.
struct ReaderHitState: Equatable {
    var itemID: Int64?
    var phase: ReaderPhase?
    var sentence: String?
    /// Found and unsure passages in reading order, as far as they are on the page: empty while marks are held or saturated.
    var hits: [Int] = []
    var found = 0
    var unsure = 0
    var checked = 0
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
        guard snapshot.phase == .ready else { return }
        checked = snapshot.passages.indices.filter { snapshot.passages[$0].isJudgeable && (snapshot.checks[$0]?.isChecked ?? false) }.count
        guard !snapshot.isSaturated, !ReaderMarkPlan.isHoldingHits(snapshot) else { return }
        hits = snapshot.hits
        found = hits.filter { snapshot.band(at: $0) == .found }.count
        unsure = hits.count - found
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

    init(snapshot: ReaderSnapshot?, hits: ReaderHitState, currentHit: Int?, isAskOpen: Bool, showsLoadingNotice: Bool) {
        guard let snapshot else { return }
        switch snapshot.phase {
        case .preview:
            status = snapshot.foot.text.isEmpty ? ReaderCopy.returnToRead : snapshot.foot.readerSentence
        case .external:
            status = snapshot.foot.text.isEmpty ? ReaderCopy.returnToOpenInBrowser : snapshot.foot.readerSentence
        case .loading:
            // Only a wait of more than a second is worth a sentence.
            if showsLoadingNotice { status = snapshot.foot.text.isEmpty ? ReaderCopy.gettingArticle : snapshot.foot.readerSentence }
        case .unavailable:
            status = ReaderCopy.unavailable
            isProminent = true
            buttonTitle = ReaderCopy.openOriginalSentence
            button = .openOriginal
        case .ready:
            readyStatus(snapshot, hits: hits, currentHit: currentHit)
            counterSlot(hits: hits, currentHit: currentHit, isAskOpen: isAskOpen)
            // The paragraph count of a saturated article lives in the help tag, wherever its sentence is showing.
            if hits.isSaturated, counter != nil { counterHelp = snapshot.foot.help }
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

    private mutating func counterSlot(hits: ReaderHitState, currentHit: Int?, isAskOpen: Bool) {
        if hits.canNavigate, let currentHit {
            counter = ReaderCopy.counter(currentHit + 1, of: hits.hits.count)
            showsChevrons = true
        } else if isAskOpen, hits.sentence != nil {
            // The ask field has taken the status sentence's place, so the slot carries its short form.
            if hits.isSaturated {
                counter = ReaderCopy.saturatedShort
            } else if hits.canNavigate {
                counter = ReaderCopy.summary(found: hits.found, unsure: hits.unsure)
                showsChevrons = true
            } else if hits.isRunning {
                counter = ReaderCopy.checking
            } else {
                counter = ReaderCopy.nothingFound(checked: hits.checked)
            }
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
