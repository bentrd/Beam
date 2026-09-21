import AppKit
import BeamModels
import SwiftUI

/// ⌘N: one address field over the live-filtered catalog. Return or a click adds a source, the row gains a checkmark,
/// the source appears in the sidebar at once, and the popover and the focus stay for more. Esc closes it.
struct AddSourcePopover: View {
    @Bindable var model: AppModel

    private enum Field: Hashable { case address, catalog }

    @State private var address = ""
    @State private var status = ""
    @State private var highlighted: CatalogEntry.ID?
    @State private var catalog: [CatalogEntry] = []
    @FocusState private var focus: Field?

    var body: some View {
        VStack(spacing: 0) {
            TextField("Feed, site, subreddit or channel URL", text: $address)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .writingToolsBehavior(.disabled)
                .autocorrectionDisabled()
                .focused($focus, equals: .address)
                .onSubmit(submitAddress)
                .onKeyPress(.downArrow) {
                    highlighted = highlighted ?? matches.first?.id
                    focus = .catalog
                    return .handled
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
            // One secondary line carries the inline status; its height is always there, so nothing shifts.
            Text(status)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 16, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            Divider()
            List(selection: selection) {
                ForEach(matches) { CatalogRow(entry: $0, isAdded: isAdded($0.candidate)).tag($0.id) }
            }
            .listStyle(.plain)
            .focused($focus, equals: .catalog)
            .onKeyPress(.return) {
                guard let entry = matches.first(where: { $0.id == highlighted }) else { return .ignored }
                add(entry.candidate)
                return .handled
            }
        }
        .frame(width: 320, height: 360)
        .onExitCommand { model.isAddSourcePresented = false }
        .onChange(of: status) { Announcer.say(status) }
        .onAppear {
            catalog = model.backend.catalog()
            focus = .address
            if let dropped = model.addSourcePrefill {
                model.addSourcePrefill = nil
                address = dropped
                submitAddress()
            }
        }
    }

    /// The catalog narrows as the address is typed; nothing is fetched until Return.
    private var matches: [CatalogEntry] {
        let wanted = address.trimmingCharacters(in: .whitespaces).lowercased()
        guard !wanted.isEmpty else { return catalog }
        return catalog.filter { entry in
            [entry.candidate.title, entry.blurb, entry.candidate.feedURL.absoluteString, entry.candidate.siteURL?.absoluteString ?? ""]
                .contains { $0.lowercased().contains(wanted) }
        }
    }

    /// A click adds the row; arrow keys only move the highlight, and Return adds it.
    private var selection: Binding<CatalogEntry.ID?> {
        Binding(get: { highlighted }, set: { id in
            highlighted = id
            let type = NSApp.currentEvent?.type
            if type == .leftMouseDown || type == .leftMouseUp, let entry = matches.first(where: { $0.id == id }) { add(entry.candidate) }
        })
    }

    private func isAdded(_ candidate: SourceCandidate) -> Bool {
        model.sidebar.sources.contains { $0.source.feedURL == candidate.feedURL }
    }

    /// Return in the field. An address is looked up; plain words take the first catalog match.
    private func submitAddress() {
        let typed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return }
        let looksLikeAddress = typed.contains(".") || typed.contains("/")
        if !looksLikeAddress, let first = matches.first { return add(first.candidate) }
        status = "Looking for a feed"
        Task {
            switch await model.backend.resolve(typed) {
            case .found(let candidates):
                if let first = candidates.first { add(first) } else { status = "No feed found at this address" }
            case .alreadyAdded: status = "Already added"
            case .notFound: status = "No feed found at this address"
            }
        }
    }

    private func add(_ candidate: SourceCandidate) {
        guard !isAdded(candidate) else { status = "Already added"; return }
        Task {
            switch await model.backend.addSource(candidate) {
            case .added: status = "Added"
            case .alreadyAdded: status = "Already added"
            case .failed(let reason): status = reason
            }
        }
    }
}

/// A catalog entry: its title, a line about it, and a checkmark once it is in the sidebar.
private struct CatalogRow: View {
    let entry: CatalogEntry
    let isAdded: Bool

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.candidate.title).font(.system(size: 13)).lineLimit(1)
                Text(entry.blurb).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if isAdded { Image(systemName: "checkmark").foregroundStyle(.secondary).accessibilityLabel("Added") }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
