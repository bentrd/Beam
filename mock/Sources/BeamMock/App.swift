import SwiftUI

@main
struct BeamMockApp: App {
    @State private var mock = Mock(scene: MockScene(rawValue: UserDefaults.standard.string(forKey: "scene") ?? "lit") ?? .lit)

    var body: some Scene {
        WindowGroup("Beam") {
            NavigationSplitView {
                Sidebar(mock: mock).navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
            } content: {
                ListPane(mock: mock).navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
            } detail: {
                if mock.selection != nil { ReaderPane(mock: mock) } else { Color(nsColor: .textBackgroundColor) }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    SearchField(text: $mock.sentence, prompt: "Describe what you want to read")
                        .frame(minWidth: 260, idealWidth: 420, maxWidth: 420)
                }
                ToolbarItem(placement: .principal) {
                    Button { } label: { Image(systemName: "pin") }.help("Pin this sentence").disabled(mock.sentence.isEmpty)
                }
            }
            .toolbar(removing: .title)
            .task {
                switch UserDefaults.standard.string(forKey: "look") {
                case "light": NSApp.appearance = NSAppearance(named: .aqua)
                case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
                default: break
                }
                let jumps = UserDefaults.standard.integer(forKey: "jump")
                guard jumps > 0 else { return }
                try? await Task.sleep(for: .seconds(1.2))
                for _ in 0..<jumps { mock.step(1) }
            }
            .frame(minWidth: 820, minHeight: 520)
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(after: .textEditing) {
                Button("Find Next") { mock.step(1) }.keyboardShortcut("g", modifiers: .command)
                Button("Find Previous") { mock.step(-1) }.keyboardShortcut("g", modifiers: [.command, .shift])
            }
        }
    }
}


/// The stock AppKit search field, so it looks and behaves exactly like every other Mac search field.
struct SearchField: NSViewRepresentable {
    @Binding var text: String
    let prompt: String
    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = prompt
        field.sendsWholeSearchString = true
        field.delegate = context.coordinator
        field.controlSize = .large
        return field
    }
    func updateNSView(_ field: NSSearchField, context: Context) { if field.stringValue != text { field.stringValue = text } }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        let parent: SearchField
        init(_ parent: SearchField) { self.parent = parent }
        func controlTextDidChange(_ note: Notification) { if let f = note.object as? NSSearchField { parent.text = f.stringValue } }
    }
}
