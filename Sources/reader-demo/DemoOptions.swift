import Foundation

/// What the demo shows, from the command line:
/// `reader-demo -scene lit|saturated|loading|unavailable|preview|unchecked -look light|dark -jump N`,
/// plus `-size 15…28`, `-ask "a question"`, and for reviews without a screen `-snapshot file.png [-after seconds]`.
struct DemoOptions {
    enum Scene: String, CaseIterable {
        /// A narrow sentence: twelve paragraphs light up over two seconds.
        case lit
        /// A broad sentence: the article saturates, so it shows no marks and the calm sentence in the foot.
        case saturated
        /// The article never arrives: title and byline at once, "Getting the article" after a second.
        case loading
        case unavailable
        /// A selected row that is not opened. Return opens it, through a slow load.
        case preview
        /// Some judgments fail: their paragraphs keep a rail and the foot offers Retry.
        case unchecked
    }

    enum Look: String { case light, dark }

    var scene = Scene.lit
    var look: Look?
    /// Find Next is pressed this many times once the run has settled.
    var jumps = 0
    /// The reader's text size in points; snapped to the nearest of the eight steps.
    var textSize: Double?
    /// Opens the ask field with this question once the run has settled, and asks it.
    var question: String?
    /// Review aid: write the window's content to this PNG once everything has settled, then quit.
    var snapshotPath: String?
    /// How long to wait before the jumps and the snapshot. The default lets the two-second run settle first.
    var settleTime = 2.6

    /// `-name value` pairs land in the argument domain of the user defaults.
    init(defaults: UserDefaults = .standard) {
        if let raw = defaults.string(forKey: "scene") {
            guard let scene = Scene(rawValue: raw) else {
                let known = Scene.allCases.map(\.rawValue).joined(separator: "|")
                FileHandle.standardError.write(Data("reader-demo: unknown scene \"\(raw)\". Use -scene \(known).\n".utf8))
                exit(2)
            }
            self.scene = scene
        }
        look = defaults.string(forKey: "look").flatMap(Look.init(rawValue:))
        jumps = max(defaults.integer(forKey: "jump"), 0)
        if defaults.object(forKey: "size") != nil { textSize = defaults.double(forKey: "size") }
        question = defaults.string(forKey: "ask").flatMap { $0.isEmpty ? nil : $0 }
        snapshotPath = defaults.string(forKey: "snapshot")
        if defaults.object(forKey: "after") != nil { settleTime = max(defaults.double(forKey: "after"), 0) }
    }
}
