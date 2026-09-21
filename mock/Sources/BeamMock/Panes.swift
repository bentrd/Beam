import SwiftUI

struct Sidebar: View {
    @Bindable var mock: Mock
    var body: some View {
        List(selection: $mock.sidebarSelection) {
            Text("All Items").tag("All Items")
            Section("Pins") {
                ForEach(mock.pins, id: \.0) { pin in
                    Text(pin.0).lineLimit(1).truncationMode(.tail).help(pin.0).badge(pin.1).tag(pin.0)
                }
            }
            Section("Sources") {
                ForEach(mock.sources, id: \.self) { Text($0).tag($0) }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button { } label: { Label("Add Source", systemImage: "plus.circle") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 10)
        }
    }
}

struct ResultRow: View {
    let row: Row
    let marked: Bool
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(Color(nsColor: Theme.hitInk))
                .frame(width: 4, height: 12).padding(.top, 2.5).opacity(marked && row.found ? 1 : 0)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).font(.system(size: 13)).lineLimit(2)
                Text("\(row.source) · \(row.age)").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

struct ListPane: View {
    @Bindable var mock: Mock
    var body: some View {
        List(selection: $mock.selection) {
            ForEach(mock.rows) { ResultRow(row: $0, marked: mock.scene != .plain).tag($0.id) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Text(mock.scene == .plain ? "\(mock.total) items" : "\(mock.total) items checked")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).frame(height: 30)
                .background(.background)
                .overlay(alignment: .top) { Divider() }
        }
    }
}
