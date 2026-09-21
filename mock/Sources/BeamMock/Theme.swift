import AppKit
import SwiftUI

/// The only colours Beam owns. Everything else is a system semantic colour.
enum Theme {
    static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
    static func hitFill(current: Bool) -> NSColor {
        NSColor(name: nil) { a in
            let alpha = isDark(a) ? (current ? 0.30 : 0.16) : (current ? 0.40 : 0.22)
            return NSColor(srgbRed: 1.0, green: 0.839, blue: 0.039, alpha: alpha)
        }
    }
    static let hitInk = NSColor(name: nil) { a in
        isDark(a) ? NSColor(srgbRed: 1.0, green: 0.878, blue: 0.40, alpha: 1)
                  : NSColor(srgbRed: 0.604, green: 0.42, blue: 0.0, alpha: 1)
    }
    static func serif(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }
}
