import AppKit
import ApplicationServices
import BeamModels

/// VoiceOver's way to the marks. The page itself is a plain text view, so reading, selection and links come for free;
/// the marks are paint, so they are offered as two rotors: "Marked paragraphs" and, when a run settles with gaps, "Not checked".
final class ReaderRotors: NSObject, NSAccessibilityCustomRotorItemSearchDelegate {
    struct Entry {
        let range: NSRange
        let label: String
    }

    private weak var textView: ReaderTextView?
    private lazy var marked = NSAccessibilityCustomRotor(label: ReaderCopy.markedRotor, itemSearchDelegate: self)
    private lazy var notChecked = NSAccessibilityCustomRotor(label: ReaderCopy.notCheckedRotor, itemSearchDelegate: self)

    init(textView: ReaderTextView) { self.textView = textView }

    /// Only rotors with something in them are offered, so "Not checked" appears exactly when a run settled with gaps.
    var rotors: [NSAccessibilityCustomRotor] {
        var result: [NSAccessibilityCustomRotor] = []
        if !entries(where: \.isHit).isEmpty { result.append(marked) }
        if !entries(where: { $0 == .unchecked }).isEmpty { result.append(notChecked) }
        return result
    }

    func rotor(_ rotor: NSAccessibilityCustomRotor,
               resultFor parameters: NSAccessibilityCustomRotor.SearchParameters) -> NSAccessibilityCustomRotor.ItemResult? {
        guard let textView else { return nil }
        var candidates = rotor === marked ? entries(where: \.isHit) : entries(where: { $0 == .unchecked })
        if !parameters.filterString.isEmpty {
            candidates = candidates.filter { $0.label.localizedCaseInsensitiveContains(parameters.filterString) }
        }
        let here = parameters.currentItem.map(\.targetRange.location).flatMap { $0 == NSNotFound ? nil : $0 }
        let entry: Entry?
        switch parameters.searchDirection {
        case .previous: entry = candidates.last { here == nil || $0.range.location < (here ?? 0) }
        case .next: entry = candidates.first { here == nil || $0.range.location > (here ?? 0) }
        @unknown default: entry = nil
        }
        guard let entry else { return nil }
        let result = NSAccessibilityCustomRotor.ItemResult(targetElement: textView)
        result.targetRange = entry.range
        result.customLabel = entry.label
        return result
    }

    /// In reading order. Labels are "Found, {first words}" or "Unsure, {first words}"; a probability is never spoken.
    private func entries(where include: (ReaderMark) -> Bool) -> [Entry] {
        guard let textView, let document = textView.document else { return [] }
        let string = textView.string as NSString
        return document.blocks.compactMap { block in
            guard let mark = textView.plan.marks[block.passageIndex], include(mark), NSMaxRange(block.range) <= string.length else { return nil }
            let band: Band? = mark == .found ? .found : (mark == .unsure ? .unsure : nil)
            return Entry(range: block.range, label: ReaderCopy.rotorLabel(band: band, text: string.substring(with: block.range)))
        }
    }
}

/// Spoken and magnified feedback that has no visual of its own.
enum ReaderAnnouncer {
    /// Every jump says where it landed ("2 of 5, unsure"), over whatever VoiceOver was reading.
    static func announceJump(_ text: String) { post(text, priority: .high) }

    /// A run that settles is announced once and politely; counts never tick aloud.
    static func announceSettled(_ text: String) { post(text, priority: .medium) }

    private static func post(_ text: String, priority: NSAccessibilityPriorityLevel) {
        guard !text.isEmpty, let app = NSApp else { return }
        let element: Any = app.mainWindow ?? app
        NSAccessibility.post(element: element, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: priority.rawValue])
    }

    /// Moves Zoom's focus to a rect of `view`, so a magnified screen follows a jump the way it follows the insertion point.
    static func moveZoomFocus(to rect: NSRect, in view: NSView) {
        guard UAZoomEnabled(), let window = view.window, let screenHeight = NSScreen.screens.first?.frame.height else { return }
        let onScreen = window.convertToScreen(view.convert(rect, to: nil))
        // Universal Access measures from the top left of the main display.
        var focus = CGRect(x: onScreen.minX, y: screenHeight - onScreen.maxY, width: onScreen.width, height: onScreen.height)
        UAZoomChangeFocus(&focus, nil, UAZoomChangeFocusType(kUAZoomFocusTypeOther))
    }
}
