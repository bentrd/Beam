import AppKit
import BeamModels
import Foundation

// The reader: previewing a selected row (nothing sent), opening it (marks it read, judges passages), and its commands.
extension AppModel {
    /// Title, snippet and "Return to read". Closes whatever article was open.
    func preview(_ id: Int64) {
        closeReader()
        readerSnapshot = backend.preview(itemID: id)
    }

    /// Return, Space, a click or a double click on a row. Opening carries the list's sentence into the article,
    /// and moves focus to the list so Space pages through it.
    public func open(_ id: Int64, trigger: OpenTrigger) {
        footOverride = nil
        if selectedItemID != id {
            selectedItemID = id
            preferences.lastItemID = id
        }
        if opensInBrowser(id) {
            // A YouTube row never opens on a single click: Return or a double click sends it to the browser.
            if readerSnapshot?.item.id != id || openItemID != nil { preview(id) }
            if trigger != .click { openInBrowser(id) }
            return
        }
        guard openItemID != id else {
            // Already open. A link that turned out to have no reader (it answered `.external`) still goes to the browser.
            if readerSnapshot?.phase == .external, trigger != .click { openInBrowser(id) }
            return
        }
        // The preview of this row stays up until the article's first snapshot replaces it: the title never blinks.
        closeReader(keepingSnapshotOf: id)
        openItemID = id
        focusRequest = .list
        let snapshots = backend.open(itemID: id, carrying: sentence)
        readerTask = Task { [weak self] in
            var hasLeftForBrowser = false
            for await snapshot in snapshots {
                guard let self, self.openItemID == id else { return }
                self.readerSnapshot = snapshot
                if snapshot.phase == .external, trigger != .click, !hasLeftForBrowser {
                    hasLeftForBrowser = true
                    self.openInBrowser(id)
                }
            }
        }
    }

    /// Space in the list: opens the selected row, then pages through the article (Shift-Space pages back).
    /// Paging goes through the reader's controller, so the keyboard stays in the list.
    public func spacePressed(shift: Bool) {
        guard let id = selectedItemID else { return }
        guard openItemID == id, readerSnapshot?.phase == .ready else { return open(id, trigger: .key) }
        shift ? reader.pageUp() : reader.pageDown()
    }

    func closeReader(keepingSnapshotOf kept: Int64? = nil) {
        readerTask?.cancel()
        readerTask = nil
        if openItemID != nil { backend.closeReader() }
        openItemID = nil
        if kept == nil || readerSnapshot?.item.id != kept { readerSnapshot = nil }
        reader.reset()
    }

    /// Known before opening only for YouTube sources; other links find out when the backend answers `.external`.
    private func opensInBrowser(_ id: Int64) -> Bool {
        guard let item = rows.first(where: { $0.id == id })?.item else { return false }
        return source(item.sourceID)?.kind == .youtube
    }

    /// Items that leave for the browser become read when they do.
    private func openInBrowser(_ id: Int64) {
        guard let url = (rows.first { $0.id == id }?.item ?? readerSnapshot?.item)?.url else { return }
        NSWorkspace.shared.open(url)
        setRead(true, itemID: id)
    }

    // MARK: Commands

    public var canOpenOriginal: Bool { selectedItem?.url != nil }

    /// ⌘O, the row's context menu, and the link in the reader header.
    public func openOriginal() {
        if let url = selectedItem?.url { NSWorkspace.shared.open(url) }
    }

    public func copyLinkOfSelection() {
        if let url = selectedItem?.url { Pasteboard.copy(url) }
    }

    func performReaderFootAction(_ action: FootAction) {
        switch action {
        case .retry: backend.retryReader()
        case .findNarrower: reader.openAsk()
        case .openSettings: openSettingsAction()
        case .checkOlder, .addSource: perform(action)
        }
    }
}
