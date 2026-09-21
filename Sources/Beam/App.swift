import AppKit
import BeamModels
import BeamUI
import SwiftUI

/// Beam: one window, a Settings scene, and the six standard menus.
///
/// A `WindowGroup`, not a `Window`: closing the window (⌘W) keeps Beam running and a Dock click brings it back.
/// The New Window item is replaced in `BeamCommands` and tabbing is off, so there is never a second window.
/// The model lives here, outside the window, so a reopened window shows the same session.
struct BeamApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = BeamApp.makeModel()

    var body: some Scene {
        WindowGroup("Beam") {
            RootView(model: model)
        }
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
        .commands { BeamCommands(model: model) }

        Settings {
            SettingsView(model: model)
        }
    }

    private static func makeModel() -> AppModel {
        do {
            let model = AppModel(backend: try BackendFactory.make())
            DevDriver.model = model; DevDriver.startIfAsked()   // TEMPORARY
            return model
        } catch {
            // Without a backend there is nothing to show; say why on the way out instead of opening an empty window.
            FileHandle.standardError.write(Data("Beam cannot start: \(error)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // One window, no tabs: this also removes the tab items from the View and Window menus.
        NSWindow.allowsAutomaticWindowTabbing = false
        // `-look light|dark` pins the appearance, so both modes can be screenshotted without touching System Settings.
        switch UserDefaults.standard.string(forKey: "look") {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run straight from `.build` there is no bundle, and AppKit would leave the process without a Dock icon or menu bar.
        guard Bundle.main.bundleIdentifier == nil else { return }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
