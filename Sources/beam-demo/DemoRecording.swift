import AppKit
import BeamModels
import BeamUI
import Foundation
import Observation

@MainActor @Observable
final class BeamDemoSession {
    static let shared: BeamDemoSession = {
        do { return try BeamDemoSession() }
        catch {
            FileHandle.standardError.write(Data("beam-demo: \(error)\n".utf8))
            exit(2)
        }
    }()

    var model: AppModel
    let isLoadingScene: Bool
    let isDark: Bool
    let loadingSnapshot: ReaderSnapshot?
    var caption = ""
    private var sessionBackend: BeamDemoBackend?
    private let isLive: Bool
    private let captureMode: BeamDemoSnapshot.CaptureMode
    private let output: URL
    private let defaults: UserDefaults
    private let suiteName: String
    private var hasRecorded = false

    static func progress(_ stage: String) {
        FileHandle.standardError.write(Data("beam-demo: \(stage)\n".utf8))
    }

    func failIfSceneDidNotStart() {
        guard !hasRecorded else { return }
        Self.progress("the showcase scene did not start")
        finish(1)
    }

    private init() throws {
        let arguments = CommandLine.arguments
        func option(_ name: String) -> String? {
            guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        guard let flag = arguments.firstIndex(of: "--output"), arguments.indices.contains(flag + 1),
              !arguments[flag + 1].hasPrefix("--") else {
            throw BeamDemoFailure(description: "usage: beam-demo --output <frame-directory> [--mode live|fixture] [--look light|dark] [--scene loading] [--capture layer|view|combined]")
        }
        isLoadingScene = option("--scene") == "loading"
        isDark = option("--look") == "dark"
        captureMode = BeamDemoSnapshot.CaptureMode(rawValue: option("--capture") ?? "combined") ?? .combined
        if isLoadingScene {
            let fixture = try ReaderFixture.load(.lit)
            loadingSnapshot = ReaderSnapshot(item: fixture.item, sourceTitle: fixture.sourceTitle, phase: .loading,
                                             foot: Foot("Getting the article"))
        } else { loadingSnapshot = nil }
        output = URL(fileURLWithPath: arguments[flag + 1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        suiteName = "Beam.Demo.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw BeamDemoFailure(description: "could not create isolated demo preferences")
        }
        self.defaults = defaults
        // An unpaired switch suppresses the initial scene in this raw SwiftPM GUI executable.
        // Keep recorder switches paired so SwiftUI receives its normal initial-window launch event.
        isLive = option("--mode") == "live"
        // Prepare the isolated live backend only after the recorder's native scene is ready.
        model = AppModel(backend: try FakeBackend(options: FakeOptions(keyStatus: .missing)),
                         preferences: Preferences(defaults: defaults), forcesWelcome: true)
        model.columnVisibility = .doubleColumn
    }

    /// SwiftUI creates and lays out the NSWindow before recording. The script yields between actions, so normal
    /// AppKit drawing, SwiftUI observation, streaming snapshots and reader scrolling all run as in the app.
    func record() async {
        guard !hasRecorded else { return }
        hasRecorded = true
        Self.progress("scene ready; preparing public sample library")
        do {
            let sessionBackend = try BeamDemoBackend(live: isLive)
            self.sessionBackend = sessionBackend
            model.isKeySheetPresented = false
            model = AppModel(backend: sessionBackend.backend,
                             preferences: Preferences(defaults: defaults), forcesWelcome: true)
            model.columnVisibility = .doubleColumn
            try await sessionBackend.prepare()
            if !isLoadingScene { model.start() }
            Self.progress("public sample library prepared")
            try await Task.sleep(for: .milliseconds(650))
            guard let window = NSApp.windows.first(where: { $0.isVisible && !$0.isSheet && $0.contentView != nil }) else {
                throw BeamDemoFailure(description: "the app window did not appear")
            }
            let script = Task { if !isLoadingScene { try await play() } }
            Self.progress("recording actual app views")
            let fps = 6
            let frameCount = isLoadingScene ? 1 : fps * 32
            let started = ContinuousClock.now
            var states: [String] = []
            for frame in 0..<frameCount {
                let deadline = started.advanced(by: .seconds(Double(frame) / Double(fps)))
                if ContinuousClock.now < deadline { try await Task.sleep(until: deadline, clock: .continuous) }
                window.contentView?.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
                let file = output.appendingPathComponent(String(format: "frame-%04d.png", frame))
                try BeamDemoSnapshot.write(window: window, mode: captureMode, to: file)
                if frame == 0 { Self.progress("first frame exported") }
                states.append("\(frame): welcome=\(model.isKeySheetPresented), rows=\(model.rows.count), reader=\(model.readerSnapshot?.phase.rawValue ?? "none"), find=\(model.readerSnapshot?.isFindActive ?? false), jump=\(model.reader.jumpCount), color=\(model.preferences.highlightColor.rawValue), caption=\(caption)")
                // Caching a Retina window can take longer than one frame. Always yield even after a missed
                // deadline, otherwise this main-actor loop starves the scene script and AppKit redraws.
                try await Task.sleep(for: .milliseconds(10))
            }
            try await script.value
            let manifest = "frames=\(frameCount)\nfps=\(fps)\ncapture=\(captureMode.rawValue)\nlook=\(isDark ? "dark" : "light")\nsource=\(sessionBackend.sourceDescription)\n" + states.joined(separator: "\n") + "\n"
            try Data(manifest.utf8).write(to: output.appendingPathComponent("recording.txt"), options: .atomic)
            print("beam-demo: wrote \(frameCount) PNG frames at \(fps) fps to \(output.path)")
            finish(0)
        } catch {
            FileHandle.standardError.write(Data("beam-demo: \(error)\n".utf8))
            finish(1)
        }
    }

    private func finish(_ status: Int32) -> Never {
        defaults.removePersistentDomain(forName: suiteName)
        sessionBackend?.cleanup()
        exit(status)
    }

    private func play() async throws {
        guard let sessionBackend else { throw BeamDemoFailure(description: "the showcase backend was not prepared") }
        try await Task.sleep(for: .milliseconds(1750))
        model.cancelKeySheet()
        try await Task.sleep(for: .milliseconds(350))
        // The backend owns credential handling; a live key never enters any field, caption or recording log.
        guard await sessionBackend.connect(model: model) == .valid else {
            throw BeamDemoFailure(description: "the showcase connection failed")
        }
        Self.progress("showcase connection validated")
        try await Task.sleep(for: .milliseconds(200))
        model.focusSearchField()
        let sentence = "running models locally on a laptop"
        for character in sentence {
            model.fieldText.append(character)
            try await Task.sleep(for: .milliseconds(35))
        }
        model.submitSearch()
        caption = "Search by meaning"
        try await waitFor("live search results") {
            model.rows.contains { $0.item.title.hasPrefix("Things we learned") && $0.check?.isChecked == true }
                && model.listFoot.text.contains("checked") && !model.listFoot.text.hasPrefix("Checking")
        }
        Self.progress("live search settled")
        try await Task.sleep(for: .milliseconds(700))
        guard let article = model.rows.first(where: { $0.item.title.hasPrefix("Things we learned") }) else {
            throw BeamDemoFailure(description: "the captured article was not found in the search")
        }
        model.open(article.id, trigger: .click)
        caption = "Matching paragraphs in the original article"
        try await waitFor("article judgments") {
            model.readerSnapshot?.phase == .ready && model.readerSnapshot?.isRunning == false && model.reader.canNavigate
        }
        Self.progress("article judgments settled")
        model.reader.next()
        try await Task.sleep(for: .milliseconds(1200))
        caption = "⌘F  Find by meaning"
        if !invokeMenu("Find by Meaning…") { model.reader.openAsk() }
        try await Task.sleep(for: .milliseconds(550))
        let question = "memory requirements for running models on a laptop"
        model.reader.openAsk(prefill: question)
        try await Task.sleep(for: .milliseconds(700))
        model.readerActions.find(question)
        try await waitFor("Find by Meaning judgments") {
            model.readerSnapshot?.isFindActive == true && model.readerSnapshot?.isRunning == false && model.reader.canNavigate
        }
        Self.progress("Find by Meaning judgments settled")
        caption = "⌘G  Next matching passage"
        if !invokeMenu("Find Next") { model.reader.next() }
        try await Task.sleep(for: .milliseconds(1200))
        if !invokeMenu("Find Next") { model.reader.next() }
        try await Task.sleep(for: .milliseconds(1200))
        caption = "⌘D  Pin this search"
        model.togglePin()
        try await Task.sleep(for: .milliseconds(800))
        caption = "Beam Settings  ·  Highlight color"
        model.perform(.openSettings)
        try await Task.sleep(for: .milliseconds(850))
        if let settings = NSApp.windows.first(where: { $0.isVisible && $0.title == "Beam Settings" }) {
            if let main = NSApp.windows.first(where: { $0.isVisible && !$0.isSheet && $0 !== settings }) {
                settings.setFrameOrigin(NSPoint(x: main.frame.midX - settings.frame.width / 2,
                                               y: main.frame.midY - settings.frame.height / 2))
            }
            if let content = settings.contentView, let picker = findPalettePicker(in: content) {
                picker.selectItem(withTitle: "Purple")
                if let action = picker.action { NSApp.sendAction(action, to: picker.target, from: picker) }
            }
            model.preferences.highlightColor = .purple
            try await Task.sleep(for: .milliseconds(1500))
            settings.close()
        } else {
            throw BeamDemoFailure(description: "Beam Settings did not open")
        }
        caption = "Your reading, your highlights"
        try await Task.sleep(for: .milliseconds(1500))
        caption = ""
    }

    private func waitFor(_ name: String, condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        while !condition() {
            guard ContinuousClock.now < deadline else { throw BeamDemoFailure(description: "timed out waiting for \(name)") }
            try await Task.sleep(for: .milliseconds(40))
        }
    }

    private func invokeMenu(_ title: String) -> Bool {
        func perform(in menu: NSMenu) -> Bool {
            for (index, item) in menu.items.enumerated() {
                if item.title == title, item.isEnabled { menu.performActionForItem(at: index); return true }
                if let submenu = item.submenu, perform(in: submenu) { return true }
            }
            return false
        }
        return NSApp.mainMenu.map(perform(in:)) ?? false
    }

    private func findPalettePicker(in view: NSView) -> NSPopUpButton? {
        if let picker = view as? NSPopUpButton, picker.itemTitles.contains("Purple") { return picker }
        for child in view.subviews { if let picker = findPalettePicker(in: child) { return picker } }
        return nil
    }
}
