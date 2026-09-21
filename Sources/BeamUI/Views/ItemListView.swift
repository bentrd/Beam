import AppKit
import BeamModels
import SwiftUI

/// The middle column: ranked or chronological rows over a one-line foot.
/// Arrow keys preview and send nothing; Return, Space or a click opens; rows drag out as URLs and ⌘C copies the link.
struct ItemListView: View {
    @Bindable var model: AppModel
    var focus: FocusState<AppModel.Pane?>.Binding

    var body: some View {
        ZStack {
            rows
                .id(model.listGeneration)                 // a streamed run's first paint cross-fades the whole list
                .transition(.opacity)
            if let message = model.emptyMessage {
                EmptyListMessage(text: message, action: model.emptyAction, perform: model.perform)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { ListFootView(foot: model.listFoot, perform: model.perform) }
        .scrollEdgeEffectStyle(.hard, for: .top)          // text never shows through the toolbar glass
    }

    private var rows: some View {
        ScrollViewReader { proxy in
            List(selection: selection) {
                ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                    ItemRowView(row: row, position: index + 1, count: model.rows.count, isFresh: model.freshRowIDs.contains(row.id))
                        .tag(row.id)
                        .modifier(NewSincePinViewedSeparator(isLastNewRow: row.id == model.lastNewRowID))
                        .modifier(DraggableLink(url: row.item.url))
                }
            }
            .focused(focus, equals: .list)
            .contextMenu(forSelectionType: Int64.self, menu: contextMenu) { ids in
                if let id = ids.first { model.open(id, trigger: .doubleClick) }
            }
            .copyable(model.selectedItem?.url.map { [$0.absoluteString] } ?? [])
            .onKeyPress(.return) {
                guard let id = model.selectedItemID else { return .ignored }
                model.open(id, trigger: .key)
                return .handled
            }
            .onKeyPress(.space, phases: .down) { press in
                model.spacePressed(shift: press.modifiers.contains(.shift))
                return .handled
            }
            .onKeyPress(.upArrow) { model.moveFocusToSearchFieldIfAtTop() ? .handled : .ignored }
            .onChange(of: model.listResets) {
                if let first = model.rows.first { proxy.scrollTo(first.id, anchor: .top) }
            }
            .onChange(of: model.listMerges) {
                // The one merge of a settled run inserts rows above the selection: keep the selected row in view.
                if let id = model.selectedItemID { proxy.scrollTo(id) }
            }
            .accessibilityLabel(model.windowTitle)
        }
    }

    /// Writes from the list are told apart by the event that caused them: a click opens the row, an arrow key previews it.
    private var selection: Binding<Int64?> {
        Binding(get: { model.selectedItemID },
                set: { model.userSelected($0, byClick: Self.isHandlingClick) })
    }

    private static var isHandlingClick: Bool {
        guard let type = NSApp.currentEvent?.type else { return false }
        return type == .leftMouseDown || type == .leftMouseUp
    }

    @ViewBuilder private func contextMenu(for ids: Set<Int64>) -> some View {
        if let row = model.rows.first(where: { ids.contains($0.id) }) {
            let url = row.item.url
            Button("Open Original") { if let url { NSWorkspace.shared.open(url) } }.disabled(url == nil)
            Button("Copy Link") { if let url { Pasteboard.copy(url) } }.disabled(url == nil)
            if let url { ShareLink(item: url) { Text("Share") } }
            Divider()
            Button(row.item.read ? "Mark as Unread" : "Mark as Read") { model.setRead(!row.item.read, itemID: row.id) }
        }
    }
}

/// Pins only: the separator under the last row that is new since the pin was last viewed runs the full width.
/// A full-width separator means nothing else anywhere.
private struct NewSincePinViewedSeparator: ViewModifier {
    let isLastNewRow: Bool

    func body(content: Content) -> some View {
        if isLastNewRow {
            content
                .listRowSeparator(.visible, edges: .bottom)
                .alignmentGuide(.listRowSeparatorLeading) { _ in -100 }
                .alignmentGuide(.listRowSeparatorTrailing) { dimensions in dimensions.width + 100 }
        } else {
            content
        }
    }
}

/// Rows drag out as URLs; a row without a link does not drag.
private struct DraggableLink: ViewModifier {
    let url: URL?

    func body(content: Content) -> some View {
        if let url { content.draggable(url) } else { content }
    }
}

/// One centred secondary line with at most one text button, and no symbols.
private struct EmptyListMessage: View {
    let text: String
    let action: FootAction?
    let perform: (FootAction) -> Void

    var body: some View {
        VStack(spacing: 2) {
            Text(text).foregroundStyle(.secondary)
            if let action { FootTextButton(title: ShellCopy.title(for: action)) { perform(action) } }
        }
        .font(.system(size: 13))
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
        .transition(.opacity)
    }
}
