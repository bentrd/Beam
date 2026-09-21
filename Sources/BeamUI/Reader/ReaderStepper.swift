import AppKit
import SwiftUI

/// The counter's chevrons: a small momentary segmented control, as the system find bar has.
///
/// It looks small (20 pt) but is hit like a 24 pt control: the host view is 24 pt tall and hands clicks
/// in the slivers above and below to the control.
struct ReaderStepper: NSViewRepresentable {
    let isEnabled: Bool
    var onPrevious: () -> Void
    var onNext: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> ReaderStepperHost {
        let images = [(name: "chevron.left", label: ReaderCopy.findPrevious), (name: "chevron.right", label: ReaderCopy.findNext)]
            .compactMap { NSImage(systemSymbolName: $0.name, accessibilityDescription: $0.label) }
        let control = NSSegmentedControl(images: images, trackingMode: .momentary, target: context.coordinator, action: #selector(Coordinator.stepped(_:)))
        control.controlSize = .small
        control.segmentDistribution = .fillEqually
        for (segment, help) in [ReaderCopy.findPrevious, ReaderCopy.findNext].enumerated() where segment < control.segmentCount {
            control.setToolTip(help, forSegment: segment)
        }
        return ReaderStepperHost(control: control)
    }

    func updateNSView(_ host: ReaderStepperHost, context: Context) {
        context.coordinator.onPrevious = onPrevious
        context.coordinator.onNext = onNext
        host.control.isEnabled = isEnabled
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView host: ReaderStepperHost, context: Context) -> CGSize? {
        host.intrinsicContentSize
    }

    @MainActor
    final class Coordinator: NSObject {
        var onPrevious: () -> Void = {}
        var onNext: () -> Void = {}

        @objc func stepped(_ control: NSSegmentedControl) {
            control.selectedSegment == 0 ? onPrevious() : onNext()
        }
    }
}

final class ReaderStepperHost: NSView {
    let control: NSSegmentedControl
    static let hitHeight: CGFloat = 24

    init(control: NSSegmentedControl) {
        self.control = control
        super.init(frame: .zero)
        addSubview(control)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("ReaderStepperHost is created in code only") }

    override var intrinsicContentSize: NSSize {
        NSSize(width: control.intrinsicContentSize.width, height: max(Self.hitHeight, control.intrinsicContentSize.height))
    }

    override func layout() {
        super.layout()
        let size = control.intrinsicContentSize
        control.frame = NSRect(x: 0, y: ((bounds.height - size.height) / 2).rounded(), width: bounds.width, height: size.height)
    }

    /// The whole 24 pt height answers for the control.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview, bounds.contains(convert(point, from: superview)) else { return nil }
        return self
    }

    /// The control tracks the mouse itself; it only needs the click to start inside it.
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let inside = NSPoint(x: min(max(point.x, control.frame.minX + 1), control.frame.maxX - 1), y: control.frame.midY)
        guard control.isEnabled,
              let moved = NSEvent.mouseEvent(with: event.type, location: convert(inside, to: nil), modifierFlags: event.modifierFlags,
                                             timestamp: event.timestamp, windowNumber: event.windowNumber, context: nil,
                                             eventNumber: event.eventNumber, clickCount: event.clickCount, pressure: event.pressure)
        else { return }
        control.mouseDown(with: moved)
    }
}
