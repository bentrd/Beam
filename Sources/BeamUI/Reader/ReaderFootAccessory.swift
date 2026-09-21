import AppKit
import SwiftUI

/// Hangs the reader's foot on the pane's split-view item, which is where DESIGN.md section 2 puts it: a bottom-aligned
/// accessory. The system then owns the band the foot sits in — it fits it to the window's rounded corners, keeps it
/// opaque and sizes it — instead of the reader laying a bar of its own over the page.
///
/// The view itself stands for nothing on screen. It goes in the pane's background, finds the item through the responder
/// chain, and says whether it found one: a reader that is not in a split view (the reader-demo window) has no item to
/// hang a foot on, and the pane then insets the foot itself.
struct ReaderFootAccessory: NSViewRepresentable {
    let foot: ReaderFoot
    /// Told whether the system is showing the foot now. Always delivered on a later turn, never inside a view update.
    var isAttached: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let anchor = AnchorView()
        anchor.onWindowChange = { [coordinator = context.coordinator] view in coordinator.attach(from: view) }
        return anchor
    }

    func updateNSView(_ view: NSView, context: Context) {
        let coordinator = context.coordinator
        coordinator.isAttached = isAttached
        coordinator.show(foot)
        coordinator.attach(from: view)
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.detach() }

    @MainActor
    final class Coordinator {
        var isAttached: (Bool) -> Void = { _ in }

        private var host: NSHostingController<ReaderFoot>?
        private var accessory: NSSplitViewItemAccessoryViewController?
        private var reported: Bool?

        /// The foot is rebuilt on every pane update; the accessory shows the newest one.
        func show(_ foot: ReaderFoot) {
            if let host { host.rootView = foot } else { host = NSHostingController(rootView: foot) }
        }

        /// Puts the accessory on the item the anchor sits in, and puts it back if a rebuilt split view dropped it.
        func attach(from view: NSView) {
            guard view.window != nil, let item = Self.splitViewItem(for: view), let host else { return report(false) }
            let accessory = accessory ?? make(hosting: host)
            if !item.bottomAlignedAccessoryViewControllers.contains(where: { $0 === accessory }) {
                item.addBottomAlignedAccessoryViewController(accessory)
            }
            report(true)
        }

        func detach() {
            accessory?.removeFromParent()
            accessory = nil
            host = nil
            report(false)
        }

        private func make(hosting host: NSHostingController<ReaderFoot>) -> NSSplitViewItemAccessoryViewController {
            let accessory = NSSplitViewItemAccessoryViewController()
            accessory.view = NSView()
            accessory.addChild(host)
            host.view.translatesAutoresizingMaskIntoConstraints = false
            accessory.view.addSubview(host.view)
            // The foot's own height (one line, two when the sentence wraps) sizes the accessory; the system adds the
            // insets that keep it clear of the window's corners.
            NSLayoutConstraint.activate([
                host.view.leadingAnchor.constraint(equalTo: accessory.view.leadingAnchor),
                host.view.trailingAnchor.constraint(equalTo: accessory.view.trailingAnchor),
                host.view.topAnchor.constraint(equalTo: accessory.view.topAnchor),
                host.view.bottomAnchor.constraint(equalTo: accessory.view.bottomAnchor),
            ])
            self.accessory = accessory
            return accessory
        }

        /// SwiftUI is mid-update whenever this is called from `updateNSView`, so the pane hears about it on a later turn.
        private func report(_ attached: Bool) {
            guard reported != attached else { return }
            reported = attached
            let tell = isAttached
            DispatchQueue.main.async { tell(attached) }
        }

        /// The pane is a SwiftUI column, so its split-view item is reachable only through the controller that carries it.
        private static func splitViewItem(for view: NSView) -> NSSplitViewItem? {
            var candidate: NSView? = view
            while let current = candidate {
                if let controller = current.nextResponder as? NSViewController,
                   let split = controller.parent as? NSSplitViewController,
                   let item = split.splitViewItem(for: controller) {
                    return item
                }
                candidate = current.superview
            }
            return nil
        }
    }
}

/// In the hierarchy only so the foot can find its split-view item: it draws nothing, catches nothing and is not read.
private final class AnchorView: NSView {
    var onWindowChange: (NSView) -> Void = { _ in }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange(self)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }
}
