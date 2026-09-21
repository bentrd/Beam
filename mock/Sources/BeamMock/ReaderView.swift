import AppKit
import SwiftUI

struct StripMark: Identifiable { let id: Int; let top: CGFloat; let height: CGFloat; let band: Band }

/// The page. TextKit 2; marks are painted behind the text so native selection always wins.
final class PageTextView: NSTextView {
    var blockRanges: [(id: Int, range: NSRange)] = []
    var bands: [Int: Band] = [:]
    var currentID: Int?
    var bylineRange = NSRange(location: 0, length: 0)
    private var cache: [Int: CGRect] = [:]
    private var bylineRect: CGRect = .zero
    var onLayout: (([StripMark]) -> Void)?

    /// Exact text rects per block, from line fragments (excludes paragraph spacing). Cached once per layout pass.
    /// A 66-character measure, centred, never less than 44 pt a side.
    private func applyMeasure() {
        guard let width = enclosingScrollView?.contentSize.width, width > 0 else { return }
        let inset = NSSize(width: max(((width - 600) / 2).rounded(), 44), height: 32)
        if inset != textContainerInset { textContainerInset = inset }
    }

    func relayout() {
        applyMeasure()
        guard let tlm = textLayoutManager, let tcm = tlm.textContentManager else { return }
        cache.removeAll(); bylineRect = .zero
        tlm.ensureLayout(for: tlm.documentRange)
        tlm.enumerateTextLayoutFragments(from: tlm.documentRange.location, options: [.ensuresLayout]) { fragment in
            let start = tcm.offset(from: tlm.documentRange.location, to: fragment.rangeInElement.location)
            var rect = CGRect.null
            for line in fragment.textLineFragments { rect = rect.union(line.typographicBounds.offsetBy(dx: fragment.layoutFragmentFrame.minX, dy: fragment.layoutFragmentFrame.minY)) }
            guard !rect.isNull else { return true }
            if NSLocationInRange(start, self.bylineRange) { self.bylineRect = rect }
            if let block = self.blockRanges.first(where: { NSLocationInRange(start, $0.range) }) {
                self.cache[block.id] = (self.cache[block.id] ?? rect).union(rect)
            }
            return true
        }
        let height = max(frame.height, 1), o = textContainerOrigin
        onLayout?(cache.compactMap { id, r in
            guard let band = bands[id], band != .nothing else { return nil }
            return StripMark(id: id, top: (r.minY + o.y) / height, height: r.height / height, band: band)
        }.sorted { $0.top < $1.top })
        needsDisplay = true
    }

    func rect(for id: Int) -> CGRect? { cache[id].map { $0.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y) } }

    override func drawBackground(in dirty: NSRect) {
        super.drawBackground(in: dirty)
        let o = textContainerOrigin
        if bylineRect != .zero {                                   // the header hairline is drawn, never a character
            NSColor.separatorColor.setFill()
            NSRect(x: o.x + bylineRect.minX, y: o.y + bylineRect.maxY + 17, width: textContainer?.size.width ?? 0, height: 1).fill()
        }
        for (id, r) in cache {
            guard let band = bands[id], band != .nothing else { continue }
            let text = r.offsetBy(dx: o.x, dy: o.y)
            let current = id == currentID
            switch band {
            case .found:
                // Span the whole measure so every tint shares the same edges, whatever the paragraph's rag.
                let measure = textContainer?.size.width ?? text.width
                let box = NSRect(x: o.x - 12, y: text.minY - 5, width: measure + 24, height: text.height + 10)
                guard box.intersects(dirty) else { continue }
                Theme.hitFill(current: current).setFill()
                NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).fill()
            case .unsure:
                let width: CGFloat = current ? 8 : 6
                let bar = NSRect(x: text.minX - 20 - width, y: text.minY + 1, width: width, height: text.height - 2).insetBy(dx: 0.75, dy: 0.75)
                guard bar.insetBy(dx: -4, dy: -4).intersects(dirty) else { continue }
                Theme.hitInk.setStroke()
                let path = NSBezierPath(roundedRect: bar, xRadius: 2.5, yRadius: 2.5); path.lineWidth = 1.5; path.stroke()
            case .nothing: break
            }
        }
    }
}

struct PageView: NSViewRepresentable {
    let mock: Mock
    var onMarks: ([StripMark]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var view: PageTextView?; var lastJump = 0; var lastWidth: CGFloat = 0 }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor
        let view = PageTextView(usingTextLayoutManager: true)
        view.isEditable = false; view.isSelectable = true; view.drawsBackground = false
        view.isVerticallyResizable = true; view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.isAutomaticLinkDetectionEnabled = false
        scroll.documentView = view
        context.coordinator.view = view
        view.onLayout = onMarks
        load(view)
        view.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: view, queue: .main) { _ in
            MainActor.assumeIsolated { view.relayout() }
        }
        return scroll
    }

    private func load(_ view: PageTextView) {
        let out = NSMutableAttributedString()
        func add(_ string: String, font: NSFont, color: NSColor = .labelColor, lineSpacing: CGFloat, after: CGFloat, before: CGFloat = 0) -> NSRange {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = lineSpacing; style.paragraphSpacing = after; style.paragraphSpacingBefore = before
            let start = out.length
            out.append(NSAttributedString(string: string + "\n", attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style]))
            return NSRange(location: start, length: out.length - start)
        }
        _ = add(mock.articleTitle, font: Theme.serif(28, weight: .semibold), lineSpacing: 3, after: 8)
        view.bylineRange = add("Simon Willison · 31 December 2024 · Open Original (14 images)", font: .systemFont(ofSize: 12), color: .secondaryLabelColor, lineSpacing: 0, after: 40)
        var ranges: [(Int, NSRange)] = []
        for block in mock.blocks {
            let r = block.kind == .heading
                ? add(block.text, font: Theme.serif(20, weight: .semibold), lineSpacing: 3, after: 8, before: 14)
                : add(block.text, font: Theme.serif(17), lineSpacing: 5.5, after: 14)
            ranges.append((block.id, r))
        }
        view.blockRanges = ranges.map { (id: $0.0, range: $0.1) }
        view.bands = mock.saturated ? [:] : Dictionary(uniqueKeysWithValues: mock.blocks.filter { $0.kind == .body }.map { ($0.id, $0.band) })
        view.textStorage?.setAttributedString(out)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { view.relayout() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { view.relayout() }
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = context.coordinator.view else { return }
        let width = scroll.contentSize.width
        if abs(width - context.coordinator.lastWidth) > 0.5 {
            context.coordinator.lastWidth = width
            DispatchQueue.main.async { view.relayout() }
        }
        view.currentID = mock.currentHit.map { mock.hits[$0] }
        view.needsDisplay = true
        if mock.jumpRequest != context.coordinator.lastJump, let id = view.currentID, let target = view.rect(for: id) {
            context.coordinator.lastJump = mock.jumpRequest
            let y = max(target.minY - scroll.contentSize.height * 0.30, 0)   // land the paragraph top at 30% of the viewport
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.3
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                scroll.contentView.animator().setBoundsOrigin(NSPoint(x: 0, y: y))
            }
        }
    }
}

/// A mouse-only map: invisible unless there are marks.
struct Strip: View {
    let marks: [StripMark]
    let currentID: Int?
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                ForEach(marks) { m in
                    let current = m.id == currentID
                    Group {
                        if m.band == .found {
                            RoundedRectangle(cornerRadius: 1.5).fill(Color(nsColor: Theme.hitInk))
                                .frame(width: current ? 10 : 6, height: max(m.height * geo.size.height, 3))
                        } else {
                            RoundedRectangle(cornerRadius: 2).strokeBorder(Color(nsColor: Theme.hitInk), lineWidth: 1.5)
                                .frame(width: current ? 10 : 8, height: max(m.height * geo.size.height, 6))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .offset(y: m.top * geo.size.height)
                }
            }
        }
        .frame(width: 12)
        .accessibilityHidden(true)
    }
}

struct ReaderPane: View {
    @Bindable var mock: Mock
    @State private var marks: [StripMark] = []

    var body: some View {
        PageView(mock: mock) { marks = $0 }
            .overlay(alignment: .trailing) {
                Strip(marks: marks, currentID: mock.currentHit.map { mock.hits[$0] }).padding(.trailing, 18).padding(.vertical, 8)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { foot }
    }

    private var status: String {
        if mock.saturated { return "Most of this article is about this." }
        if let i = mock.currentHit, mock.blocks.first(where: { $0.id == mock.hits[i] })?.band == .unsure { return "Unsure. Read this yourself." }
        return "\(mock.foundCount) found, \(mock.unsureCount) unsure"
    }

    private var foot: some View {
        HStack(spacing: 6) {
            Text(status).foregroundStyle(.secondary)
            if mock.saturated {
                Button("Find something narrower.") {}.buttonStyle(.plain).foregroundStyle(Color.accentColor)
                    .help("150 of 159 paragraphs")
            }
            Spacer()
            if let i = mock.currentHit {
                Text("\(i + 1) of \(mock.hits.count)").foregroundStyle(.secondary).monospacedDigit()
                ControlGroup {
                    Button { mock.step(-1) } label: { Image(systemName: "chevron.left") }.help("Find Previous")
                    Button { mock.step(1) } label: { Image(systemName: "chevron.right") }.help("Find Next")
                }.controlSize(.small).fixedSize()
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 16).frame(height: 30)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(alignment: .top) { Divider() }
    }
}
