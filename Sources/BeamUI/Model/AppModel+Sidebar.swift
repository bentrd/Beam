import AppKit
import BeamModels
import SwiftUI

// The sidebar: selection, pins, sources, and the Undo that stands in for confirmation alerts.
extension AppModel {
    func receive(_ snapshot: SidebarSnapshot, isFirst: Bool) {
        let previous = sidebar
        sidebar = snapshot
        if isFirst, let remembered = preferences.lastScope.flatMap(ListScope.init(storageKey:)), contains(remembered) {
            select(remembered)
        }
        // A pin or source that was there and no longer is (removed, or its removal redone elsewhere): fall back to All Items.
        if !contains(scope), Self.contains(scope, in: previous) { leaveRemovedScope() }
    }

    private func contains(_ scope: ListScope) -> Bool { Self.contains(scope, in: sidebar) }

    private static func contains(_ scope: ListScope, in snapshot: SidebarSnapshot) -> Bool {
        switch scope {
        case .all: return true
        case .pin(let id): return snapshot.pins.contains { $0.id == id }
        case .source(let id): return snapshot.sources.contains { $0.id == id }
        }
    }

    // MARK: Selection

    /// A click in the sidebar, ⌘0 to ⌘9. Filters locally: a source click during a search keeps the sentence and sends nothing.
    /// - Parameter pinSentence: for a pin the sidebar has not published yet (it was created a moment ago).
    public func select(_ newScope: ListScope, pinSentence: String? = nil) {
        guard newScope != scope else { return }
        footOverride = nil
        markViewedIfLeavingPin()
        let wasPin = scope.isPin
        scope = newScope
        if case .pin(let id) = newScope {
            sentence = pinSentence ?? pin(id)?.sentence
            fieldText = sentence ?? ""
        } else if wasPin {
            // The sentence belonged to the pin, not to a search: leaving the pin leaves it behind.
            sentence = nil
            fieldText = ""
        }
        reload()
    }

    public func selectPin(at index: Int) {
        guard sidebar.pins.indices.contains(index) else { return }
        select(.pin(sidebar.pins[index].id))
    }

    /// Leaving a pin marks it viewed: its badge counts what is new since then.
    func markViewedIfLeavingPin() {
        guard case .pin(let id) = scope else { return }
        Task { await backend.markPinViewed(id: id) }
    }

    /// The selected pin or source is gone. An unpinned sentence stays in the field as an ordinary search in All Items;
    /// a removed source takes nothing with it.
    private func leaveRemovedScope() {
        scope = .all
        reload()
    }

    // MARK: Pins

    public var isSentencePinned: Bool { sentence.flatMap(pinMatching) != nil }
    public var canTogglePin: Bool { sentence != nil }

    private func pinMatching(_ sentence: String) -> Pin? {
        let wanted = Self.cleaned(sentence).lowercased()
        return sidebar.pins.first { Self.cleaned($0.pin.sentence).lowercased() == wanted }?.pin
    }

    /// ⌘D and the toolbar button. Pinning selects the new sidebar row; at nine pins nothing is pinned and the foot says so.
    public func togglePin() {
        guard let sentence else { return }
        footOverride = nil
        if let existing = pinMatching(sentence) { return remove(.pin(existing.id)) }
        Task {
            switch await backend.pin(sentence: sentence) {
            case .pinned(let pin), .alreadyPinned(let pin): select(.pin(pin.id), pinSentence: pin.sentence)
            case .limitReached: footOverride = ShellCopy.ninePinsFoot
            }
        }
    }

    public func canMovePin(by offset: Int) -> Bool {
        guard case .pin(let id) = scope, let index = sidebar.pins.firstIndex(where: { $0.id == id }) else { return false }
        return sidebar.pins.indices.contains(index + offset)
    }

    /// Move Pin Up and Move Pin Down, on the selected pin. The order sets ⌘1 to ⌘9.
    public func moveSelectedPin(by offset: Int) {
        guard case .pin(let id) = scope, canMovePin(by: offset) else { return }
        movePin(id, by: offset)
    }

    public func movePin(_ id: Int64, by offset: Int) {
        Task { await backend.movePin(id: id, by: offset) }
    }

    /// A drag in the sidebar, in `List.onMove` terms.
    public func movePins(from offsets: IndexSet, to destination: Int) {
        guard let from = offsets.first, sidebar.pins.indices.contains(from) else { return }
        let landing = destination > from ? destination - 1 : destination
        if landing != from { movePin(sidebar.pins[from].id, by: landing - from) }
    }

    // MARK: Sources

    /// ⌘N and the button under the sidebar. A collapsed sidebar is revealed first: the popover hangs from it.
    public func presentAddSource(prefill: String? = nil) {
        addSourcePrefill = prefill
        guard columnVisibility != .all else { isAddSourcePresented = true; return }
        columnVisibility = .all
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            isAddSourcePresented = true
        }
    }

    public func retry(sourceID: Int64) { Task { await backend.retrySource(id: sourceID) } }

    public func copyFeedURL(of sourceID: Int64) {
        if let url = source(sourceID)?.feedURL { Pasteboard.copy(url) }
    }

    /// ⌘R: fetches every source and retries anything not checked.
    public func refresh() { Task { await backend.refresh() } }

    // MARK: Removal and Undo

    /// "Remove Pin" or "Remove Source": the File menu item follows the sidebar selection.
    public var removeCommandTitle: String { scope.isPin ? "Remove Pin" : "Remove Source" }
    /// ⌘⌫ is live only while the sidebar has focus, so that everywhere else the key still edits text.
    /// A removal already under way is not offered again: the sidebar still lists what the backend has just dropped.
    public var canRemoveSelection: Bool {
        focusedPane == .sidebar && scope != .all && !mutationsInFlight.contains(.removal(scope))
    }
    public func removeSelection() { if canRemoveSelection { remove(scope) } }

    /// No alert: Undo restores the pin, or the source with its items, until Beam quits.
    public func remove(_ target: ListScope) {
        guard target != .all, !mutationsInFlight.contains(.removal(target)) else { return }
        let name = target.isPin ? "Remove Pin" : "Remove Source"
        let wasSelected = target == scope
        mutationsInFlight.insert(.removal(target))
        Task {
            switch target {
            case .pin(let id): await backend.removePin(id: id)
            case .source(let id): await backend.removeSource(id: id)
            case .all: return
            }
            registerUndo(name)
            mutationsInFlight.remove(.removal(target))
            if wasSelected, scope == target { leaveRemovedScope() }
        }
    }

    /// The backend keeps the real undo stack; the window's undo manager only needs to know there is something to undo
    /// and what to call it, so Edit ▸ Undo reads "Undo Remove Pin" and ⌘Z still undoes typing in a field first.
    ///
    /// The two stacks have to stay in step, so this registers what the backend reports rather than what the caller
    /// assumed: an action that found nothing to change pushes nothing, and then nothing is named here either.
    /// Otherwise ⌘Z would read one action's name and perform another's.
    func registerUndo(_ actionName: String) {
        guard backend.undoTitle == "Undo " + actionName else { return }
        undoNames.append(actionName)
        if let undoManager { register(actionName, with: undoManager) }
    }

    func register(_ actionName: String, with undoManager: UndoManager) {
        undoManager.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated { model.undoLastBackendAction() }
        }
        undoManager.setActionName(actionName)
    }

    private func undoLastBackendAction() {
        guard !undoNames.isEmpty else { return }
        undoNames.removeLast()
        // The backend keeps the real stack: when it has nothing left, neither has the window.
        Task { if await backend.undo() == nil { undoNames.removeAll() } }
    }
}
