import AppKit

/// The map beside the scroller: one mark per marked paragraph, at its true place and height in the document.
///
/// It has no track and no border, so it is invisible unless there are marks. It is a mouse-only convenience:
/// it takes no focus and is hidden from accessibility, because Find Next is its keyboard and VoiceOver equivalent.
final class ReaderStripView: NSView {
    /// The strip draws straight from the page's layout cache and fades, so it is always true to what the page shows.
    weak var page: ReaderTextView?
    /// A scroll over the lane must still scroll the article.
    weak var scrollView: NSScrollView?
    var onJump: ((_ passage: Int) -> Void)?

    static let laneWidth: CGFloat = 16
    /// A click this close to a mark, vertically, counts as a click on it.
    private static let reach: CGFloat = 12
    /// Marks share their trailing edge, so the current one widens toward the text.
    private static let trailingInset: CGFloat = 2

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override func isAccessibilityElement() -> Bool { false }
    override func isAccessibilityHidden() -> Bool { true }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let page, let context = NSGraphicsContext.current?.cgContext else { return }
        let raised = ReaderContrast.isRaised
        for entry in page.stripEntries() {
            draw(entry, raised: raised, in: context)
        }
    }

    private func draw(_ entry: ReaderStripEntry, raised: Bool, in context: CGContext) {
        let top = entry.top * bounds.height
        let natural = entry.height * bounds.height
        let edge = bounds.maxX - Self.trailingInset

        func rect(width: CGFloat, minimumHeight: CGFloat) -> NSRect {
            backingAlignedRect(NSRect(x: edge - width, y: top, width: width, height: max(natural, minimumHeight)), options: .alignAllEdgesNearest)
        }
        func withOpacity(_ opacity: CGFloat, _ body: () -> Void) {
            guard opacity > 0 else { return }
            context.saveGState()
            context.setAlpha(opacity)
            body()
            context.restoreGState()
        }

        // A current mark is 10 pt wide, toward the text. Like everything else it arrives by opacity: the wider
        // shape fades in over the resting one; nothing grows.
        switch entry.hit {
        case .found:
            ReaderTheme.hitInk.setFill()
            withOpacity(entry.hitOpacity) { NSBezierPath(roundedRect: rect(width: 6, minimumHeight: 3), xRadius: 1.5, yRadius: 1.5).fill() }
            withOpacity(entry.hitOpacity * entry.emphasis) { NSBezierPath(roundedRect: rect(width: 10, minimumHeight: 3), xRadius: 1.5, yRadius: 1.5).fill() }
        case .unsure:
            ReaderTheme.hitInk.setStroke()
            withOpacity(entry.hitOpacity * (1 - entry.emphasis)) { strokeHollow(rect(width: 8, minimumHeight: 6)) }
            withOpacity(entry.hitOpacity * entry.emphasis) { strokeHollow(rect(width: 10, minimumHeight: 6)) }
        case .none, .pending, .unchecked:
            break
        }
        // Not checked: a 2 pt segment centred on the column the solid marks occupy, in the rail's colour.
        withOpacity(entry.railOpacity) {
            (entry.isSettledRail ? ReaderContrast.settledRail(raised: raised) : ReaderContrast.pendingRail(raised: raised)).setFill()
            rect(width: 6, minimumHeight: 1).insetBy(dx: 2, dy: 0).fill(using: .sourceOver)
        }
    }

    private func strokeHollow(_ rect: NSRect) {
        let lineWidth: CGFloat = 1.5
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2), xRadius: 2, yRadius: 2)
        path.lineWidth = lineWidth
        path.stroke()
    }

    // MARK: Clicks

    /// The nearest hit mark within reach of `point`, or nil. Rails are not destinations.
    private func passage(near point: NSPoint) -> Int? {
        guard let page, bounds.contains(point) else { return nil }
        let candidates = page.stripEntries().filter { $0.hit.isHit && $0.hitOpacity > 0 }
        let nearest = candidates.map { entry -> (passage: Int, distance: CGFloat) in
            let top = entry.top * bounds.height
            let bottom = top + max(entry.height * bounds.height, 3)
            return (entry.passage, point.y < top ? top - point.y : max(point.y - bottom, 0))
        }.min { $0.distance < $1.distance }
        guard let nearest, nearest.distance <= Self.reach else { return nil }
        return nearest.passage
    }

    /// Anywhere that is not near a mark belongs to the page underneath: selection, scrolling and the I-beam go through.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview else { return nil }
        return passage(near: convert(point, from: superview)) == nil ? nil : self
    }

    override func mouseDown(with event: NSEvent) {
        guard let passage = passage(near: convert(event.locationInWindow, from: nil)) else { return }
        onJump?(passage)
    }

    override func scrollWheel(with event: NSEvent) {
        scrollView?.scrollWheel(with: event)
    }
}
