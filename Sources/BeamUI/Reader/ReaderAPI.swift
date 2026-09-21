import BeamModels
import SwiftUI

// The seam between the two UI lanes. The shell lane (window, sidebar, list, menus) uses ONLY what is declared here;
// the reader lane owns everything else under Sources/BeamUI/Reader and may extend these types, but must not
// change or remove anything public below.

/// What the reader asks the rest of the app to do.
public struct ReaderActions {
    /// Find by Meaning: a sentence to re-light this article with, or nil to restore the carried sentence.
    public var find: (String?) -> Void
    /// The judgeable passages currently on screen changed (passage indexes).
    public var viewportChanged: (_ first: Int, _ last: Int) -> Void
    public var footAction: (FootAction) -> Void
    public var openOriginal: () -> Void

    public init(find: @escaping (String?) -> Void = { _ in },
                viewportChanged: @escaping (Int, Int) -> Void = { _, _ in },
                footAction: @escaping (FootAction) -> Void = { _ in },
                openOriginal: @escaping () -> Void = {}) {
        self.find = find; self.viewportChanged = viewportChanged; self.footAction = footAction; self.openOriginal = openOriginal
    }
}

/// Lets menu commands drive the reader (Find by Meaning…, Find Next, Find Previous, Use Selection for Find, Jump to Selection).
@MainActor @Observable
public final class ReaderController {
    public init() {}

    /// Index into the current snapshot's `hits`, or nil before the first jump.
    public var currentHit: Int?
    /// Whether the ask field has replaced the status text in the reader foot.
    public var isAskOpen = false
    /// Text to put in the ask field when it opens (Use Selection for Find).
    public var askPrefill: String?
    /// Incremented for every jump so the page view knows to scroll even if `currentHit` is unchanged.
    public private(set) var jumpCount = 0
    /// Set by the reader: true when an article is open and marks are navigable (false when saturated or empty).
    public var canNavigate = false
    public var isArticleOpen = false
    /// The reader's current text selection, for Use Selection for Find.
    public var selectedText: String?
    var hitCount = 0

    public func next() { step(1) }
    public func previous() { step(-1) }
    public func openAsk(prefill: String? = nil) { askPrefill = prefill; isAskOpen = true }
    public func closeAsk() { isAskOpen = false }
    public func jumpToSelection() { jumpCount += 1 }
    public func reset() { currentHit = nil; isAskOpen = false; askPrefill = nil; canNavigate = false; hitCount = 0 }

    func step(_ delta: Int) {
        guard canNavigate, hitCount > 0 else { return }
        currentHit = ((currentHit ?? (delta > 0 ? -1 : 0)) + delta + hitCount) % hitCount      // wraps at both ends
        jumpCount += 1
        hitJumpCount += 1
    }

    // MARK: Added by the reader lane (additive: nothing public above changed; `step` also counts its jump below)

    /// Counts jumps to a hit only. `jumpCount` also counts Jump to Selection, and the page must tell the two apart
    /// even when `currentHit` does not change (Find Next in an article with a single hit).
    private(set) var hitJumpCount = 0

    /// A click on the strip lands on one particular hit instead of stepping to a neighbour.
    func jump(toHit index: Int) {
        guard canNavigate, (0..<hitCount).contains(index) else { return }
        currentHit = index
        jumpCount += 1
        hitJumpCount += 1
    }

    /// Pages the article from wherever the focus is: Space and Shift-Space in the list page the reader without a focus change.
    public func pageDown() { pageRequest = PageRequest(count: pageRequest.count + 1, isDown: true) }
    public func pageUp() { pageRequest = PageRequest(count: pageRequest.count + 1, isDown: false) }

    struct PageRequest: Equatable {
        var count = 0
        var isDown = true
    }
    private(set) var pageRequest = PageRequest()
}
