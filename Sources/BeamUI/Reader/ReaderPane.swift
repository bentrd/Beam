import BeamModels
import SwiftUI

/// The reader: one page of text with Beam's marks painted behind it, a strip beside the scroller and a one-line foot.
///
/// The pane holds no product logic. It draws a `ReaderSnapshot`, keeps `ReaderController` truthful about what can be
/// navigated, and reports what the reader does through `ReaderActions`.
public struct ReaderPane: View {
    @Environment(\.beamHighlightColor) private var highlightColor
    private let snapshot: ReaderSnapshot?
    private let textSize: CGFloat
    private let controller: ReaderController
    private let actions: ReaderActions

    /// The last question asked of each article, so reopening the ask field on the same article restores it.
    @State private var lastQuestion: (itemID: Int64, text: String)?
    /// The passage the current hit points at. Hits arrive in reading order while a run is going, so an index into
    /// `hits` can come to mean another paragraph; the passage is what stays current.
    @State private var currentPassage: Int?
    @State private var pageFocusRequests = 0
    /// True once the foot hangs on the pane's split-view item. Until then, and in a window with no split view, the
    /// pane insets a foot of its own.
    @State private var footIsAccessory = false

    /// - Parameters:
    ///   - snapshot: nil means nothing is selected: blank paper and a blank foot.
    ///   - textSize: the reader body size in points (eight steps, 15…28, default 17; see `ReaderTextSize`).
    ///   - controller: lets menu commands drive the reader; the pane keeps its `canNavigate`, `isArticleOpen` and `selectedText` current.
    ///   - actions: what the reader asks of the app. `FootAction.findNarrower` is the one action the reader performs
    ///     itself (it opens the ask field); every other foot action is forwarded to `footAction`.
    public init(snapshot: ReaderSnapshot?, textSize: CGFloat, controller: ReaderController, actions: ReaderActions) {
        self.snapshot = snapshot
        self.textSize = textSize
        self.controller = controller
        self.actions = actions
    }

    public var body: some View {
        let hits = ReaderHitState(snapshot: snapshot)
        let isAskOpen = controller.isAskOpen && hits.isArticleOpen
        let foot = foot(hits, isAskOpen: isAskOpen)
        ReaderPage(snapshot: snapshot, textSize: textSize, highlightColor: highlightColor, commands: commands(hits), controller: controller, actions: actions)
            // The system's own separator stays hidden while nothing scrolls under the accessory, and the reader's
            // AppKit scroll view cannot be given the hard scroll-edge effect, so the page keeps its bottom hairline.
            .overlay(alignment: .bottom) { if footIsAccessory { Divider() } }
            .safeAreaInset(edge: .bottom, spacing: 0) { if !footIsAccessory { foot } }
            .background(Color(nsColor: ReaderTheme.paper))
            .background { ReaderFootAccessory(foot: foot) { footIsAccessory = $0 } }
            .onChange(of: hits, initial: true) { old, new in sync(from: old, to: new) }
            .onChange(of: controller.currentHit) { _, hit in
                currentPassage = hit.flatMap { hits.hits.indices.contains($0) ? hits.hits[$0] : nil }
            }
            .onChange(of: hits.isRunning) { wasRunning, isRunning in
                if wasRunning, !isRunning, let foot = snapshot?.foot { ReaderAnnouncer.announceSettled(foot.text) }
            }
    }

    private func foot(_ hits: ReaderHitState, isAskOpen: Bool) -> ReaderFoot {
        ReaderFoot(model: ReaderFootModel(snapshot: snapshot, hits: hits, currentHit: controller.currentHit,
                                          isAskOpen: isAskOpen),
                   isAccessory: footIsAccessory,
                   isAskOpen: isAskOpen,
                   askOpeningText: askOpeningText(for: hits.itemID),
                   askPrefill: controller.askPrefill,
                   canStep: hits.canNavigate,
                   onButton: perform,
                   onAsk: { ask($0, itemID: hits.itemID) },
                   onCloseAsk: closeAsk,
                   onStep: { $0 > 0 ? controller.next() : controller.previous() })
    }

    private func commands(_ hits: ReaderHitState) -> ReaderPage.Commands {
        let position = controller.currentHit.flatMap { hits.hits.indices.contains($0) ? $0 : nil }
        return ReaderPage.Commands(currentPassage: position.map { hits.hits[$0] }, currentPosition: position, hits: hits.hits,
                                   hitJumps: controller.hitJumpCount, jumps: controller.jumpCount, page: controller.pageRequest,
                                   focusRequests: pageFocusRequests)
    }

    // MARK: Keeping the controller truthful

    private func sync(from old: ReaderHitState, to new: ReaderHitState) {
        if old.itemID != new.itemID || old.sentence != new.sentence {
            // Another article or another sentence: the old position means nothing now.
            controller.currentHit = nil
            currentPassage = nil
        } else if old.hits != new.hits, let passage = currentPassage {
            controller.currentHit = new.hits.firstIndex(of: passage)
        }
        if old.itemID != new.itemID || !new.isArticleOpen { controller.isAskOpen = false }
        controller.hitCount = new.hits.count
        controller.canNavigate = new.canNavigate
        controller.isArticleOpen = new.isArticleOpen
        if !new.isArticleOpen { controller.selectedText = nil }
    }

    // MARK: The ask field

    private func askOpeningText(for itemID: Int64?) -> String {
        if let prefill = controller.askPrefill, !prefill.isEmpty { return prefill }
        if let lastQuestion, lastQuestion.itemID == itemID { return lastQuestion.text }
        return ""
    }

    private func ask(_ question: String, itemID: Int64?) {
        if let itemID { lastQuestion = (itemID, question) }
        actions.find(question)
    }

    /// Closing restores the carried sentence (its marks return from the cache at once). The keyboard goes back to
    /// the page only if the reader closed the field deliberately; if the focus already moved elsewhere, it stays there.
    private func closeAsk(returnsFocus: Bool) {
        controller.closeAsk()
        actions.find(nil)
        if returnsFocus { pageFocusRequests += 1 }
    }

    private func perform(_ button: ReaderFootModel.Button) {
        switch button {
        case .openOriginal: actions.openOriginal()
        case .foot(.findNarrower): controller.openAsk()
        case .foot(let action): actions.footAction(action)
        }
    }
}
