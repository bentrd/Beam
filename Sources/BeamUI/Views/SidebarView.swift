import AppKit
import BeamModels
import SwiftUI

/// The sidebar is text only: All Items, Pins (no header when there are none), Sources, and Add Source at the bottom.
/// Badges are the system's: unread counts on All Items and sources, "new since last viewed" on pins.
struct SidebarView: View {
    @Bindable var model: AppModel
    var focus: FocusState<AppModel.Pane?>.Binding

    var body: some View {
        List(selection: selection) {
            Text(ShellCopy.allItems)
                .badge(model.sidebar.unreadInAll)
                .tag(ListScope.all)
            if !model.sidebar.pins.isEmpty {
                Section(ShellCopy.pins) {
                    ForEach(model.sidebar.pins) { PinRow(model: model, summary: $0).tag(ListScope.pin($0.id)) }
                        .onMove(perform: model.movePins)
                }
            }
            Section(ShellCopy.sources) {
                ForEach(model.sidebar.sources) { SourceRow(model: model, summary: $0).tag(ListScope.source($0.id)) }
            }
        }
        .focused(focus, equals: .sidebar)
        .copyable(selectedFeedURL.map { [$0.absoluteString] } ?? [])
        .dropDestination(for: URL.self) { urls, _ in
            // A URL dropped on the sidebar opens the popover with that address already running.
            guard let url = urls.first else { return false }
            model.presentAddSource(prefill: url.absoluteString)
            return true
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { addSourceButton }
        .background(WidthReader { model.preferences.sidebarWidth = $0 })
    }

    private var selection: Binding<ListScope?> {
        Binding(get: { model.scope }, set: { if let scope = $0 { model.select(scope) } })
    }

    private var selectedFeedURL: URL? {
        if case .source(let id) = model.scope { return model.source(id)?.feedURL }
        return nil
    }

    private var addSourceButton: some View {
        Button { model.presentAddSource() } label: { Label(ShellCopy.addSource, systemImage: "plus.circle") }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .popover(isPresented: $model.isAddSourcePresented, arrowEdge: .trailing) { AddSourcePopover(model: model) }
    }
}

/// The sentence, tail-truncated, with the whole of it in the help tag. Not editable.
private struct PinRow: View {
    let model: AppModel
    let summary: PinSummary

    var body: some View {
        Text(summary.pin.sentence)
            .lineLimit(1)
            .truncationMode(.tail)
            .help(summary.pin.sentence)
            .badge(summary.newFound)
            .contextMenu { Button("Remove Pin") { model.remove(.pin(summary.id)) } }
            .accessibilityLabel(summary.newFound > 0 ? "\(summary.pin.sentence), \(summary.newFound) new" : summary.pin.sentence)
            .accessibilityAction(named: "Move Up") { model.movePin(summary.id, by: -1) }
            .accessibilityAction(named: "Move Down") { model.movePin(summary.id, by: 1) }
    }
}

/// The title. A passing failure shows nothing; after 24 hours of failing, one monochrome warning glyph.
private struct SourceRow: View {
    let model: AppModel
    let summary: SourceSummary

    var body: some View {
        HStack(spacing: 6) {
            Text(summary.source.title).lineLimit(1).truncationMode(.tail)
            if summary.showsWarning {
                Spacer(minLength: 0)
                Image(systemName: "exclamationmark.triangle")
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.secondary)
                    .help(ShellCopy.couldNotRefresh(summary.source.lastError ?? ""))
                    .accessibilityHidden(true)
            }
        }
        .badge(summary.unread)
        .contextMenu {
            Button("Retry") { model.retry(sourceID: summary.id) }
            Button("Copy Feed URL") { model.copyFeedURL(of: summary.id) }
            Divider()
            Button("Remove Source") { model.remove(.source(summary.id)) }
        }
        .accessibilityLabel(accessibilityLabel)
    }

    /// "{name}, couldn't refresh, {reason}" for a failing source.
    private var accessibilityLabel: String {
        guard let reason = summary.source.lastError else { return summary.source.title }
        return "\(summary.source.title), couldn't refresh, \(reason)"
    }
}

/// Reports the sidebar's width as the owner drags it, so the next launch starts from the same place.
private struct WidthReader: View {
    let report: (Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            Color.clear.onChange(of: geometry.size.width) { _, width in
                if Preferences.sidebarWidths.contains(width) { report(width) }
            }
        }
    }
}
