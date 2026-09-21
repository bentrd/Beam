import AppKit

/// The last few menu items SwiftUI cannot express, so that the menu bar reads exactly as DESIGN.md section 10 lists it.
///
/// Everything Beam owns is a real `Commands` item in `BeamCommands`. What is left here is AppKit's own doing:
/// the window item it inserts into File, the full-screen item it does not insert into View, and the separators
/// that fall either side of an empty group. Every step is idempotent, and every one fails silently if a future
/// macOS names things differently: a tidier must never be the reason a menu bar is missing.
///
/// Nothing is ever removed. SwiftUI keeps its own account of the items it put in these menus, and taking one out
/// from under it stops it updating the rest (the View menu loses its pins). A hidden item is not drawn, which is
/// all that is being asked for here.
@MainActor
enum MainMenu {
    private enum Title {
        static let closeWindow = "Close Window"
        static let enterFullScreen = "Enter Full Screen"
        static let exitFullScreen = "Exit Full Screen"
        /// AppKit adds this submenu to Edit because Beam has secure fields (the key sheet and Settings).
        static let autoFill = "AutoFill"
    }

    /// The Edit menu of DESIGN.md section 10 is Undo, Redo, Cut, Copy, Paste, Select All, Find and Speech.
    /// Dictation and Emoji & Symbols are kept out by the two defaults `main.swift` registers; these two have no
    /// such switch. AutoFill offers to fill a TypeSafe key from a password manager, which is not a thing Beam asks
    /// for: the key sheet is the one place a key is typed, once. Delete arrives inside AppKit's pasteboard group
    /// and does what ⌫ already does in the one or two fields Beam has, under a title section 10 does not list.
    private static let unlistedEditItems: [(title: String?, action: Selector?)] = [
        (Title.autoFill, nil),
        (nil, #selector(NSText.delete(_:))),
    ]

    /// Menus whose separators are ours to tidy. The Window menu is left alone: AppKit fills its tail at display time.
    private static let tidiedMenus = ["File", "Edit", "View"]

    private static var fullScreenObservers: [NSObjectProtocol] = []
    /// The item added below, kept so the two full-screen notifications can retitle it without capturing it.
    private static weak var fullScreenItem: NSMenuItem?

    /// Call once the menu bar exists, and again whenever it may have been rebuilt.
    static func tidy() {
        guard let main = NSApp.mainMenu else { return }
        populate(main)
        renameCloseItem(in: main)
        addFullScreenItemIfMissing(to: main)
        hideUnlistedEditItems(in: main)
        for title in tidiedMenus {
            if let menu = menu(titled: title, in: main) { collapseSeparators(in: menu) }
        }
    }

    // MARK: Steps

    /// SwiftUI fills a menu from its delegate, the moment before it is drawn, so an untouched menu bar holds
    /// little more than titles. Asking for that fill first is what lets the steps below see the real items —
    /// and it is exactly what AppKit does when the owner reaches for the menu bar.
    private static func populate(_ main: NSMenu) {
        main.delegate?.menuNeedsUpdate?(main)
        for submenu in main.items.compactMap(\.submenu) {
            submenu.delegate?.menuNeedsUpdate?(submenu)
            for nested in submenu.items.compactMap(\.submenu) { nested.delegate?.menuNeedsUpdate?(nested) }
        }
    }

    /// AppKit's item reads "Close"; DESIGN.md section 10 names it "Close Window", because ⌘W closes the window
    /// and leaves Beam running. Its Option-key alternate ("Close All") is AppKit's and stays as it is.
    private static func renameCloseItem(in main: NSMenu) {
        guard let file = menu(titled: "File", in: main),
              let close = file.items.first(where: { $0.action == #selector(NSWindow.performClose(_:)) && !$0.isAlternate }),
              close.title != Title.closeWindow
        else { return }
        close.title = Title.closeWindow
    }

    /// A SwiftUI `WindowGroup` gives the View menu no full-screen item, even once the window allows full screen
    /// (measured), and DESIGN.md section 10 ends the View menu with one. It goes to the first responder, as AppKit's
    /// own does, so the window answers for it and disables it when there is no window.
    private static func addFullScreenItemIfMissing(to main: NSMenu) {
        let toggle = #selector(NSWindow.toggleFullScreen(_:))
        guard !main.items.contains(where: { $0.submenu?.items.contains { $0.action == toggle } ?? false }),
              let view = menu(titled: "View", in: main)
        else { return }
        let item = NSMenuItem(title: Title.enterFullScreen, action: toggle, keyEquivalent: "f")
        item.keyEquivalentModifierMask = [.control, .command]
        view.addItem(item)
        fullScreenItem = item
        watchFullScreen()
    }

    /// AppKit retitles its own full-screen item; ours has to be told, so the menu never offers to enter
    /// a full screen the window is already in.
    private static func watchFullScreen() {
        guard fullScreenObservers.isEmpty else { return }
        let center = NotificationCenter.default
        for (name, title) in [(NSWindow.didEnterFullScreenNotification, Title.exitFullScreen),
                              (NSWindow.didExitFullScreenNotification, Title.enterFullScreen)] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { fullScreenItem?.title = title }
            }
            fullScreenObservers.append(token)
        }
    }

    /// Hides the items AppKit puts in Edit that section 10 does not list. Nothing is removed: a hidden item is
    /// not drawn, and its action still answers the key that reaches it through the responder chain.
    private static func hideUnlistedEditItems(in main: NSMenu) {
        guard let edit = menu(titled: "Edit", in: main) else { return }
        for item in edit.items {
            let matchesTitle = unlistedEditItems.contains { $0.title == item.title && item.submenu != nil }
            let matchesAction = item.action.map { action in unlistedEditItems.contains { $0.action == action } } ?? false
            if matchesTitle || matchesAction { item.isHidden = true }
        }
    }

    /// One separator between groups, none at either end. A group that turns out to be empty (AppKit's window items,
    /// when Beam has replaced them all) otherwise leaves two rules with nothing between them.
    ///
    /// A separator that is wanted again later — SwiftUI fills an empty group as the model changes — is shown again,
    /// so this both hides and unhides and can run as often as it likes.
    private static func collapseSeparators(in menu: NSMenu) {
        var previousDrawnWasSeparator = true                  // the top of a menu counts as a rule already drawn
        for item in menu.items where !item.isAlternate {
            if item.isSeparatorItem {
                item.isHidden = previousDrawnWasSeparator
                previousDrawnWasSeparator = !item.isHidden
            } else if !item.isHidden {
                previousDrawnWasSeparator = false
            }
        }
        // Nothing but separators after the last item that draws.
        for item in menu.items.reversed() where !item.isAlternate {
            guard item.isSeparatorItem || item.isHidden else { break }
            item.isHidden = true
        }
    }

    // MARK: Lookup

    static func menu(titled title: String, in main: NSMenu) -> NSMenu? {
        main.items.first { $0.submenu?.title == title || $0.title == title }?.submenu
    }
}
