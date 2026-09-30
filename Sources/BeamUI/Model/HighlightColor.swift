import SwiftUI

/// Named highlight choices keep their identity across appearances and future palette adjustments.
public enum HighlightColor: String, CaseIterable, Identifiable, Hashable, Sendable {
    case yellow, green, blue, purple, pink

    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

private struct HighlightColorKey: EnvironmentKey {
    static let defaultValue = HighlightColor.yellow
}

extension EnvironmentValues {
    var beamHighlightColor: HighlightColor {
        get { self[HighlightColorKey.self] }
        set { self[HighlightColorKey.self] = newValue }
    }
}
