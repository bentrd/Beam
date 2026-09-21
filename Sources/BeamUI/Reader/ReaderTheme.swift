import AppKit

/// The only colours and faces the reader owns. Everything else on the page is a system semantic colour,
/// so the reader follows the user's appearance, accent and contrast settings without any code of its own.
enum ReaderTheme {
    /// Paper. The scroll view, the foot and the body veil all use it so the pane reads as one sheet.
    static let paper = NSColor.textBackgroundColor

    /// #FFD60A, the one hit colour. The alpha carries the state (resting or current) and the fade.
    static func hitFill(alpha: CGFloat) -> NSColor {
        NSColor(srgbRed: 1.0, green: 0.839, blue: 0.039, alpha: alpha)
    }

    /// Resting and current tint strengths. Dark values come from the owner's review of the mock (DESIGN.md section 11):
    /// the lighter pair in section 3 read olive on dark paper.
    static func hitFillAlpha(emphasis: CGFloat, isDark: Bool) -> CGFloat {
        let resting: CGFloat = isDark ? 0.20 : 0.22
        let current: CGFloat = isDark ? 0.34 : 0.40
        return resting + (current - resting) * emphasis
    }

    /// #9A6B00 on light paper (about 4.7:1), #FFE066 on dark paper.
    static let hitInk = NSColor(name: nil) { appearance in
        isDark(appearance) ? NSColor(srgbRed: 1.0, green: 0.878, blue: 0.40, alpha: 1)
                           : NSColor(srgbRed: 0.604, green: 0.420, blue: 0.0, alpha: 1)
    }

    static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    /// New York, the system serif. Falls back to the system face rather than failing if the design is unavailable.
    static func serif(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    static func mono(_ size: CGFloat) -> NSFont {
        .monospacedSystemFont(ofSize: size, weight: .regular)
    }
}

/// Increase Contrast and Differentiate Without Colour ask for the same thing here: states that survive greyscale.
enum ReaderContrast {
    static var isRaised: Bool {
        let workspace = NSWorkspace.shared
        return workspace.accessibilityDisplayShouldIncreaseContrast || workspace.accessibilityDisplayShouldDifferentiateWithoutColor
    }

    /// The rail of a paragraph that is still waiting: transient, so it is the quietest line the system has.
    static func pendingRail(raised: Bool) -> NSColor { raised ? .tertiaryLabelColor : .separatorColor }

    /// The rail of a paragraph that stayed unchecked after the run settled. It is information, so it is darker.
    static func settledRail(raised: Bool) -> NSColor { raised ? .labelColor : .secondaryLabelColor }
}

/// A yellow system highlight would vanish on a yellow tint, so the reader then selects in the unemphasised grey.
enum ReaderSelection {
    static var attributes: [NSAttributedString.Key: Any] {
        let background: NSColor = isYellow(.selectedTextBackgroundColor) ? .unemphasizedSelectedTextBackgroundColor : .selectedTextBackgroundColor
        return [.backgroundColor: background]
    }

    /// Hue between orange-yellow and yellow-green, with enough saturation to be a colour at all.
    static func isYellow(_ color: NSColor) -> Bool {
        guard let rgb = color.usingColorSpace(.sRGB) else { return false }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return saturation > 0.15 && (0.10...0.20).contains(hue)
    }
}
