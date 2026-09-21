import AppKit
import SwiftUI

enum HitState { case found, unsure, nothing }
struct Mark: Identifiable { let id: Int; let top: CGFloat; let height: CGFloat; let state: HitState }

/// NSTextView that paints a soft rounded tint behind whole paragraphs, using TextKit 2 fragment frames.
final class ReaderTextView: NSTextView {
    var states: [Int: HitState] = [:]            // paragraph index -> state
    var paragraphRanges: [NSRange] = []
    var onLayout: (([Mark], CGFloat) -> Void)?

    func fragmentFrames() -> [Int: CGRect] {
        guard let tlm = textLayoutManager, let tcm = tlm.textContentManager else { return [:] }
        var frames: [Int: CGRect] = [:]
        tlm.ensureLayout(for: tlm.documentRange)
        tlm.enumerateTextLayoutFragments(from: tlm.documentRange.location, options: [.ensuresLayout]) { fragment in
            let start = tcm.offset(from: tlm.documentRange.location, to: fragment.rangeInElement.location)
            if let index = self.paragraphRanges.firstIndex(where: { NSLocationInRange(start, $0) }) {
                frames[index] = (frames[index] ?? fragment.layoutFragmentFrame).union(fragment.layoutFragmentFrame)
            }
            return true
        }
        return frames
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        let origin = textContainerOrigin
        for (index, frame) in fragmentFrames() {
            guard let state = states[index], state != .nothing else { continue }
            let box = frame.offsetBy(dx: origin.x, dy: origin.y).insetBy(dx: -14, dy: -5)
            guard box.intersects(rect) else { continue }
            let path = NSBezierPath(roundedRect: box, xRadius: 8, yRadius: 8)
            let tint = NSColor.controlAccentColor
            if state == .found { tint.withAlphaComponent(0.16).setFill(); path.fill() }
            else { tint.withAlphaComponent(0.45).setStroke(); path.lineWidth = 1; path.setLineDash([3, 3], count: 2, phase: 0); path.stroke() }
        }
    }

    func publishMarks() {
        let frames = fragmentFrames()
        let total = max((frames.values.map(\.maxY).max() ?? 1) + textContainerOrigin.y * 2, 1)
        let marks = frames.compactMap { index, f -> Mark? in
            guard let s = states[index] else { return nil }
            return Mark(id: index, top: (f.minY + textContainerOrigin.y) / total, height: f.height / total, state: s)
        }.sorted { $0.id < $1.id }
        onLayout?(marks, total)
    }
}

struct ReaderView: NSViewRepresentable {
    let passages: [Passage]
    let states: [Int: HitState]
    @Binding var jumpTo: Int?
    var onMarks: ([Mark]) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.scrollerStyle = .overlay
        let textView = ReaderTextView(usingTextLayoutManager: true)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 40)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        scroll.documentView = textView
        context.coordinator.textView = textView
        load(into: textView)
        NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: textView, queue: .main) { _ in
            MainActor.assumeIsolated { textView.publishMarks() }
        }
        textView.postsFrameChangedNotifications = true
        return scroll
    }

    func load(into view: ReaderTextView) {
        let out = NSMutableAttributedString()
        var ranges: [NSRange] = []
        for p in passages {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 5
            style.paragraphSpacing = p.kind == "heading" ? 10 : 18
            style.paragraphSpacingBefore = p.kind == "heading" ? 22 : 0
            let font: NSFont = p.kind == "heading"
                ? .systemFont(ofSize: 22, weight: .semibold)
                : (NSFont(descriptor: NSFontDescriptor.preferredFontDescriptor(forTextStyle: .body).withDesign(.serif)!, size: 17) ?? .systemFont(ofSize: 17))
            let start = out.length
            out.append(NSAttributedString(string: p.text + "\n", attributes: [
                .font: font, .paragraphStyle: style, .foregroundColor: NSColor.labelColor]))
            ranges.append(NSRange(location: start, length: out.length - start))
        }
        view.paragraphRanges = ranges
        view.states = states
        view.onLayout = { marks, _ in onMarks(marks) }
        view.textStorage?.setAttributedString(out)
        DispatchQueue.main.async { view.publishMarks() }
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = context.coordinator.textView else { return }
        let inset = max((scroll.contentSize.width - 680) / 2, 40)     // a calm 680pt measure
        view.textContainerInset = NSSize(width: inset, height: 40)
        if let target = jumpTo, target < view.paragraphRanges.count {
            if let frame = view.fragmentFrames()[target] {
                let y = frame.minY + view.textContainerOrigin.y - scroll.contentSize.height * 0.3
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.35; ctx.allowsImplicitAnimation = true
                    scroll.contentView.animator().setBoundsOrigin(NSPoint(x: 0, y: max(y, 0)))
                }
            }
            DispatchQueue.main.async { jumpTo = nil }
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var textView: ReaderTextView? }
}

struct Strip: View {
    let marks: [Mark]
    var tap: (Int) -> Void
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                ForEach(marks) { m in
                    if m.state != .nothing {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(m.state == .found ? Color.accentColor : Color.clear)
                            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Color.accentColor.opacity(m.state == .unsure ? 0.8 : 0), lineWidth: 1))
                            .frame(width: 6, height: max(m.height * geo.size.height, 4))
                            .offset(y: m.top * geo.size.height)
                            .onTapGesture { tap(m.id) }
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .center)
        }.frame(width: 18)
    }
}
