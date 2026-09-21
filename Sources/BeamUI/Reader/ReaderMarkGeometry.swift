import AppKit

/// Where a paragraph's marks go, given the rect its text occupies. All rects are in the text view's coordinates.
///
/// Everything hangs off the text container, not off the paragraph's own rag or indent: found tints span the full
/// measure so every tint shares the same two edges, and bars and rails share one column in the margin slot.
struct ReaderMarkGeometry {
    let metrics: ReaderMetrics
    /// The text container's origin in the view, and its width (the measure as laid out).
    let origin: NSPoint
    let measure: CGFloat

    /// A text rect from the layout cache (container coordinates) moved into the view.
    func textRect(_ cached: CGRect) -> NSRect { cached.offsetBy(dx: origin.x, dy: origin.y) }

    func tint(for text: NSRect) -> NSRect {
        let outset = metrics.tintOutset
        return NSRect(x: origin.x - outset.width, y: text.minY - outset.height,
                      width: measure + outset.width * 2, height: text.height + outset.height * 2)
    }

    /// The hollow bar of an unsure paragraph. It grows away from the text when current, so its near edge never moves.
    func bar(for text: NSRect, current: Bool) -> NSRect {
        let width = metrics.barWidth(current: current)
        return NSRect(x: origin.x - metrics.slotOffset - width, y: text.minY + 1, width: width, height: max(text.height - 2, width))
    }

    /// The rail of a paragraph that is not checked, centred on the column the resting bar occupies.
    func rail(for text: NSRect, weight: CGFloat) -> NSRect {
        let column = bar(for: text, current: false)
        return NSRect(x: column.midX - weight / 2, y: column.minY, width: weight, height: column.height)
    }

    /// The whole slot beside a paragraph: what a help tag covers.
    func slot(for text: NSRect) -> NSRect {
        let left = origin.x - metrics.slotOffset - metrics.barWidth(current: true) - 4
        return NSRect(x: left, y: text.minY, width: origin.x - 2 - left, height: text.height)
    }

    /// Everything a change to this paragraph's marks can touch. A fade invalidates this and nothing else.
    func damage(for text: NSRect) -> NSRect {
        tint(for: text).union(slot(for: text)).insetBy(dx: -2, dy: -2)
    }
}
