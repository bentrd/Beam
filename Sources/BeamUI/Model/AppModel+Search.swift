import BeamModels
import Foundation

// The search field: Return runs or opens, Down moves to the list, Esc clears. Nothing is sent while typing.
extension AppModel {
    /// Return in the field. Changed text runs the sentence; unchanged text opens the selected row, or the top one.
    public func submitSearch() {
        footOverride = nil
        let typed = Self.cleaned(fieldText)
        guard !typed.isEmpty else { return clearSearch() }
        if let sentence, typed == Self.cleaned(sentence) { return openSelectedOrTopRow() }
        guard keyStatus != .missing else {
            // No key yet: the sentence waits in the field while the sheet asks for one.
            waitingSentence = typed
            isKeySheetPresented = true
            return
        }
        run(typed)
    }

    /// A new sentence searches every source and selects All Items. It cancels the running queue (the backend does,
    /// when asked for a new list), clears the list selection and blanks the reader; the old list holds until the first paint.
    func run(_ typed: String) {
        waitingSentence = nil
        markViewedIfLeavingPin()
        sentence = typed
        scope = .all
        deselect()
        reload()
    }

    /// Esc in the field, or its clear button. Back to the plain list of the current selection; a pin has no plain list.
    public func clearSearch() {
        footOverride = nil
        fieldText = ""
        waitingSentence = nil
        guard sentence != nil else { return }
        markViewedIfLeavingPin()
        sentence = nil
        if scope.isPin { scope = .all }
        reload()
    }

    /// Cancel in the key sheet keeps the sentence in the field, and the foot says what is missing.
    public func cancelKeySheet() {
        isKeySheetPresented = false
        if waitingSentence != nil { footOverride = ShellCopy.addKeyFoot }
    }

    /// Down in the field. With nothing selected the top row becomes the selection, so the arrow has somewhere to be.
    public func moveFocusToList() {
        if selectedItemID == nil, let top = rows.first { selectForPreview(top.id) }
        focusRequest = .list
    }

    /// Up from the first row (or in an empty list) goes back to the field.
    public func moveFocusToSearchFieldIfAtTop() -> Bool {
        guard selectedItemID == nil || selectedItemID == rows.first?.id else { return false }
        focusSearchField()
        return true
    }

    private func openSelectedOrTopRow() {
        guard let id = selectedItemID ?? rows.first?.id else { return }
        open(id, trigger: .key)
    }
}
