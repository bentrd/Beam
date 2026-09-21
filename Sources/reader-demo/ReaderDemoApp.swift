import AppKit
import BeamUI
import SwiftUI

/// Shows `ReaderPane` by itself, fed from the captured article, so the reader can be reviewed without the rest of Beam.
@main
struct ReaderDemoApp: App {
    @NSApplicationDelegateAdaptor(DemoAppDelegate.self) private var delegate
    @State private var model = DemoLauncher.model

    var body: some Scene {
        WindowGroup("Reader") {
            ReaderPane(snapshot: model.snapshot, textSize: model.textSize, controller: model.controller, actions: model.actions)
                .frame(minWidth: 420, minHeight: 360)
                .task { await DemoScript(model: model).run() }
        }
        .defaultSize(width: 640, height: 760)
        .commands { DemoCommands(model: model) }
    }
}

/// The fixture is part of the build; a demo without it has nothing to show, so it says why and stops.
@MainActor
enum DemoLauncher {
    static let model: DemoModel = {
        do { return try DemoModel(options: DemoOptions()) } catch {
            FileHandle.standardError.write(Data("reader-demo: \(error)\n".utf8))
            exit(1)
        }
    }()
}

/// A bare executable is not a regular app until it says so: without this the window opens behind everything, with no menus.
final class DemoAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// The menu commands the real app will have, so the reader can be driven from the keyboard here too.
struct DemoCommands: Commands {
    @Bindable var model: DemoModel

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open") { model.openPreviewed() }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(!model.isPreview)
        }
        CommandGroup(after: .textEditing) {
            let controller = model.controller
            Button("Find by Meaning…") { controller.openAsk() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(!controller.isArticleOpen)
            Button("Find Next") { controller.next() }
                .keyboardShortcut("g", modifiers: .command)
                .disabled(!controller.canNavigate)
            Button("Find Previous") { controller.previous() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(!controller.canNavigate)
            Button("Use Selection for Find") { controller.openAsk(prefill: controller.selectedText) }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(!controller.isArticleOpen || controller.selectedText == nil)
            Button("Jump to Selection") { controller.jumpToSelection() }
                .keyboardShortcut("j", modifiers: .command)
                .disabled(!controller.isArticleOpen || controller.selectedText == nil)
        }
        CommandGroup(before: .toolbar) {
            Button("Make Text Bigger") { model.textSize = ReaderTextSize.larger(than: model.textSize) }
                .keyboardShortcut("+", modifiers: .command)
            Button("Make Text Smaller") { model.textSize = ReaderTextSize.smaller(than: model.textSize) }
                .keyboardShortcut("-", modifiers: .command)
            Button("Actual Size") { model.textSize = ReaderTextSize.standard }
            Divider()
        }
    }
}
