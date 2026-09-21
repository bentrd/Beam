import AppKit
import BeamModels
import SwiftUI

/// The middle column: ranked or chronological rows over a one-line foot.
/// Arrow keys preview and send nothing; Return, Space or a click opens; rows drag out as URLs and ⌘C copies the link.
struct ItemListView: View {
    @Bindable var model: AppModel
    var focus: FocusState<AppModel.Pane?>.Binding

    /// Where the selected row sat just before the merge, so it can be put back there afterwards.
    @State private var anchor = SelectionAnchor()

    /// The list's own frame, so a row's position can be read as a height above the list's top edge.
    private static let space = "beam.list"

    var body: some View {
        ZStack {
            rows
                .id(model.listGeneration)                 // a streamed run's first paint cross-fades the whole list
                .transition(.opacity)
            if let message = model.emptyMessage {
                EmptyListMessage(text: message, action: model.emptyAction, perform: model.perform)
            }
        }
        // A bottom-aligned bar accessory: the system draws its material and fits it to the window's corners.
        .safeAreaBar(edge: .bottom, spacing: 0) { ListFootView(foot: model.listFoot, perform: model.perform) }
        // Text never shows through the toolbar glass above, or through the foot below.
        .scrollEdgeEffectStyle(.hard, for: [.top, .bottom])
    }

    private var rows: some View {
        ScrollViewReader { proxy in
            List(selection: selection) {
                ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                    ItemRowView(row: row, position: index + 1, count: model.rows.count, isFresh: model.freshRowIDs.contains(row.id))
                        .tag(row.id)
                        .modifier(NewSincePinViewedSeparator(isLastNewRow: row.id == model.lastNewRowID))
                        .modifier(DraggableLink(url: row.item.url))
                        .modifier(MeasuredWhenSelected(isSelected: row.id == model.selectedItemID, space: Self.space,
                                                      report: { anchor.row = $0 }))
                }
            }
            .coordinateSpace(.named(Self.space))
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { anchor.listHeight = $0 }
            .focused(focus, equals: .list)
            .contextMenu(forSelectionType: Int64.self, menu: contextMenu) { ids in
                if let id = ids.first { model.open(id, trigger: .doubleClick) }
            }
            .copyable(model.selectedItem?.url.map { [CopiedLink($0)] } ?? [])
            .onKeyPress(.return) {
                guard let id = model.selectedItemID else { return .ignored }
                model.open(id, trigger: .key)
                return .handled
            }
            .onKeyPress(.space, phases: .down) { press in
                guard model.selectedItemID != nil else { return .ignored }
                model.spacePressed(shift: press.modifiers.contains(.shift))
                return .handled
            }
            .onKeyPress(.upArrow) { model.moveFocusToSearchFieldIfAtTop() ? .handled : .ignored }
            .onChange(of: model.listResets) {
                if let first = model.rows.first { proxy.scrollTo(first.id, anchor: .top) }
            }
            .onChange(of: model.listMerges) { keepSelectedRowStill(proxy) }
            .accessibilityLabel(model.windowTitle)
        }
    }

    /// The one merge of a settled run inserts held rows above the selection, which would push everything under
    /// Ben's eyes down by their height. Where he has touched the list, the selected row keeps the y position it
    /// had a moment ago: the row is scrolled back to the same height above the list's top edge, unanimated.
    /// Where he has not, nothing is scrolled — the list never moves by itself.
    private func keepSelectedRowStill(_ proxy: ScrollViewProxy) {
        guard model.hasTouchedList, let id = model.selectedItemID,
              let row = anchor.row, let height = anchor.listHeight,
              row.minY >= 0, row.maxY <= height, height > row.height
        else { return }
        // `scrollTo` lines the row's anchor point up with the same point of the list, so the fraction that puts
        // the row's top back where it was is its old height above the top over the travel the two have between them.
        let unit = UnitPoint(x: 0, y: min(max(row.minY / (height - row.height), 0), 1))
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { proxy.scrollTo(id, anchor: unit) }
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

/// The selected row's frame in the list, kept out of the view's state so that reading it at the merge cannot
/// itself redraw anything. It holds what was measured at the last layout, which is the position before the merge.
@MainActor private final class SelectionAnchor {
    var row: CGRect?
    var listHeight: CGFloat?
}

/// Measures the selected row, and only it: the rest of the list is not worth a geometry reader each.
private struct MeasuredWhenSelected: ViewModifier {
    let isSelected: Bool
    let space: String
    let report: (CGRect?) -> Void

    func body(content: Content) -> some View {
        if isSelected {
            content.onGeometryChange(for: CGRect.self) { $0.frame(in: .named(space)) } action: { report($0) }
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
            if let action, let title = ShellCopy.title(for: action) { FootTextButton(title: title) { perform(action) } }
        }
        .font(.system(size: 13))
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
        .transition(.opacity)
    }
}
