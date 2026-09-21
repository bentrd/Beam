import AppKit

/// Space in the list pages the open article. `ReaderController` has no paging call, so the shell finds the reader's
/// text view itself: the one read-only, selectable `NSTextView` of the main window that is not a field editor.
@MainActor
enum ReaderScrollBridge {
    static func page(up: Bool) {
        guard let root = (NSApp.mainWindow ?? NSApp.keyWindow)?.contentView, let page = articleTextView(in: root) else { return }
        if up { page.scrollPageUp(nil) } else { page.scrollPageDown(nil) }
    }

    private static func articleTextView(in view: NSView) -> NSTextView? {
        if let text = view as? NSTextView, !text.isFieldEditor, !text.isEditable, text.isSelectable { return text }
        for child in view.subviews {
            if let found = articleTextView(in: child) { return found }
        }
        return nil
    }
}
