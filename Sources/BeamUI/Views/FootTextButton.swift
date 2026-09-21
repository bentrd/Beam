import AppKit
import SwiftUI

/// The text button a foot or an empty state may end with ("Retry", "Open Settings", "Check 53 older").
/// A real button in the key loop with a 24 pt hit height. It is underlined when colour alone would not tell it from
/// the sentence beside it: Differentiate Without Colour, or a Graphite or Yellow accent.
struct FootTextButton: View {
    let title: String
    let action: () -> Void

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @State private var accentIsWeak = FootTextButton.accentIsGraphiteOrYellow

    var body: some View {
        Button(action: action) {
            Text(title)
                .underline(differentiateWithoutColor || accentIsWeak)
                .foregroundStyle(Color.accentColor)
                .frame(minHeight: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onReceive(NotificationCenter.default.publisher(for: NSColor.systemColorsDidChangeNotification)) { _ in
            accentIsWeak = Self.accentIsGraphiteOrYellow
        }
    }

    /// System Settings stores the accent as `AppleAccentColor`: -1 is Graphite and 2 is Yellow. Absent means multicolour (blue).
    private static var accentIsGraphiteOrYellow: Bool {
        guard let accent = UserDefaults.standard.object(forKey: "AppleAccentColor") as? Int else { return false }
        return accent == -1 || accent == 2
    }
}
