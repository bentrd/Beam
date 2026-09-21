import AppKit
import SwiftUI

/// The text button a foot or an empty state may end with ("Retry", "Open Settings", "Check 53 older").
/// Both feet use it, so the same sentence reads the same under the list and under the reader.
///
/// It is a real button in the key loop with a 24 pt hit height, and it is drawn in the user's accent colour.
/// When that colour cannot carry a button it falls back to ink and an underline: a graphite accent is the colour of
/// the sentence beside it, and yellow belongs to the hits alone (DESIGN.md section 3, "no yellow controls").
struct FootTextButton: View {
    let title: String
    let action: () -> Void

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @State private var accentIsWeak = FootAccent.cannotCarryAButton

    var body: some View {
        Button(action: action) {
            Text(title)
                .underline(differentiateWithoutColor || accentIsWeak)
                .foregroundStyle(accentIsWeak ? Color(nsColor: .labelColor) : Color.accentColor)
                .fixedSize()
                .frame(minHeight: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onReceive(NotificationCenter.default.publisher(for: NSColor.systemColorsDidChangeNotification)) { _ in
            accentIsWeak = FootAccent.cannotCarryAButton
        }
    }
}

/// Whether the accent colour is one a text button cannot be told from its surroundings by.
/// Measured from the resolved colour rather than read from `AppleAccentColor`, so a custom accent is judged too.
enum FootAccent {
    static var cannotCarryAButton: Bool {
        guard let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB) else { return false }
        return accent.saturationComponent < 0.15 || ReaderSelection.isYellow(accent)
    }
}
