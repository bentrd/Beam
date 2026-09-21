import AppKit

/// The scroll view, the page and the strip, as one AppKit view.
///
/// The strip is a sibling laid over the scroll view's trailing margin, not a SwiftUI overlay: that way it can let every
/// event that is not a click on a mark fall through to the page, and a scroll over it still scrolls the article.
final class ReaderPageView: NSView {
    let scrollView = NSScrollView()
    let textView = ReaderTextView(usingTextLayoutManager: true)
    let strip = ReaderStripView()
    private let veil = ReaderVeilView()
    private var veilFades = 0

    /// Keeps the strip's ends clear of the window's rounded corners and the scroller's caps.
    private static let stripVerticalInset: CGFloat = 8

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureTextView()
        configureScrollView()
        strip.page = textView
        strip.scrollView = scrollView
        veil.isHidden = true
        addSubview(scrollView)
        addSubview(veil)
        addSubview(strip)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("ReaderPageView is created in code only") }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        // A 16 pt lane at the trailing edge, inset by the width a legacy scroller takes, so it never sits under one.
        let scroller = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
        strip.frame = NSRect(x: bounds.maxX - scroller - ReaderStripView.laneWidth, y: Self.stripVerticalInset,
                             width: ReaderStripView.laneWidth, height: max(bounds.height - Self.stripVerticalInset * 2, 0))
        strip.needsDisplay = true
    }

    /// The body's arrival: 200 ms, opacity only, with the header already in its final place.
    ///
    /// TextKit 2 draws glyphs in views of its own, above anything the text view can paint, and their opacity cannot be
    /// animated without touching the storage. So paper is laid over the body and cleared instead.
    /// - Parameter top: where the body begins, in this view's coordinates.
    func fadeInBody(below top: CGFloat) {
        let page = scrollView.contentView.frame
        veil.frame = NSRect(x: page.minX, y: top, width: page.width, height: max(page.maxY - top, 0))
        veil.alphaValue = 1
        veil.isHidden = false
        veilFades += 1
        let fade = veilFades
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.bodyFadeIn
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            veil.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, fade == self.veilFades else { return }
                self.veil.isHidden = true
            }
        })
    }

    private static let bodyFadeIn: TimeInterval = 0.2

    private func configureScrollView() {
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = ReaderTheme.paper
        scrollView.documentView = textView
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.contentView.postsFrameChangedNotifications = true
    }

    private func configureTextView() {
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        // The measure is exact and the tint outsets are counted from the text itself, so no hidden padding.
        textView.textContainer?.lineFragmentPadding = 0
        textView.postsFrameChangedNotifications = true

        // A reader, not an editor: nothing detects, corrects, rewrites or searches literally.
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.allowsUndo = false
        textView.usesFindBar = false
        textView.isIncrementalSearchingEnabled = false
        textView.usesFontPanel = false
        textView.usesRuler = false
        textView.writingToolsBehavior = .none
        // The link is a marker, not an address; its raw value must never show in a tool tip.
        textView.displaysLinkToolTips = false
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.labelColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand,
        ]
        textView.refreshSystemColors()
    }
}

/// A sheet of paper over the body while it fades in. It is never a target: every event goes to the page beneath.
private final class ReaderVeilView: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }

    /// Since macOS 14 a view's dirty rect may reach beyond its bounds, and the header above must stay uncovered.
    override func draw(_ dirtyRect: NSRect) {
        ReaderTheme.paper.setFill()
        bounds.fill()
    }
}
