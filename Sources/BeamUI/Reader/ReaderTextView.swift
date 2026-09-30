import AppKit
import BeamModels

/// The page: a TextKit 2 text view that paints Beam's marks behind the text.
///
/// Marks are drawn in `drawBackground`, below the glyphs and below the selection, so native selection, lookup,
/// copy and VoiceOver behave exactly as in any text view. The exact text rect of every passage is cached once per
/// layout pass; drawing, the strip, jumps and the viewport report all read that cache and never lay out text.
final class ReaderTextView: NSTextView {
    /// The layout cache was rebuilt or the page was replaced: the strip and the viewport report are stale.
    var onLayout: (() -> Void)?
    /// Marks changed strength or shape without moving: only the strip needs to repaint.
    var onMarksDisplay: (() -> Void)?

    private(set) var document: ReaderDocument?
    private(set) var plan = ReaderMarkPlan.empty
    var highlightColor = HighlightColor.yellow {
        didSet { if highlightColor != oldValue { refreshSystemColors() } }
    }
    private var metrics = ReaderMetrics(textSize: ReaderTextSize.standard)

    // Layout cache, in text-container coordinates.
    private var frames: [Int: CGRect] = [:]
    private var bylineFrame: CGRect?
    private var cachedLayout: LayoutKey?
    private var generation = 0

    // Marks
    private var layers: [Int: ReaderMarkLayer] = [:]
    private var fading: Set<Int> = []
    private var currentPassage: Int?
    private var waitingPlan: ReaderMarkPlan?
    private var lastApplied: CFTimeInterval = 0
    private var applyTimer: Timer?
    private var fadeTimer: Timer?
    private let helpTags = ReaderHelpTags()

    private struct LayoutKey: Equatable { let generation: Int; let width: CGFloat }

    /// Judgments land on this beat rather than one by one, so the page settles in calm steps.
    private static let applyInterval: CFTimeInterval = 0.1

    // MARK: Loading

    /// Replaces the page. The storage is set once here and never touched again.
    func load(_ document: ReaderDocument?, metrics: ReaderMetrics) {
        self.document = document
        self.metrics = metrics
        generation += 1
        frames.removeAll()
        bylineFrame = nil
        layers.removeAll()
        fading.removeAll()
        plan = .empty
        waitingPlan = nil
        currentPassage = nil
        applyTimer?.invalidate()
        applyTimer = nil
        textStorage?.setAttributedString(document?.text ?? NSAttributedString())
        setAccessibilityLabel(document?.identity.phase == .loading ? "Loading article" : nil)
        setSelectedRange(NSRange(location: 0, length: 0))
        relayout()
    }

    // MARK: Layout

    /// Centres the measure, then caches the text rect of every passage. Runs from the frame-change handler,
    /// so the cache is rebuilt exactly when the layout can have changed: a new page or a new width.
    func relayout() {
        applyMeasure()
        guard let container = textContainer, container.size.width > 1 else { return }
        let key = LayoutKey(generation: generation, width: container.size.width)
        if key != cachedLayout {
            cachedLayout = key
            cacheFrames()
        }
        rebuildHelpTags()
        needsDisplay = true
        onLayout?()
    }

    /// A 66-character measure, centred, with room on both sides for the mark slot and the strip.
    private func applyMeasure() {
        guard let width = enclosingScrollView?.contentSize.width, width > 0 else { return }
        let side = max(((width - metrics.measure) / 2).rounded(.down), metrics.sideMinimum)
        let inset = NSSize(width: side, height: metrics.topInset)
        if inset != textContainerInset { textContainerInset = inset }
    }

    /// Exact text rects from line fragments: they exclude paragraph spacing, so tint outsets are even on every side.
    private func cacheFrames() {
        frames.removeAll()
        bylineFrame = nil
        guard let document, let layoutManager = textLayoutManager, let content = layoutManager.textContentManager else { return }
        let blocks = document.blocks
        let documentStart = layoutManager.documentRange.location
        var cursor = 0
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        layoutManager.enumerateTextLayoutFragments(from: documentStart, options: [.ensuresLayout]) { fragment in
            var rect = CGRect.null
            let frame = fragment.layoutFragmentFrame
            // The document's last paragraph carries an empty extra line after its newline; it is not text.
            for line in fragment.textLineFragments where line.characterRange.length > 0 {
                rect = rect.union(line.typographicBounds.offsetBy(dx: frame.minX, dy: frame.minY))
            }
            guard !rect.isNull else { return true }
            let start = content.offset(from: documentStart, to: fragment.rangeInElement.location)
            if let byline = document.bylineRange, NSLocationInRange(start, byline) { self.bylineFrame = rect }
            // Fragments and blocks are both in document order, so one cursor walks them together.
            while cursor < blocks.count, NSMaxRange(blocks[cursor].range) <= start { cursor += 1 }
            if cursor < blocks.count, NSLocationInRange(start, blocks[cursor].range) {
                let index = blocks[cursor].passageIndex
                self.frames[index] = self.frames[index]?.union(rect) ?? rect
            }
            return true
        }
    }

    private var geometry: ReaderMarkGeometry {
        ReaderMarkGeometry(metrics: metrics, origin: textContainerOrigin, measure: textContainer?.size.width ?? metrics.measure)
    }

    /// Where the body begins, just under the header's hairline, in view coordinates. Nil for a page without a byline
    /// or before the first layout pass.
    var bodyTop: CGFloat? {
        bylineFrame.map { geometry.textRect($0).maxY + metrics.hairlineOffset + 1 }
    }

    /// Decorative body lines in page coordinates. They never enter text storage, selection or passage judgments.
    var loadingBodyLines: [NSRect] {
        guard document?.identity.phase == .loading, let bodyTop else { return [] }
        let origin = textContainerOrigin
        let measure = textContainer?.size.width ?? metrics.measure
        let patterns: [[CGFloat]] = [[0.96, 1, 0.91, 0.58], [1, 0.88, 0.96, 0.70], [0.94, 1, 0.64]]
        let height = max(8, metrics.textSize * 0.65)
        var y = bodyTop + metrics.bodyLeading * 0.6
        var lines: [NSRect] = []
        for paragraph in patterns {
            for width in paragraph {
                lines.append(NSRect(x: origin.x, y: y, width: measure * width, height: height))
                y += metrics.bodyLeading
            }
            y += metrics.paragraphSpacing
        }
        return lines
    }

    /// The text rect of a passage in view coordinates, from the cache.
    func textRect(ofPassage index: Int) -> NSRect? { frames[index].map(geometry.textRect) }

    /// The judgeable passages on screen, for judging the viewport first.
    func visibleJudgeablePassages() -> ClosedRange<Int>? {
        guard let document else { return nil }
        let visible = visibleRect.offsetBy(dx: -textContainerOrigin.x, dy: -textContainerOrigin.y)
        var first: Int?
        var last: Int?
        for block in document.blocks where block.isJudgeable {
            guard let frame = frames[block.passageIndex], frame.maxY >= visible.minY else { continue }
            if frame.minY > visible.maxY { break }
            first = first ?? block.passageIndex
            last = block.passageIndex
        }
        guard let first, let last else { return nil }
        return first...last
    }

    /// The first passage on screen and how far its top is from the top of the viewport,
    /// so a change of text size can keep the reader's place.
    func readingAnchor() -> (passage: Int, offset: CGFloat)? {
        guard let document else { return nil }
        let visible = visibleRect
        for block in document.blocks {
            guard let rect = textRect(ofPassage: block.passageIndex), rect.maxY > visible.minY else { continue }
            return (block.passageIndex, rect.minY - visible.minY)
        }
        return nil
    }

    // MARK: Marks

    /// Takes the marks a snapshot asks for. A new sentence (or article) repaints at once, from the cache as it were;
    /// within one sentence, changes wait for the next 100 ms beat and then fade.
    func show(_ newPlan: ReaderMarkPlan) {
        if newPlan.sentenceKey != plan.sentenceKey {
            waitingPlan = nil
            apply(newPlan, animated: false)
            return
        }
        guard newPlan != plan || waitingPlan != nil else { return }
        waitingPlan = newPlan
        guard applyTimer == nil else { return }
        let wait = max(lastApplied + Self.applyInterval - CACurrentMediaTime(), 0)
        let timer = Timer(timeInterval: wait, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyWaitingPlan() }
        }
        RunLoop.main.add(timer, forMode: .common)
        applyTimer = timer
    }

    private func applyWaitingPlan() {
        applyTimer = nil
        guard let next = waitingPlan else { return }
        waitingPlan = nil
        apply(next, animated: true)
    }

    private func apply(_ newPlan: ReaderMarkPlan, animated: Bool) {
        let now = CACurrentMediaTime()
        lastApplied = now
        if !animated {
            // A different sentence: the old marks go at once, whatever they were doing.
            layers.removeAll()
            fading.removeAll()
            currentPassage = nil
            needsDisplay = true
        }
        let touched = animated ? Set(plan.marks.keys).union(newPlan.marks.keys) : Set(newPlan.marks.keys)
        for index in touched {
            let mark = newPlan.marks[index] ?? .none
            if animated, mark == plan.marks[index] ?? .none { continue }
            var layer = layers[index] ?? ReaderMarkLayer()
            layer.show(mark, animated: animated, now: now)
            store(layer, at: index, now: now)
        }
        plan = newPlan
        rebuildHelpTags()
        startFadeTimerIfNeeded()
        onMarksDisplay?()
    }

    /// The current hit steps to its stronger state and keeps it; it is not a pulse.
    func setCurrent(_ passage: Int?, animated: Bool) {
        guard passage != currentPassage else { return }
        let now = CACurrentMediaTime()
        for (index, isCurrent) in [(currentPassage, false), (passage, true)] {
            guard let index else { continue }
            var layer = layers[index] ?? ReaderMarkLayer()
            layer.setCurrent(isCurrent, animated: animated, now: now)
            store(layer, at: index, now: now)
        }
        currentPassage = passage
        startFadeTimerIfNeeded()
        onMarksDisplay?()
    }

    private func store(_ layer: ReaderMarkLayer, at index: Int, now: CFTimeInterval) {
        if layer.isSpent(at: now) { layers[index] = nil } else { layers[index] = layer }
        if layer.isActive(at: now) { fading.insert(index) }
        invalidateMarks(ofPassage: index)
    }

    private func invalidateMarks(ofPassage index: Int) {
        guard let rect = textRect(ofPassage: index) else { return }
        setNeedsDisplay(geometry.damage(for: rect))
    }

    // MARK: Fading

    /// One timer serves every fade and stops with the last one. Each beat repaints only the paragraphs still fading.
    private func startFadeTimerIfNeeded() {
        guard fadeTimer == nil, !fading.isEmpty else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.fadeBeat() }
        }
        RunLoop.main.add(timer, forMode: .common)
        fadeTimer = timer
    }

    private func fadeBeat() {
        let now = CACurrentMediaTime()
        for index in fading {
            // The beat after a fade ends still repaints once, so the final strength is what stays on screen.
            invalidateMarks(ofPassage: index)
            guard layers[index]?.isActive(at: now) != true else { continue }
            fading.remove(index)
            if layers[index]?.isSpent(at: now) == true { layers[index] = nil }
        }
        onMarksDisplay?()
        if fading.isEmpty {
            fadeTimer?.invalidate()
            fadeTimer = nil
        }
    }

    // MARK: Drawing

    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        let geometry = self.geometry
        drawHairline(geometry, in: dirtyRect)
        let now = CACurrentMediaTime()
        let isDark = ReaderTheme.isDark(effectiveAppearance)
        let raised = ReaderContrast.isRaised
        for (index, layer) in layers {
            guard let cached = frames[index] else { continue }
            let text = geometry.textRect(cached)
            guard geometry.damage(for: text).intersects(dirtyRect) else { continue }
            drawHit(layer, text: text, geometry: geometry, now: now, isDark: isDark, raised: raised)
            drawRail(layer, text: text, geometry: geometry, now: now, raised: raised)
        }
    }

    /// The header's rule is drawn, never a character: it must not select, copy or be read.
    private func drawHairline(_ geometry: ReaderMarkGeometry, in dirtyRect: NSRect) {
        guard let bylineFrame else { return }
        let byline = geometry.textRect(bylineFrame)
        let rule = backingAlignedRect(NSRect(x: geometry.origin.x, y: byline.maxY + metrics.hairlineOffset, width: geometry.measure, height: 1),
                                      options: .alignAllEdgesNearest)
        guard rule.intersects(dirtyRect) else { return }
        NSColor.separatorColor.setFill()
        rule.fill(using: .sourceOver)
    }

    private func drawHit(_ layer: ReaderMarkLayer, text: NSRect, geometry: ReaderMarkGeometry, now: CFTimeInterval, isDark: Bool, raised: Bool) {
        let opacity = layer.hitOpacity.value(at: now)
        let emphasis = layer.emphasis.value(at: now)
        switch layer.hit {
        case .found:
            withOpacity(opacity) {
                let box = backingAlignedRect(geometry.tint(for: text), options: .alignAllEdgesNearest)
                ReaderTheme.hitFill(alpha: ReaderTheme.hitFillAlpha(emphasis: emphasis, isDark: isDark), color: highlightColor).setFill()
                NSBezierPath(roundedRect: box, xRadius: metrics.tintRadius, yRadius: metrics.tintRadius).fill()
                guard raised else { return }
                // Without colour a pale fill is barely a shape; the outline makes it one (1 pt, 2 pt when current).
                let width: CGFloat = 1 + emphasis
                let outline = NSBezierPath(roundedRect: box.insetBy(dx: width / 2, dy: width / 2), xRadius: metrics.tintRadius, yRadius: metrics.tintRadius)
                outline.lineWidth = width
                ReaderTheme.hitInk(highlightColor).setStroke()
                outline.stroke()
            }
        case .unsure:
            // The bar widens by cross-fading two bars: motion stays opacity only.
            withOpacity(opacity * (1 - emphasis)) { strokeBar(geometry.bar(for: text, current: false)) }
            withOpacity(opacity * emphasis) { strokeBar(geometry.bar(for: text, current: true)) }
        case .none, .pending, .unchecked:
            break
        }
    }

    private func strokeBar(_ rect: NSRect) {
        let lineWidth: CGFloat = 1.5
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2), xRadius: 2.5, yRadius: 2.5)
        path.lineWidth = lineWidth
        ReaderTheme.hitInk(highlightColor).setStroke()
        path.stroke()
    }

    private func drawRail(_ layer: ReaderMarkLayer, text: NSRect, geometry: ReaderMarkGeometry, now: CFTimeInterval, raised: Bool) {
        withOpacity(layer.railOpacity.value(at: now)) {
            let settled = layer.rail == .unchecked
            let rail = backingAlignedRect(geometry.rail(for: text, weight: settled ? 2 : 1), options: .alignAllEdgesNearest)
            (settled ? ReaderContrast.settledRail(raised: raised) : ReaderContrast.pendingRail(raised: raised)).setFill()
            NSBezierPath(roundedRect: rail, xRadius: rail.width / 2, yRadius: rail.width / 2).fill()
        }
    }

    /// Opacity is applied by the context, so system colours keep resolving for the current appearance.
    private func withOpacity(_ opacity: CGFloat, _ draw: () -> Void) {
        guard opacity > 0, let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.setAlpha(opacity)
        draw()
        context.restoreGState()
    }

    // MARK: The strip's view of the page

    /// Marks as the strip needs them: positions true to layout, as fractions of the document's height.
    func stripEntries() -> [ReaderStripEntry] {
        let height = max(bounds.height, 1)
        let now = CACurrentMediaTime()
        return layers.compactMap { index, layer in
            guard let rect = textRect(ofPassage: index) else { return nil }
            return ReaderStripEntry(passage: index, top: rect.minY / height, height: rect.height / height,
                                    hit: layer.hit, hitOpacity: layer.hitOpacity.value(at: now),
                                    isSettledRail: layer.rail == .unchecked, railOpacity: layer.railOpacity.value(at: now),
                                    emphasis: layer.emphasis.value(at: now))
        }
    }

    // MARK: Help tags

    /// "Unsure. Read this yourself." and "Not checked", over the full slot by the paragraph's height.
    /// Waiting rails get none: they are gone before a help tag could appear.
    private func rebuildHelpTags() {
        helpTags.removeAll(from: self)
        let geometry = self.geometry
        for (index, mark) in plan.marks where mark == .unsure || mark == .unchecked {
            guard let cached = frames[index] else { continue }
            helpTags.add(mark == .unsure ? ReaderCopy.unsure : ReaderCopy.notChecked, over: geometry.slot(for: geometry.textRect(cached)), to: self)
        }
    }

    // MARK: Accessibility

    private lazy var rotors = ReaderRotors(textView: self)

    override func accessibilityCustomRotors() -> [NSAccessibilityCustomRotor] {
        super.accessibilityCustomRotors() + rotors.rotors
    }

    // MARK: The literal text finder never appears

    override func performFindPanelAction(_ sender: Any?) {}
    override func performTextFinderAction(_ sender: Any?) {}

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        let finderActions = [#selector(performFindPanelAction(_:)), #selector(performTextFinderAction(_:))]
        if let action = item.action, finderActions.contains(action) { return false }
        return super.validateUserInterfaceItem(item)
    }

    // MARK: Appearance

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshSystemColors()
    }

    /// Accent, highlight and contrast settings can change while the page is open.
    func refreshSystemColors() {
        selectedTextAttributes = ReaderSelection.attributes(highlightColor: highlightColor)
        needsDisplay = true
        onMarksDisplay?()
    }
}

/// One mark as the strip draws it. `top` and `height` are fractions of the document's height.
struct ReaderStripEntry {
    let passage: Int
    let top: CGFloat
    let height: CGFloat
    let hit: ReaderMark
    let hitOpacity: CGFloat
    let isSettledRail: Bool
    let railOpacity: CGFloat
    let emphasis: CGFloat
}

/// Owns the margin slot's help tags. A separate owner keeps them apart from any tool tips the text view makes itself.
private final class ReaderHelpTags: NSObject, NSViewToolTipOwner {
    private var strings: [NSView.ToolTipTag: String] = [:]

    func add(_ string: String, over rect: NSRect, to view: NSView) {
        strings[view.addToolTip(rect, owner: self, userData: nil)] = string
    }

    func removeAll(from view: NSView) {
        strings.keys.forEach(view.removeToolTip)
        strings.removeAll()
    }

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        strings[tag] ?? ""
    }
}
