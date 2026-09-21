import AppKit
import SwiftUI

/// The toolbar's search field: the stock AppKit `NSSearchField`, so it looks and behaves like every other Mac search field.
/// It sends whole strings only, keeps no recents, offers no suggestions, and Writing Tools are off.
///
/// Return runs the sentence (or opens a row when the text is unchanged), Down moves to the list, Esc clears.
/// Return and Esc are left to the input system while there is marked text: AZERTY dead keys produce it.
struct SearchToolbarField: NSViewRepresentable {
    @Bindable var model: AppModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSSearchField {
        let field = FocusReportingSearchField()
        field.placeholderString = ShellCopy.searchPrompt
        field.sendsWholeSearchString = true
        field.sendsSearchStringImmediately = false
        field.maximumRecents = 0
        field.recentsAutosaveName = nil
        field.allowsWritingTools = false
        field.controlSize = .large
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.searchFieldSent(_:))
        field.onFocus = { [weak coordinator = context.coordinator] in coordinator?.model.isSearchFieldFocused = true }
        field.setAccessibilityLabel(ShellCopy.searchPrompt)
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        let isComposing = (field.currentEditor() as? NSTextView)?.hasMarkedText() ?? false
        if field.stringValue != model.fieldText, !isComposing { field.stringValue = model.fieldText }
        let coordinator = context.coordinator
        if coordinator.answeredFocusRequests != model.searchFocusRequests {
            coordinator.answeredFocusRequests = model.searchFocusRequests
            // The field may not be in its window yet when the first request arrives at launch.
            DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        let model: AppModel
        var answeredFocusRequests = 0

        init(model: AppModel) { self.model = model }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            model.fieldText = field.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) { model.isSearchFieldFocused = false }

        /// The clear button sends the action with an empty string. Return never gets here: `doCommandBy` takes it first.
        @objc func searchFieldSent(_ field: NSSearchField) {
            if field.stringValue.isEmpty { model.clearSearch() }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard !textView.hasMarkedText() else { return false }
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                model.fieldText = textView.string
                model.submitSearch()
                return true
            case #selector(NSResponder.moveDown(_:)):
                model.moveFocusToList()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                // Esc clears the sentence, and only from here: it never navigates.
                guard !textView.string.isEmpty || model.sentence != nil else { return false }
                model.clearSearch()
                return true
            default:
                return false
            }
        }
    }
}

/// `NSSearchField` tells its delegate when editing ends but not when focus arrives; the model needs both,
/// because a settled run selects the top row only while the field still has focus.
private final class FocusReportingSearchField: NSSearchField {
    var onFocus: (() -> Void)?

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocus?() }
        return accepted
    }
}
