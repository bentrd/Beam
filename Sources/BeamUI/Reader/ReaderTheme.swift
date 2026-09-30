import AppKit

/// The only colours and faces the reader owns. Everything else on the page is a system semantic colour,
/// so the reader follows the user's appearance, accent and contrast settings without any code of its own.
enum ReaderTheme {
    /// Paper. The scroll view, the foot and the body veil all use it so the pane reads as one sheet.
    static let paper = NSColor.textBackgroundColor

    /// The selected hue; alpha carries resting/current state and the fade.
    static func hitFill(alpha: CGFloat, color: HighlightColor = .yellow) -> NSColor {
        palette(color).fill.withAlphaComponent(alpha)
    }

    /// Resting and current tint strengths. Dark values come from the owner's review of the mock (DESIGN.md section 11):
    /// the lighter pair in section 3 read olive on dark paper.
    static func hitFillAlpha(emphasis: CGFloat, isDark: Bool) -> CGFloat {
        let resting: CGFloat = isDark ? 0.20 : 0.22
        let current: CGFloat = isDark ? 0.34 : 0.40
        return resting + (current - resting) * emphasis
    }

    /// Dark ink on light paper and light ink on dark paper keep the bars, strip and list marks readable.
    static func hitInk(_ color: HighlightColor = .yellow) -> NSColor {
        NSColor(name: nil) { appearance in
            let colors = palette(color)
            return isDark(appearance) ? colors.darkInk : colors.lightInk
        }
    }

    private struct Palette { let fill: NSColor; let lightInk: NSColor; let darkInk: NSColor }

    private static func palette(_ color: HighlightColor) -> Palette {
        func rgb(_ hex: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                    blue: CGFloat(hex & 255) / 255, alpha: 1)
        }
        switch color {
        case .yellow: return Palette(fill: rgb(0xFFD60A), lightInk: rgb(0x9A6B00), darkInk: rgb(0xFFE066))
        case .green: return Palette(fill: rgb(0x34C759), lightInk: rgb(0x28733B), darkInk: rgb(0x82E599))
        case .blue: return Palette(fill: rgb(0x0A84FF), lightInk: rgb(0x1F5FAD), darkInk: rgb(0x83BBFF))
        case .purple: return Palette(fill: rgb(0xAF52DE), lightInk: rgb(0x7E3FAC), darkInk: rgb(0xD5A1F4))
        case .pink: return Palette(fill: rgb(0xFF2D55), lightInk: rgb(0xA72D58), darkInk: rgb(0xFF9FBD))
        }
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

/// A system selection with the same hue as the passage tint uses neutral grey so selected text remains distinct.
enum ReaderSelection {
    static func attributes(highlightColor: HighlightColor) -> [NSAttributedString.Key: Any] {
        let tint = ReaderTheme.hitFill(alpha: 1, color: highlightColor)
        let background: NSColor = clashes(.selectedTextBackgroundColor, with: tint) ? .unemphasizedSelectedTextBackgroundColor : .selectedTextBackgroundColor
        return [.backgroundColor: background]
    }

    private static func clashes(_ color: NSColor, with tint: NSColor) -> Bool {
        guard let selected = color.usingColorSpace(.sRGB), let highlight = tint.usingColorSpace(.sRGB) else { return false }
        let distance = abs(selected.hueComponent - highlight.hueComponent)
        return selected.saturationComponent > 0.15 && min(distance, 1 - distance) < 0.09
    }

    /// The shell's link treatment still recognises a yellow system accent independently of the chosen palette.
    static func isYellow(_ color: NSColor) -> Bool {
        guard let rgb = color.usingColorSpace(.sRGB) else { return false }
        return rgb.saturationComponent > 0.15 && (0.10...0.20).contains(rgb.hueComponent)
    }
}
