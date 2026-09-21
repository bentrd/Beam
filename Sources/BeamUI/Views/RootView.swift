import AppKit
import BeamModels
import SwiftUI

/// The one window: sidebar, list and reader under a toolbar that holds the search field and the pin button.
/// Glass is only where the system draws it (sidebar, toolbar); the list, the reader and both feet are opaque.
public struct RootView: View {
    @Bindable var model: AppModel

    @FocusState private var focus: AppModel.Pane?
    @Environment(\.openSettings) private var openSettings
    @Environment(\.undoManager) private var undoManager
    /// True while the sidebar is hidden because the window got narrow, as opposed to hidden by its owner.
    @State private var collapsedForWidth = false

    /// Below this window width the sidebar collapses by itself.
    private static let sidebarCollapseWidth: CGFloat = 960

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        NavigationSplitView(columnVisibility: $model.columnVisibility) {
            SidebarView(model: model, focus: $focus)
                .navigationSplitViewColumnWidth(min: Preferences.sidebarWidths.lowerBound, ideal: model.preferences.sidebarWidth,
                                                max: Preferences.sidebarWidths.upperBound)
        } content: {
            ItemListView(model: model, focus: $focus)
                .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
        } detail: {
            ReaderPane(snapshot: model.readerSnapshot, textSize: model.preferences.textSize, controller: model.reader,
                       actions: model.readerActions)
        }
        .navigationTitle(model.windowTitle)
        .toolbar {
            ToolbarItem(placement: .principal) {
                // Preferred 420 pt and never under 260 pt, so the field never collapses to a magnifier button.
                SearchToolbarField(model: model).frame(minWidth: 260, idealWidth: 420, maxWidth: 420)
            }
            ToolbarItem(placement: .principal) { PinButton(model: model) }
        }
        .toolbar(removing: .title)
        .frame(minWidth: 820, minHeight: 520)
        .background(WindowConfigurator())
        .background(UnlistedShortcuts(model: model))
        .background(GeometryReader { geometry in
            Color.clear.onChange(of: geometry.size.width, initial: true) { _, width in collapseSidebarIfNarrow(width) }
        })
        .sheet(isPresented: $model.isKeySheetPresented) { KeySheet(model: model).interactiveDismissDisabled() }
        .onChange(of: focus) { model.focusedPane = focus }
        .onChange(of: model.focusRequest) {
            guard let requested = model.focusRequest else { return }
            focus = requested
            model.focusRequest = nil
        }
        .onChange(of: undoManager, initial: true) { model.attach(openSettings: { openSettings() }, undoManager: undoManager) }
        .task { model.start() }
    }

    private func collapseSidebarIfNarrow(_ width: CGFloat) {
        if width < Self.sidebarCollapseWidth, model.columnVisibility == .all {
            model.columnVisibility = .doubleColumn
            collapsedForWidth = true
        } else if width >= Self.sidebarCollapseWidth, collapsedForWidth {
            model.columnVisibility = .all
            collapsedForWidth = false
        }
    }
}

/// `pin` when the sentence is unpinned, `pin.fill` when it is pinned, in the standard toolbar tint.
/// Enabled whenever there is a submitted sentence.
private struct PinButton: View {
    let model: AppModel

    var body: some View {
        Button(action: model.togglePin) {
            Image(systemName: model.isSentencePinned ? "pin.fill" : "pin").contentTransition(.symbolEffect(.replace))
        }
        .help(model.isSentencePinned ? ShellCopy.unpinHelp : ShellCopy.pinHelp)
        .accessibilityLabel(model.isSentencePinned ? ShellCopy.unpinLabel : ShellCopy.pinLabel)
        .disabled(!model.canTogglePin)
    }
}

/// The two alternates DESIGN.md asks for without listing them in a menu: ⌘L beside ⌥⌘F, and ⌘= beside ⌘+.
/// A menu item has one key equivalent, so these live in the window as invisible buttons.
private struct UnlistedShortcuts: View {
    let model: AppModel

    var body: some View {
        Group {
            Button("Search All Items", action: model.focusSearchField).keyboardShortcut("l")
            Button("Make Text Bigger", action: model.preferences.makeTextBigger).keyboardShortcut("=")
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// What SwiftUI's scene modifiers cannot say: this window never joins a tab group, and it does go full screen
/// (DESIGN.md section 10 ends the View menu with Enter Full Screen).
private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.tabbingMode = .disallowed
            window.collectionBehavior.insert(.fullScreenPrimary)
        }
    }
}
