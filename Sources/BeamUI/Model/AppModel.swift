import AppKit
import BeamModels
import Observation
import SwiftUI

/// Everything the window knows that is not pixels: the sidebar selection, the submitted sentence, the selected and
/// the open item, and the three backend streams. Views draw it and call it; they hold no logic of their own.
///
/// One instance lives for the whole session, so closing the window (⌘W) and reopening it from the Dock loses nothing.
@MainActor @Observable
public final class AppModel {
    /// The two panes SwiftUI focus can name. The search field is AppKit and reports its own focus.
    public enum Pane: Hashable { case sidebar, list }
    /// An undoable backend action asked for and not yet finished. The snapshots the window reads lag the backend,
    /// so what is in flight is what keeps ⌘K and ⌘⌫ from being asked twice for work already being done.
    enum Mutation: Hashable { case sweep(ListScope), removal(ListScope) }
    /// How an item was asked to open: a single click never sends a YouTube row to the browser.
    public enum OpenTrigger { case click, doubleClick, key }

    public let backend: BeamBackend
    public let preferences: Preferences
    /// Lets menu commands drive the reader pane.
    public let reader = ReaderController()

    // Sidebar
    public internal(set) var sidebar = SidebarSnapshot()
    /// The sidebar selection.
    public internal(set) var scope: ListScope = .all
    public var columnVisibility = NavigationSplitViewVisibility.all

    // Sentence
    /// What is in the search field right now. Nothing is sent while typing.
    public var fieldText = ""
    /// The sentence the list is ranked by: the last one submitted, or the selected pin's.
    public internal(set) var sentence: String?
    /// Typed before a key existed: runs as soon as one is accepted.
    var waitingSentence: String?
    public internal(set) var keyStatus = KeyStatus.missing

    // List
    var streaming = ListStreaming()
    /// Changes at each first paint of a streamed run, so the list cross-fades as a whole instead of sliding rows.
    public internal(set) var listGeneration = 0
    /// Bumped when a different list takes over at once (another scope, a cached sentence), so it starts at its top.
    public internal(set) var listResets = 0
    /// Rows that just arrived and fade in. Everything else is drawn at full strength at once.
    public internal(set) var freshRowIDs: Set<Int64> = []
    /// Bumped at the one merge of a settled run, so the selected row can be kept in view.
    public internal(set) var listMerges = 0
    public internal(set) var selectedItemID: Int64?
    /// A sentence of the shell's own ("Nine pins maximum") shown until the next action.
    var footOverride: Foot?

    // Reader
    public internal(set) var readerSnapshot: ReaderSnapshot?
    /// The item whose article is open, as opposed to merely selected and previewed.
    public internal(set) var openItemID: Int64?

    // Presentation
    public var isKeySheetPresented = false
    public internal(set) var isWelcomeKeySheet = false
    public var isAddSourcePresented = false
    /// A URL dropped on the sidebar: the popover opens with it already running.
    public var addSourcePrefill: String?

    // Focus
    public var focusedPane: Pane?
    /// Set to move SwiftUI focus; the window clears it once applied.
    public var focusRequest: Pane?
    /// Bumped to move focus to the AppKit search field.
    public internal(set) var searchFocusRequests = 0
    public var isSearchFieldFocused = false

    @ObservationIgnored var openSettingsAction: () -> Void = {}
    @ObservationIgnored weak var undoManager: UndoManager?
    /// Action names registered with the window's undo manager, oldest first: they mirror the backend's undo stack,
    /// so a reopened window (a new undo manager) can be given the same Undo menu.
    @ObservationIgnored var undoNames: [String] = []
    @ObservationIgnored var sidebarTask: Task<Void, Never>?
    @ObservationIgnored var listTask: Task<Void, Never>?
    @ObservationIgnored var firstPaintTask: Task<Void, Never>?
    @ObservationIgnored var readerTask: Task<Void, Never>?
    @ObservationIgnored var hasStarted = false
    @ObservationIgnored let offersWelcome: Bool
    @ObservationIgnored private let forcesWelcome: Bool
    @ObservationIgnored var itemToRestore: Int64?
    @ObservationIgnored var hasAnnouncedSettle = false
    /// True once Ben has reached into the list in this run (a click, an arrow key, Down from the field): from then on
    /// the selected row keeps its y position when the held rows merge in.
    @ObservationIgnored var hasTouchedList = false
    /// True from a new list request until its first rows are on screen.
    @ObservationIgnored var isAwaitingFirstRows = false
    /// Undoable backend actions under way. They are observed, because the File menu greys out what is in flight.
    var mutationsInFlight: Set<Mutation> = []

    public init(backend: BeamBackend, preferences: Preferences? = nil, offersWelcome: Bool = true, forcesWelcome: Bool = false) {
        self.backend = backend
        self.preferences = preferences ?? Preferences()
        self.offersWelcome = offersWelcome
        self.forcesWelcome = forcesWelcome
    }

    // MARK: What the views draw

    public var rows: [Row] { streaming.rows }
    public var listFoot: Foot { footOverride ?? streaming.latest?.foot ?? .blank }
    public var emptyMessage: String? { streaming.emptyMessage }
    public var emptyAction: FootAction? { streaming.emptyAction }
    public var lastNewRowID: Int64? { streaming.lastNewRowID }

    /// The window title follows the sidebar selection (Mission Control, the Window menu, VoiceOver); the toolbar hides it.
    public var windowTitle: String {
        switch scope {
        case .all: return ShellCopy.allItems
        case .pin(let id): return pin(id)?.sentence ?? ShellCopy.allItems
        case .source(let id): return source(id)?.title ?? ShellCopy.allItems
        }
    }

    public var selectedItem: Item? {
        guard let id = selectedItemID else { return nil }
        if let row = rows.first(where: { $0.id == id }) { return row.item }
        return readerSnapshot?.item.id == id ? readerSnapshot?.item : nil
    }

    func pin(_ id: Int64) -> Pin? { sidebar.pins.first { $0.id == id }?.pin }
    func source(_ id: Int64) -> Source? { sidebar.sources.first { $0.id == id }?.source }

    /// The reader's requests, routed to the backend.
    public var readerActions: ReaderActions {
        ReaderActions(find: { [weak self] in self?.backend.find($0) },
                      viewportChanged: { [weak self] first, last in self?.backend.setViewport(firstVisible: first, lastVisible: last) },
                      footAction: { [weak self] in self?.performReaderFootAction($0) },
                      openOriginal: { [weak self] in self?.openOriginal() })
    }

    // MARK: Session

    /// Subscribes to the backend. Safe to call again when the window is reopened.
    public func start() {
        guard !hasStarted else { return }
        hasStarted = true
        itemToRestore = preferences.lastItemID
        Task { [weak self] in await self?.loadKeyStatus() }
        let snapshots = backend.sidebar()
        sidebarTask = Task { [weak self] in
            var isFirst = true
            for await snapshot in snapshots {
                self?.receive(snapshot, isFirst: isFirst)
                isFirst = false
            }
        }
        reload()
        if itemToRestore == nil { focusSearchField() }
    }

    /// The window hands over its system hooks: the Settings action and the undo manager the Edit menu talks to.
    public func attach(openSettings: @escaping () -> Void, undoManager: UndoManager?) {
        openSettingsAction = openSettings
        guard let undoManager, undoManager !== self.undoManager else { return }
        self.undoManager = undoManager
        for name in undoNames { register(name, with: undoManager) }
    }

    public func focusSearchField() { searchFocusRequests += 1 }

    /// Loading a connection sends no validation request. Captured design sessions can opt out of setup.
    public func loadKeyStatus() async {
        await refreshConnectionStatus()
        guard offersWelcome, forcesWelcome || !preferences.hasCompletedWelcome else { return }
        if keyStatus == .valid, !forcesWelcome {
            preferences.hasCompletedWelcome = true
        } else {
            isWelcomeKeySheet = true
            isKeySheetPresented = true
        }
    }

    /// A request may have discovered that a saved key was revoked since launch.
    public func refreshConnectionStatus() async { keyStatus = await backend.keyStatus() }

    /// Settings and the key sheet both end here. A sentence that was waiting for a key runs as soon as one is accepted.
    public func setKey(_ key: String?) async -> KeyStatus {
        let result = await backend.setKey(key)
        // A failed replacement preserves the saved connection; report the attempted key separately to the view.
        keyStatus = await backend.keyStatus()
        let connected = result == .valid && !(key ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if connected {
            if offersWelcome { preferences.hasCompletedWelcome = true }
            isKeySheetPresented = false
            isWelcomeKeySheet = false
            if let waiting = waitingSentence, Self.cleaned(fieldText) == waiting { run(waiting) }
        }
        return result
    }

    static func cleaned(_ text: String) -> String { text.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
}

extension ListScope {
    var isPin: Bool { if case .pin = self { return true }; return false }

    /// "all", "pin:12", "source:3": how the selection is remembered between launches.
    var storageKey: String {
        switch self {
        case .all: return "all"
        case .pin(let id): return "pin:\(id)"
        case .source(let id): return "source:\(id)"
        }
    }

    init?(storageKey: String) {
        let parts = storageKey.split(separator: ":")
        switch (parts.first, parts.count == 2 ? Int64(parts[1]) : nil) {
        case ("all", _): self = .all
        case ("pin", let id?): self = .pin(id)
        case ("source", let id?): self = .source(id)
        default: return nil
        }
    }
}
