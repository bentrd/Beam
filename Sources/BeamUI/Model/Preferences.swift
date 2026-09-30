import Foundation
import Observation

/// What Beam remembers about how its owner likes the window, kept in `UserDefaults`.
/// Appearance changes in Settings; reading and window preferences also change from the View menu and by dragging.
@MainActor @Observable
public final class Preferences {
    /// The eight reader sizes of DESIGN.md section 3, owned by the reader (`ReaderTextSize`).
    /// Chrome never scales: Mac apps scale content, not controls.
    public static let textSizes = ReaderTextSize.steps
    /// What Actual Size returns to.
    public static let standardTextSizeStep = ReaderTextSize.steps.firstIndex(of: ReaderTextSize.standard) ?? 0
    static let sidebarWidths: ClosedRange<Double> = 180...280

    private enum Key {
        static let textSizeStep = "textSizeStep", hidesReadItems = "hidesReadItems", sidebarWidth = "sidebarWidth"
        static let lastScope = "lastScope", lastItem = "lastItem"
        static let hasCompletedWelcome = "hasCompletedWelcome"
        static let highlightColor = "highlightColor"
    }

    @ObservationIgnored private let defaults: UserDefaults

    public var textSizeStep: Int { didSet { defaults.set(textSizeStep, forKey: Key.textSizeStep) } }
    /// View ▸ Hide Read Items.
    public var hidesReadItems: Bool { didSet { defaults.set(hidesReadItems, forKey: Key.hidesReadItems) } }
    /// Connecting or choosing the plain reader dismisses first-launch setup for future launches.
    public var hasCompletedWelcome: Bool { didSet { defaults.set(hasCompletedWelcome, forKey: Key.hasCompletedWelcome) } }
    public var highlightColor: HighlightColor { didSet { defaults.set(highlightColor.rawValue, forKey: Key.highlightColor) } }
    /// Written while the owner drags the divider and read once at launch, so it is not observed:
    /// feeding it back into the split view during layout would make the sidebar's table re-enter itself.
    @ObservationIgnored public var sidebarWidth: Double { didSet { defaults.set(sidebarWidth, forKey: Key.sidebarWidth) } }
    /// The sidebar selection and the selected row at the last quit: "all", "pin:12" or "source:3", and an item id.
    var lastScope: String? { didSet { defaults.set(lastScope, forKey: Key.lastScope) } }
    var lastItemID: Int64? { didSet { defaults.set(lastItemID.map { NSNumber(value: $0) }, forKey: Key.lastItem) } }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let step = defaults.object(forKey: Key.textSizeStep) as? Int ?? Self.standardTextSizeStep
        textSizeStep = min(max(step, 0), Self.textSizes.count - 1)
        hidesReadItems = defaults.bool(forKey: Key.hidesReadItems)
        hasCompletedWelcome = defaults.bool(forKey: Key.hasCompletedWelcome)
        highlightColor = defaults.string(forKey: Key.highlightColor).flatMap(HighlightColor.init(rawValue:)) ?? .yellow
        let width = defaults.object(forKey: Key.sidebarWidth) as? Double ?? 220
        sidebarWidth = min(max(width, Self.sidebarWidths.lowerBound), Self.sidebarWidths.upperBound)
        lastScope = defaults.string(forKey: Key.lastScope)
        lastItemID = (defaults.object(forKey: Key.lastItem) as? NSNumber)?.int64Value
    }

    public var textSize: CGFloat { Self.textSizes[textSizeStep] }
    public var canMakeTextBigger: Bool { textSizeStep < Self.textSizes.count - 1 }
    public var canMakeTextSmaller: Bool { textSizeStep > 0 }
    public func makeTextBigger() { if canMakeTextBigger { textSizeStep += 1 } }
    public func makeTextSmaller() { if canMakeTextSmaller { textSizeStep -= 1 } }
    public func useActualSize() { textSizeStep = Self.standardTextSizeStep }
}
