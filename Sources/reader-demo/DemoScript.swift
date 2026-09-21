import AppKit

/// What the command line asked to happen after launch: the look, the jumps, and the review snapshot.
@MainActor
struct DemoScript {
    let model: DemoModel

    func run() async {
        switch model.options.look {
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        case nil: break
        }
        let options = model.options
        guard options.jumps > 0 || options.question != nil || options.snapshotPath != nil else { return }

        try? await Task.sleep(for: .seconds(options.settleTime))
        if let question = options.question {
            model.controller.openAsk(prefill: question)
            try? await Task.sleep(for: .milliseconds(400))
            model.ask(question)
            try? await Task.sleep(for: .milliseconds(2600))
        }
        for _ in 0..<options.jumps {
            model.controller.next()
            try? await Task.sleep(for: .milliseconds(600))
        }
        guard let path = options.snapshotPath else { return }
        do {
            try DemoSnapshot.write(to: URL(fileURLWithPath: path))
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("reader-demo: \(error)\n".utf8))
            exit(1)
        }
    }
}

/// Renders the window's content into a PNG without the screen: a review aid for machines that cannot take screenshots.
@MainActor
enum DemoSnapshot {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    static func write(to url: URL) throws {
        guard let view = NSApp.windows.first(where: \.isVisible)?.contentView else { throw Failure(description: "no window to snapshot") }
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw Failure(description: "could not allocate the bitmap") }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw Failure(description: "could not encode the PNG") }
        try png.write(to: url)
    }
}
