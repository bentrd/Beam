import AppKit
import BeamModels
import SwiftUI

/// Every shortcut is a real menu item (DESIGN.md sections 10 and 11), inside the six standard menus.
/// There are no New Window or tab items, no custom top-level menu, and Help keeps only the system search field.
///
/// Each group's items are a `View` of their own, so their titles and enabling are tracked against the `@Observable`
/// model like any other view body.
public struct BeamCommands: Commands {
    let model: AppModel

    public init(model: AppModel) { self.model = model }

    public var body: some Commands {
        CommandGroup(replacing: .newItem) { FileMenuItems(model: model) }
        CommandGroup(after: .pasteboard) { Divider(); FindMenuItems(model: model); SpeechMenuItems() }
        SidebarCommands()
        CommandGroup(after: .sidebar) { ViewMenuItems(model: model) }
        CommandGroup(replacing: .help) {}
    }
}

private struct FileMenuItems: View {
    let model: AppModel

    var body: some View {
        Button("Add Source…") { model.presentAddSource() }.keyboardShortcut("n")
        Divider()
        Button("Open Original", action: model.openOriginal).keyboardShortcut("o").disabled(!model.canOpenOriginal)
        if let url = model.selectedItem?.url {
            ShareLink(item: url) { Text("Share") }
        } else {
            Button("Share") {}.disabled(true)
        }
        Divider()
        Button(model.readCommandTitle, action: model.toggleReadOfSelection)
            .keyboardShortcut("u", modifiers: [.command, .shift])
            .disabled(model.selectedItem == nil)
        Button("Mark All as Read", action: model.markAllRead).keyboardShortcut("k").disabled(!model.canMarkAllRead)
        Divider()
        Button(model.isSentencePinned ? "Unpin Sentence" : "Pin Sentence", action: model.togglePin)
            .keyboardShortcut("d")
            .disabled(!model.canTogglePin)
        Button("Move Pin Up") { model.moveSelectedPin(by: -1) }
            .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            .disabled(!model.canMovePin(by: -1))
        Button("Move Pin Down") { model.moveSelectedPin(by: 1) }
            .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            .disabled(!model.canMovePin(by: 1))
        // Enabled only while the sidebar has focus, so that everywhere else ⌘⌫ still reaches the text field.
        Button(model.removeCommandTitle, action: model.removeSelection)
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(!model.canRemoveSelection)
        Divider()
        Button("Refresh", action: model.refresh).keyboardShortcut("r")
    }
}

/// Edit ▸ Find. The literal text finder never appears: these are Beam's own items, under the standard names.
private struct FindMenuItems: View {
    let model: AppModel

    var body: some View {
        Menu("Find") {
            Button("Search All Items", action: model.focusSearchField).keyboardShortcut("f", modifiers: [.command, .option])
            Button("Find by Meaning…") { model.reader.openAsk() }.keyboardShortcut("f").disabled(!model.reader.isArticleOpen)
            Button("Find Next", action: model.reader.next).keyboardShortcut("g").disabled(!canWalkHits)
            Button("Find Previous", action: model.reader.previous).keyboardShortcut("g", modifiers: [.command, .shift]).disabled(!canWalkHits)
            Button("Use Selection for Find") { model.reader.openAsk(prefill: model.reader.selectedText) }
                .keyboardShortcut("e")
                .disabled(!model.reader.isArticleOpen || (model.reader.selectedText ?? "").isEmpty)
            Button("Jump to Selection", action: model.reader.jumpToSelection).keyboardShortcut("j").disabled(!model.reader.isArticleOpen)
        }
    }

    /// Find Next and Find Previous are also off in a saturated article: there is nothing to walk.
    private var canWalkHits: Bool { model.reader.isArticleOpen && model.reader.canNavigate }

}

private struct SpeechMenuItems: View {
    var body: some View {
        Menu("Speech") {
            Button("Start Speaking") { NSApp.sendAction(#selector(NSTextView.startSpeaking(_:)), to: nil, from: nil) }
            Button("Stop Speaking") { NSApp.sendAction(#selector(NSTextView.stopSpeaking(_:)), to: nil, from: nil) }
        }
    }

}

private struct ViewMenuItems: View {
    @Bindable var model: AppModel

    var body: some View {
        Divider()
        Button(ShellCopy.allItems) { model.select(.all) }.keyboardShortcut("0")
        // The pins, in sidebar order: their position is their shortcut.
        ForEach(Array(model.sidebar.pins.prefix(Pin.maximum).enumerated()), id: \.element.id) { index, summary in
            Button(summary.pin.sentence) { model.selectPin(at: index) }
                .keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
        }
        Divider()
        Toggle("Hide Read Items", isOn: $model.hidesReadItems).keyboardShortcut("r", modifiers: [.command, .option])
        Divider()
        Button("Make Text Bigger", action: model.preferences.makeTextBigger).keyboardShortcut("+").disabled(!model.preferences.canMakeTextBigger)
        Button("Make Text Smaller", action: model.preferences.makeTextSmaller).keyboardShortcut("-").disabled(!model.preferences.canMakeTextSmaller)
        Button("Actual Size", action: model.preferences.useActualSize)
        Divider()                                   // AppKit appends Enter Full Screen below
    }
}
