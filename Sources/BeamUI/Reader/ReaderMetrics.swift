import AppKit

/// The eight persisted reader text sizes. Public so the shell's View menu and the reader agree on the steps.
public enum ReaderTextSize {
    public static let steps: [CGFloat] = [15, 16, 17, 18, 20, 22, 25, 28]
    /// What Actual Size returns to.
    public static let standard: CGFloat = 17

    /// The next step up, or the same size at the top. Sizes between steps snap outward.
    public static func larger(than size: CGFloat) -> CGFloat { steps.first { $0 > size } ?? steps[steps.count - 1] }
    public static func smaller(than size: CGFloat) -> CGFloat { steps.last { $0 < size } ?? steps[0] }
}

/// Every dimension of the page that follows the text size. DESIGN.md gives the values at 17 pt;
/// the measure, the mark slot and the outsets scale with the body so the page keeps its proportions at every step.
struct ReaderMetrics: Equatable {
    let textSize: CGFloat

    init(textSize: CGFloat) {
        self.textSize = min(max(textSize, ReaderTextSize.steps[0]), ReaderTextSize.steps[ReaderTextSize.steps.count - 1])
    }

    private var scale: CGFloat { textSize / ReaderTextSize.standard }
    private func scaled(_ value: CGFloat) -> CGFloat { (value * scale * 2).rounded() / 2 }

    // Type
    var titleSize: CGFloat { scaled(28) }
    var headingSize: CGFloat { scaled(20) }
    var bylineSize: CGFloat { scaled(12) }
    var codeSize: CGFloat { scaled(14) }
    var bodyLeading: CGFloat { scaled(26) }
    var codeLeading: CGFloat { scaled(20) }
    var paragraphSpacing: CGFloat { scaled(14) }
    var headingSpacingBefore: CGFloat { scaled(14) }
    var headingSpacingAfter: CGFloat { scaled(8) }
    var titleSpacingAfter: CGFloat { scaled(8) }
    /// Between the title and the snippet of a preview, where an opened article has its byline and hairline.
    var previewSpacing: CGFloat { scaled(18) }
    /// From the byline's last line to the first line of the body; the hairline sits inside this gap.
    var headerSpacingAfter: CGFloat { scaled(40) }
    var hairlineOffset: CGFloat { scaled(17) }
    var quoteIndent: CGFloat { scaled(24) }
    var listIndent: CGFloat { scaled(20) }

    // Page
    /// A 66-character line of New York is about 31 em wide in running English text.
    var measure: CGFloat { (textSize * 31).rounded() }
    /// The title starts this far below the toolbar edge. Fixed: it belongs to the window, not to the text.
    let topInset: CGFloat = 32
    /// Each side keeps room for the mark slot and the strip whatever the window width: never less than 44 pt,
    /// and never so little that a tint's outset would run under the strip's lane.
    var sideMinimum: CGFloat {
        let slot = slotOffset + barWidth(current: true) + 12
        let strip = tintOutset.width + ReaderStripView.laneWidth + NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy) + 2
        return max(44, slot, strip)
    }

    // Marks
    var tintOutset: NSSize { NSSize(width: scaled(12), height: scaled(5)) }
    var tintRadius: CGFloat { scaled(6) }
    /// The gap between the text's leading edge and the margin slot.
    var slotOffset: CGFloat { scaled(20) }
    func barWidth(current: Bool) -> CGFloat { scaled(current ? 8 : 6) }
}
