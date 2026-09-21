import AppKit
import SwiftUI

/// Find by Meaning's field: the stock search field, so it looks and behaves like every other one on the Mac.
///
/// Nothing is sent while typing. Return asks; a further Return with the same words walks to the next hit;
/// Esc, the clear button, or losing focus while empty closes the field.
struct ReaderAskField: NSViewRepresentable {
    /// What the field holds when it opens: the selection (Use Selection for Find), else the last question asked of
    /// this article, else nothing. It arrives selected, so typing replaces it. Read once, when the field is made.
    let openingText: String
    /// Use Selection for Find. A new value while the field is already open replaces its text.
    let prefill: String?
    var onAsk: (String) -> Void
    var onNext: () -> Void
    /// `returnsFocus` is true when the reader closed the field from the keyboard or its clear button, false when
    /// the field closed because the focus had already gone elsewhere.
    var onClose: (_ returnsFocus: Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSSearchField {
        let field = FocusingSearchField()
        field.placeholderString = ReaderCopy.askPlaceholder
        field.controlSize = .small
        field.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small))
        field.sendsWholeSearchString = true
        field.sendsSearchStringImmediately = false
        field.recentsAutosaveName = nil
        field.maximumRecents = 0
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.fieldActed(_:))
        field.stringValue = openingText
        context.coordinator.prefill = prefill
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        let coordinator = context.coordinator
        coordinator.onAsk = onAsk
        coordinator.onNext = onNext
        coordinator.onClose = onClose
        if prefill != coordinator.prefill {
            coordinator.prefill = prefill
            guard let prefill, !prefill.isEmpty else { return }
            coordinator.asked = nil
            field.stringValue = prefill
            field.selectText(nil)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var onAsk: (String) -> Void = { _ in }
        var onNext: () -> Void = {}
        var onClose: (Bool) -> Void = { _ in }
        var prefill: String?
        /// The question already asked since the field opened; Return on the same words means "next".
        var asked: String?
        private var isClosed = false

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            // A dead key (AZERTY's circumflex, for one) leaves marked text; Return and Esc then belong to the input method.
            guard !textView.hasMarkedText() else { return false }
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                let question = control.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !question.isEmpty else { return true }
                if question == asked { onNext() } else { asked = question; onAsk(question) }
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                close(returnsFocus: true)
                return true
            default:
                return false
            }
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            guard let editor = notification.userInfo?["NSFieldEditor"] as? NSTextView else { return }
            editor.writingToolsBehavior = .none
        }

        /// Losing focus while empty closes the field; losing it with a question leaves the field and its marks alone.
        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField, field.stringValue.isEmpty else { return }
            close(returnsFocus: false)
        }

        /// Return is handled above, so the only action left is the clear button.
        @objc func fieldActed(_ field: NSSearchField) {
            if field.stringValue.isEmpty { close(returnsFocus: true) }
        }

        private func close(returnsFocus: Bool) {
            guard !isClosed else { return }
            isClosed = true
            onClose(returnsFocus)
        }
    }
}

/// Takes the keyboard as soon as it is on screen, with its text selected, as a find field should.
private final class FocusingSearchField: NSSearchField {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window === window else { return }
            window.makeFirstResponder(self)
        }
    }
}
