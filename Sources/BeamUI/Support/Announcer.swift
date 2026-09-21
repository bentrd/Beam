import AppKit

/// Polite VoiceOver announcements: one when a run settles, one for each popover or sheet status line.
/// Never a count-up, and never an interruption.
@MainActor
enum Announcer {
    static func say(_ text: String) {
        guard !text.isEmpty, NSWorkspace.shared.isVoiceOverEnabled, let element = NSApp.mainWindow ?? NSApp.keyWindow else { return }
        NSAccessibility.post(element: element, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }
}
