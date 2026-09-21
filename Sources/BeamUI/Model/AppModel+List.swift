import AppKit
import BeamModels
import SwiftUI

// The list: its stream, how streamed rows reach the screen, selection, and read state.
extension AppModel {
    // MARK: Stream

    /// Asks the backend for the list of the current scope and sentence. The previous run is cancelled by the backend.
    func reload() {
        listTask?.cancel()
        firstPaintTask?.cancel()
        preferences.lastScope = scope.storageKey
        hasAnnouncedSettle = false
        isAwaitingFirstRows = true

        let request = ListRequest(scope: scope, sentence: scope.isPin ? nil : sentence, hidesRead: preferences.hidesReadItems)
        let isRanked = request.sentence != nil || scope.isPin
        streaming.begin(ranked: isRanked, holdsUntilSettled: NSWorkspace.shared.isVoiceOverEnabled)
        let snapshots = backend.list(request)
        listTask = Task { [weak self] in
            for await snapshot in snapshots { self?.receive(snapshot) }
        }
        guard isRanked else { return }
        firstPaintTask = Task { [weak self] in
            try? await Task.sleep(for: ListStreaming.firstPaintDelay)
            guard let self, !Task.isCancelled else { return }
            self.apply(self.streaming.firstPaintDeadlinePassed())
        }
    }

    private func receive(_ snapshot: ListSnapshot) {
        apply(streaming.receive(snapshot))
        if !snapshot.isRunning { didSettle(snapshot) }
    }

    private func apply(_ change: ListStreaming.Change) {
        switch change {
        case .none:
            break
        case .replace:
            if isAwaitingFirstRows { listResets += 1 }
            isAwaitingFirstRows = false
            deselectIfGone()
            restoreSelectionIfAsked()
        case .firstPaint:
            isAwaitingFirstRows = false
            withAnimation(.easeInOut(duration: 0.18)) { listGeneration += 1 }
        case .append(let ids):
            fadeIn(ids)
        case .merge(let ids):
            fadeIn(ids)
            listMerges += 1
        }
    }

    /// New rows fade in over 150 ms; opacity is the only motion there is.
    private func fadeIn(_ ids: Set<Int64>) {
        guard !ids.isEmpty else { return }
        freshRowIDs = ids
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            if freshRowIDs == ids { freshRowIDs = [] }
        }
    }

    /// Once per run. With the field still focused and nothing selected, the top row becomes the (unemphasised)
    /// selection and the reader previews it; nothing is sent. VoiceOver hears one polite sentence, never a count-up.
    private func didSettle(_ snapshot: ListSnapshot) {
        guard !hasAnnouncedSettle else { return }
        hasAnnouncedSettle = true
        guard snapshot.request.sentence != nil || snapshot.request.scope.isPin else { return }
        if snapshot.request.sentence != nil, isSearchFieldFocused, selectedItemID == nil, let top = rows.first {
            selectForPreview(top.id)
        }
        if let top = rows.first {
            let count = rows.count == 1 ? "1 item" : "\(rows.count.formatted()) items"
            Announcer.say("\(count). Top: \(top.item.title). Return to read.")
        } else {
            Announcer.say(emptyMessage ?? listFoot.text)
        }
    }

    // MARK: Foot

    public func perform(_ action: FootAction) {
        footOverride = nil
        switch action {
        case .retry:
            hasAnnouncedSettle = false
            backend.retryList()
            if case .source(let id) = scope, source(id)?.lastError != nil { retry(sourceID: id) }
        case .openSettings: openSettingsAction()
        case .checkOlder:
            hasAnnouncedSettle = false
            backend.checkOlder()
        case .findNarrower: reader.openAsk()
        case .addSource: presentAddSource()
        }
    }

    // MARK: Selection

    /// The list's selection changed by hand. Arrow keys preview (title and snippet, nothing sent);
    /// a click opens, except on a row that leaves for the browser, which waits for Return or a double click.
    public func userSelected(_ id: Int64?, byClick: Bool) {
        footOverride = nil
        guard let id else { return deselect() }
        if byClick { open(id, trigger: .click) } else { selectForPreview(id) }
    }

    func selectForPreview(_ id: Int64) {
        // SwiftUI may write the same selection again when the list rebuilds: an open article must survive that.
        guard selectedItemID != id else { return }
        selectedItemID = id
        preferences.lastItemID = id
        preview(id)
    }

    func deselect() {
        selectedItemID = nil
        preferences.lastItemID = nil
        closeReader()
    }

    /// A new list that no longer holds the selected row: the selection goes, and the reader with it.
    private func deselectIfGone() {
        guard let id = selectedItemID, itemToRestore == nil, !rows.contains(where: { $0.id == id }) else { return }
        deselect()
    }

    /// At launch the row selected at the last quit comes back as a preview; nothing opens or is sent by itself.
    private func restoreSelectionIfAsked() {
        guard let id = itemToRestore, streaming.latest?.isRunning == false else { return }
        itemToRestore = nil
        guard rows.contains(where: { $0.id == id }) else { return focusSearchField() }
        selectForPreview(id)
        focusRequest = .list
    }

    // MARK: Read and unread

    /// "Mark as Read" or "Mark as Unread": one toggling item, on the selected row.
    public var readCommandTitle: String { selectedItem?.read == true ? "Mark as Unread" : "Mark as Read" }

    public func toggleReadOfSelection() {
        guard let item = selectedItem else { return }
        setRead(!item.read, itemID: item.id)
    }

    public func setRead(_ read: Bool, itemID: Int64) {
        Task { await backend.setRead(read, itemIDs: [itemID]) }
    }

    /// ⌘K acts on the current list scope, and is undoable.
    public var canMarkAllRead: Bool {
        switch scope {
        case .all: return sidebar.unreadInAll > 0
        case .source(let id): return (sidebar.sources.first { $0.id == id }?.unread ?? 0) > 0
        case .pin: return rows.contains { !$0.item.read }
        }
    }

    public func markAllRead() {
        guard canMarkAllRead else { return }
        let scope = scope
        Task {
            await backend.markAllRead(in: scope)
            registerUndo("Mark All as Read")
        }
    }

    /// View ▸ Hide Read Items. Persisted; ignored by the backend while a sentence is active.
    public var hidesReadItems: Bool {
        get { preferences.hidesReadItems }
        set {
            guard newValue != preferences.hidesReadItems else { return }
            preferences.hidesReadItems = newValue
            reload()
        }
    }
}
