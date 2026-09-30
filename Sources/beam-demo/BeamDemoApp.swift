import AppKit
import BeamModels
import BeamUI
import SwiftUI

/// A developer recorder using Beam's real scene and views over captured public feed content.
/// Run `swift run beam-demo --output /path/to/frames`; add `--mode live` for real Jev judgments.
@main
struct BeamDemoApp: App {
    @NSApplicationDelegateAdaptor(BeamDemoDelegate.self) private var delegate
    @State private var session = BeamDemoSession.shared

    var body: some Scene {
        Window("Beam", id: "beam-showcase") {
            BeamDemoContent(session: session)
        }
        .defaultSize(width: BeamDemoSession.shared.isLoadingScene ? 640 : 1180, height: 760)
        .defaultLaunchBehavior(.presented)
        .restorationBehavior(.disabled)
        .windowResizability(.contentMinSize)
        .commands { BeamCommands(model: session.model) }

        Settings { SettingsView(model: session.model) }
    }
}

private struct BeamDemoContent: View {
    @Bindable var session: BeamDemoSession

    var body: some View {
        Group {
            if session.isLoadingScene {
                ReaderPane(snapshot: session.loadingSnapshot, textSize: ReaderTextSize.standard,
                           controller: session.model.reader, actions: ReaderActions())
                    .frame(minWidth: 420, minHeight: 360)
            } else {
                RootView(model: session.model).id(ObjectIdentifier(session.model))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if !session.caption.isEmpty {
                Text(session.caption)
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Color(nsColor: .windowBackgroundColor), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color(nsColor: .separatorColor)))
                    .padding(.trailing, 18).padding(.bottom, 44)
            }
        }
        .task { await session.record() }
    }
}

final class BeamDemoDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        BeamDemoSession.progress("application launching")
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApp.appearance = NSAppearance(named: BeamDemoSession.shared.isDark ? .darkAqua : .aqua)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        BeamDemoSession.progress("application launched")
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(8))
            BeamDemoSession.shared.failIfSceneDidNotStart()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct BeamDemoFailure: Error, CustomStringConvertible {
    let description: String
}
