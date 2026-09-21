import AppKit

/// The one colour the shell draws itself. Everything else is a system semantic colour.
enum ShellPalette {
    /// The list mark: #9A6B00 on light paper (about 4.7:1 on white), pale yellow #FFE066 in dark mode.
    static let hitInk = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 1.0, green: 0.878, blue: 0.40, alpha: 1)
            : NSColor(srgbRed: 0.604, green: 0.42, blue: 0.0, alpha: 1)
    }
}
