import AppKit
import BeamModels
import SwiftUI

/// The page inside SwiftUI. It is given plain values only (the controller's state is read in `ReaderPane.body`),
/// so SwiftUI sees every change that should reach the text view.
struct ReaderPage: NSViewRepresentable {
    struct Commands: Equatable {
        /// The passage the current hit points at, or nil before the first jump.
        var currentPassage: Int?
        /// Position among the hits, for the jump announcement ("2 of 5").
        var currentPosition: Int?
        var hits: [Int] = []
        var hitJumps = 0
        var jumps = 0
        var page = ReaderController.PageRequest()
        /// Bumped when the ask field closes, to hand the keyboard back to the page.
        var focusRequests = 0
    }

    let snapshot: ReaderSnapshot?
    let textSize: CGFloat
    let commands: Commands
    let controller: ReaderController
    let actions: ReaderActions

    func makeCoordinator() -> ReaderPageCoordinator { ReaderPageCoordinator(controller: controller, commands: commands) }

    func makeNSView(context: Context) -> ReaderPageView { context.coordinator.pageView }

    func updateNSView(_ view: ReaderPageView, context: Context) {
        context.coordinator.update(snapshot: snapshot, textSize: textSize, commands: commands, controller: controller, actions: actions)
    }

    static func dismantleNSView(_ view: ReaderPageView, coordinator: ReaderPageCoordinator) {
        coordinator.tearDown()
    }
}

/// Drives the AppKit page from snapshots and commands: loads documents, applies marks, performs jumps,
/// reports the viewport and relays what the text view tells it.
@MainActor
final class ReaderPageCoordinator: NSObject, NSTextViewDelegate {
    let pageView = ReaderPageView()

    private var controller: ReaderController
    private var actions = ReaderActions()
    private var commands: ReaderPage.Commands
    private var snapshot: ReaderSnapshot?
    private var identity: ReaderDocument.Identity?
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    private var isUpdating = false
    private var jumpInFlight = 0
    private var reportedViewport: ClosedRange<Int>?
    private var viewportTimer: Timer?

    private static let jumpDuration: TimeInterval = 0.3
    /// Where a jump lands the paragraph's top, as a share of the viewport's height.
    private static let landing: CGFloat = 0.30
    private static let viewportDebounce: TimeInterval = 0.15

    private var textView: ReaderTextView { pageView.textView }
    private var scrollView: NSScrollView { pageView.scrollView }

    init(controller: ReaderController, commands: ReaderPage.Commands) {
        self.controller = controller
        // Start from the controller's present counts so that jumps made before this page existed are not replayed.
        self.commands = commands
        super.init()
        textView.delegate = self
        textView.onLayout = { [weak self] in
            self?.pageView.strip.needsDisplay = true
            self?.viewportMayHaveChanged(after: 0)
        }
        textView.onMarksDisplay = { [weak self] in self?.pageView.strip.needsDisplay = true }
        pageView.strip.onJump = { [weak self] passage in self?.stripClicked(passage) }
        observe()
    }

    // MARK: Updates from SwiftUI

    func update(snapshot: ReaderSnapshot?, textSize: CGFloat, commands new: ReaderPage.Commands, controller: ReaderController, actions: ReaderActions) {
        isUpdating = true
        defer { isUpdating = false }
        self.controller = controller
        self.actions = actions
        self.snapshot = snapshot
        let old = commands
        commands = new

        let shownSentence = textView.plan.sentenceKey
        let didLoad = loadIfNeeded(snapshot, metrics: ReaderMetrics(textSize: textSize))
        let plan = snapshot.map(ReaderMarkPlan.init(snapshot:)) ?? .empty
        textView.show(plan)

        // The pane clears the current hit when the sentence changes, but only after this update: until then the old
        // position belongs to the old sentence and must not be shown on the new marks.
        let current = plan.sentenceKey == shownSentence ? new.currentPassage : nil
        if new.hitJumps != old.hitJumps, let current {
            jump(to: current)
        } else if jumpInFlight == 0 {
            // A page rebuilt for a new text size shows its current hit at once; it did not just become current.
            textView.setCurrent(current, animated: !didLoad)
        }
        if new.jumps - old.jumps > new.hitJumps - old.hitJumps { textView.centerSelectionInVisibleArea(nil) }
        if new.page != old.page { new.page.isDown ? textView.pageDown(nil) : textView.pageUp(nil) }
        if new.focusRequests != old.focusRequests { pageView.window?.makeFirstResponder(textView) }
    }

    func tearDown() {
        viewportTimer?.invalidate()
        observers.forEach { $0.center.removeObserver($0.token) }
        observers.removeAll()
    }

    /// A new document is needed for a new article, phase or text size; never for judgments. Returns whether one was loaded.
    private func loadIfNeeded(_ snapshot: ReaderSnapshot?, metrics: ReaderMetrics) -> Bool {
        let newIdentity = snapshot.map { ReaderDocument.identity(for: $0, metrics: metrics) }
        guard newIdentity != identity else { return false }
        let old = identity
        identity = newIdentity
        // Only the text size changed: keep the reader's place and do not replay the body's arrival.
        let isRestyle = old != nil && old?.itemID == newIdentity?.itemID && old?.phase == newIdentity?.phase && old?.passages == newIdentity?.passages
        let anchor = isRestyle ? textView.readingAnchor() : nil
        textView.load(snapshot.map { ReaderDocument(snapshot: $0, metrics: metrics) }, metrics: metrics)
        if let anchor, let rect = textView.textRect(ofPassage: anchor.passage) {
            scroll(toY: rect.minY - anchor.offset, animated: false)
        } else if !isRestyle {
            scroll(toY: -scrollView.contentInsets.top, animated: false)
            // The title and byline are already where they will stay; only the body arrives.
            if snapshot?.phase == .ready, let top = textView.bodyTop {
                pageView.fadeInBody(below: pageView.convert(NSPoint(x: 0, y: top), from: textView).y)
            }
        }
        reportedViewport = nil
        return true
    }

    // MARK: Jumps

    /// An animated scroll that lands the paragraph's top at 30% of the viewport; the current state steps in on landing.
    /// The article never scrolls by itself: this runs only for Find Next, Find Previous and a click on the strip.
    private func jump(to passage: Int) {
        guard let rect = textView.textRect(ofPassage: passage) else {
            textView.setCurrent(passage, animated: true)
            return
        }
        jumpInFlight += 1
        let flight = jumpInFlight
        textView.setCurrent(nil, animated: true)
        let insets = scrollView.contentInsets
        let viewport = scrollView.contentView.bounds.height - insets.top - insets.bottom
        let animated = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        scroll(toY: rect.minY - viewport * Self.landing - insets.top, animated: animated) { [weak self] in
            guard let self, flight == self.jumpInFlight else { return }
            self.jumpInFlight = 0
            self.land(on: passage)
        }
    }

    private func land(on passage: Int) {
        textView.setCurrent(commands.currentPassage, animated: true)
        guard commands.currentPassage == passage, let position = commands.currentPosition, let snapshot else { return }
        ReaderAnnouncer.announceJump(ReaderCopy.jumpAnnouncement(position + 1, of: commands.hits.count, band: snapshot.band(at: passage)))
        if let rect = textView.textRect(ofPassage: passage) { ReaderAnnouncer.moveZoomFocus(to: rect, in: textView) }
    }

    private func scroll(toY y: CGFloat, animated: Bool, completion: (() -> Void)? = nil) {
        let clip = scrollView.contentView
        let insets = scrollView.contentInsets
        let lowest = max(textView.frame.height - clip.bounds.height + insets.bottom, -insets.top)
        let target = NSPoint(x: clip.bounds.origin.x, y: min(max(y, -insets.top), lowest).rounded())
        guard animated, target != clip.bounds.origin else {
            clip.setBoundsOrigin(target)
            scrollView.reflectScrolledClipView(clip)
            completion?()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.jumpDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            clip.animator().setBoundsOrigin(target)
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                if let self { self.scrollView.reflectScrolledClipView(self.scrollView.contentView) }
                completion?()
            }
        })
    }

    private func stripClicked(_ passage: Int) {
        guard let index = commands.hits.firstIndex(of: passage) else { return }
        controller.jump(toHit: index)
    }

    // MARK: Viewport

    /// Tells the engine which judgeable passages are on screen so it can judge them first. Debounced, because a scroll
    /// produces a burst of changes, and always delivered on a later turn of the run loop, never inside a view update.
    private func viewportMayHaveChanged(after delay: TimeInterval) {
        guard identity?.phase == .ready else { return }
        viewportTimer?.invalidate()
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.reportViewport() }
        }
        RunLoop.main.add(timer, forMode: .common)
        viewportTimer = timer
    }

    private func reportViewport() {
        viewportTimer = nil
        guard let visible = textView.visibleJudgeablePassages(), visible != reportedViewport else { return }
        reportedViewport = visible
        actions.viewportChanged(visible.lowerBound, visible.upperBound)
    }

    // MARK: Notifications

    private func observe() {
        let clip = scrollView.contentView
        // The measure is applied here, from the frame change itself: waiting for the next SwiftUI update would
        // leave a resized window showing marks cached for the old width.
        add(.default, NSView.frameDidChangeNotification, textView) { $0.textView.relayout() }
        add(.default, NSView.frameDidChangeNotification, clip) { coordinator in
            coordinator.textView.relayout()
            coordinator.viewportMayHaveChanged(after: Self.viewportDebounce)
        }
        add(.default, NSView.boundsDidChangeNotification, clip) { $0.viewportMayHaveChanged(after: Self.viewportDebounce) }
        add(.default, NSColor.systemColorsDidChangeNotification, nil) { $0.textView.refreshSystemColors() }
        add(NSWorkspace.shared.notificationCenter, NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, nil) { $0.textView.refreshSystemColors() }
    }

    private func add(_ center: NotificationCenter, _ name: Notification.Name, _ object: Any?, _ handler: @escaping (ReaderPageCoordinator) -> Void) {
        let token = center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self { handler(self) } }
        }
        observers.append((center, token))
    }

    // MARK: NSTextViewDelegate

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        guard link as? String == ReaderDocument.openOriginalLink else { return false }
        actions.openOriginal()
        return true
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        let range = textView.selectedRange()
        let selected = range.length > 0 ? (textView.string as NSString).substring(with: range) : nil
        guard selected != controller.selectedText else { return }
        // Loading a document moves the selection during a SwiftUI update; observable state must not change under it.
        if isUpdating {
            DispatchQueue.main.async { [controller] in controller.selectedText = selected }
        } else {
            controller.selectedText = selected
        }
    }
}
