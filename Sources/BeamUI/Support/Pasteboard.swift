import AppKit
import CoreTransferable

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

/// What ⌘C puts on the pasteboard, on a row and on a source. Copy Link, Copy Feed URL and ⌘C are one command
/// (DESIGN.md section 10), so ⌘C carries both flavours `Pasteboard.copy(_:)` writes: the link for apps that take
/// one, the same text for everything else.
struct CopiedLink: Transferable {
    let url: URL

    init(_ url: URL) { self.url = url }

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.url)
        ProxyRepresentation(exporting: \.url.absoluteString)
    }
}
