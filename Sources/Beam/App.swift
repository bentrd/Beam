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
            let reviewWelcome = UserDefaults.standard.bool(forKey: "showWelcome")
            let model = AppModel(backend: try BackendFactory.make(),
                                 offersWelcome: !UserDefaults.standard.bool(forKey: "fake") || reviewWelcome,
                                 forcesWelcome: reviewWelcome)
            MenuCheck.runIfAsked(for: model)
            return model
        } catch {
            FileHandle.standardError.write(Data("Beam cannot start: \(error)\n".utf8))
            // A Finder launch has no terminal: make a library failure visible and leave the user's data intact.
            NSApplication.shared.setActivationPolicy(.regular)
            NSApp.activate()
            let alert = NSAlert()
            alert.messageText = "Beam couldn't open your library"
            alert.informativeText = "\(error.localizedDescription)\n\nYour library is in ~/Library/Application Support/Beam. Check that this folder is writable, then reopen Beam."
            alert.alertStyle = .critical
            alert.addButton(withTitle: "Quit")
            alert.runModal()
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
        // The menu bar exists by now; the few items AppKit owns are put right here (DESIGN.md section 10).
        MainMenu.tidy()
        // SwiftUI rebuilds menu items as the model changes (a pin arrives, an item's enabling turns over), and can
        // bring AppKit's own items back with them. The moment that matters is the one before a menu is drawn.
        NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: NSApp.mainMenu, queue: .main) { _ in
            MainActor.assumeIsolated { MainMenu.tidy() }
        }
        // Run straight from `.build` there is no bundle, and AppKit would leave the process without a Dock icon or menu bar.
        guard Bundle.main.bundleIdentifier == nil else { return }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
