import AppKit

/// Copy Link and Copy Feed URL: a URL for apps that take links, the same text for everything else.
@MainActor
enum Pasteboard {
    static func copy(_ url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
        pasteboard.setString(url.absoluteString, forType: .string)
    }
}
