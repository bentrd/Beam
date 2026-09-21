import AppKit
import BeamModels
import BeamUI

/// `Beam -fake YES -menucheck YES`: the menu bar against DESIGN.md section 10 and the owner's addendum.
///
/// A menu bar exists only in a running app, so this check launches one, waits for the window and the first sidebar
/// snapshot, asserts, prints the whole tree for a human to read, and exits with the report's code.
/// It is the one part of the shell `-selfcheck` cannot reach, and it is where "every shortcut is a menu item" is proved.
@MainActor
enum MenuCheck {
    /// One item DESIGN.md section 10 requires. A toggling item is named by both of its titles.
    private struct Expected {
        let titles: [String]
        let key: String?
        let modifiers: NSEvent.ModifierFlags
        /// nil when the state at launch says nothing; true or false when section 10 fixes it.
        let isEnabled: Bool?

        init(_ titles: String..., key: String? = nil, modifiers: NSEvent.ModifierFlags = .command, isEnabled: Bool? = nil) {
            self.titles = titles; self.key = key; self.modifiers = modifiers; self.isEnabled = isEnabled
        }
    }

    static func runIfAsked(for model: AppModel) {
        guard UserDefaults.standard.bool(forKey: "menucheck") else { return }
        setvbuf(stdout, nil, _IONBF, 0)
        Task { @MainActor in
            // A menu bar is only kept current for the active app, and the pins arrive with the first sidebar
            // snapshot, so the check asserts on a window that is up and in front, as the owner's would be.
            try? await Task.sleep(for: .seconds(1))
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { $0.isVisible }?.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .seconds(1.5))
            exit(run(for: model))
        }
    }

    private static func run(for model: AppModel) -> Int32 {
        var report = CheckReport("ui-menus")
        guard let main = NSApp.mainMenu else {
            report.expect(false, "the app has a menu bar")
            return report.finish()
        }
        MainMenu.tidy()                                     // which also fills every menu from its delegate
        main.items.compactMap(\.submenu).forEach { $0.update() }

        report.section("The six standard menus, and nothing else (section 10)")
        report.expectEqual(main.items.compactMap(\.submenu).map(\.title), ["Beam", "File", "Edit", "View", "Window", "Help"],
                           "six menus, in order")
        let everyItem = items(of: main)
        let shown = everyItem.filter { !$0.isHidden }
        let forbidden = ["New Window", "New Tab", "Show Tab Bar", "Show All Tabs", "Merge All Windows", "Move Tab to New Window",
                         "Writing Tools", "Start Dictation…", "Emoji & Symbols", "AutoFill", "Delete"]
        for title in forbidden {
            report.expect(!shown.contains { $0.title == title }, "no \"\(title)\" item")
        }
        for title in ["File", "Edit", "View"] {
            let items = MainMenu.menu(titled: title, in: main)?.items.filter { !$0.isHidden } ?? []
            report.expect(items.last?.isSeparatorItem == false, "\(title) does not end on a separator")
            report.expect(!zip(items, items.dropFirst()).contains { $0.isSeparatorItem && $1.isSeparatorItem },
                          "\(title) has no empty group")
        }

        report.section("Beam")
        check(&report, "Beam", in: main, [
            Expected("About Beam", modifiers: []),
            Expected("Settings…", key: ","),
            Expected("Services", modifiers: []),
            Expected("Hide Beam", key: "h"),
            Expected("Hide Others", key: "h", modifiers: [.command, .option]),
            Expected("Show All", modifiers: []),
            Expected("Quit Beam", key: "q"),
        ])

        report.section("File")
        check(&report, "File", in: main, [
            Expected("Add Source…", key: "n", isEnabled: true),
            Expected("Open Original", key: "o", isEnabled: false),
            Expected("Share", modifiers: []),
            Expected("Mark as Read", "Mark as Unread", key: "u", modifiers: [.command, .shift], isEnabled: false),
            Expected("Mark All as Read", key: "k"),
            Expected("Pin Sentence", "Unpin Sentence", key: "d", isEnabled: false),
            Expected("Move Pin Up", key: "\u{F700}", modifiers: [.command, .option], isEnabled: false),
            Expected("Move Pin Down", key: "\u{F701}", modifiers: [.command, .option], isEnabled: false),
            Expected("Remove Pin", "Remove Source", key: "\u{8}", isEnabled: false),
            Expected("Refresh", key: "r", isEnabled: true),
            Expected("Close Window", key: "w"),
        ])

        report.section("Edit")
        check(&report, "Edit", in: main, [
            Expected("Undo", key: "z"),
            Expected("Redo", key: "z", modifiers: [.command, .shift]),
            Expected("Cut", key: "x"),
            Expected("Copy", key: "c"),
            Expected("Paste", key: "v"),
            Expected("Select All", key: "a"),
            Expected("Find", modifiers: []),
            Expected("Speech", modifiers: []),
        ])

        report.section("Find")
        let edit = MainMenu.menu(titled: "Edit", in: main)
        let find = edit?.items.first { $0.title == "Find" }?.submenu
        find?.update()

        check(&report, find, named: "Find", [
            Expected("Search All Items", key: "f", modifiers: [.command, .option], isEnabled: true),
            Expected("Find by Meaning…", key: "f", isEnabled: false),
            Expected("Find Next", key: "g", isEnabled: false),
            Expected("Find Previous", key: "g", modifiers: [.command, .shift], isEnabled: false),
            Expected("Use Selection for Find", key: "e", isEnabled: false),
            Expected("Jump to Selection", key: "j", isEnabled: false),
        ])

        report.section("View")
        check(&report, "View", in: main, [
            Expected("Show Sidebar", "Hide Sidebar", key: "s", modifiers: [.control, .command]),
            Expected("All Items", key: "0"),
            Expected("Hide Read Items", key: "r", modifiers: [.command, .option]),
            Expected("Make Text Bigger", key: "+"),
            Expected("Make Text Smaller", key: "-"),
            Expected("Actual Size", modifiers: []),
            Expected("Enter Full Screen", "Exit Full Screen", key: "f", modifiers: [.control, .command], isEnabled: true),
        ])
        checkPins(&report, in: main, model: model)

        report.section("Window")
        check(&report, "Window", in: main, [
            Expected("Minimize", key: "m"),
            Expected("Zoom", modifiers: []),
            Expected("Bring All to Front", modifiers: []),
        ])

        report.section("Every shortcut is unique")
        checkUniqueShortcuts(&report, everyItem)

        print("")
        describe(main, indent: "")
        return report.finish()
    }

    // MARK: Steps

    private static func check(_ report: inout CheckReport, _ title: String, in main: NSMenu, _ expected: [Expected]) {
        check(&report, MainMenu.menu(titled: title, in: main), named: title, expected)
    }

    private static func check(_ report: inout CheckReport, _ menu: NSMenu?, named name: String, _ expected: [Expected]) {
        guard let menu else { return report.expect(false, "the \(name) menu exists") }
        var previous = -1
        for wanted in expected {
            let where_ = "\(name) ▸ \(wanted.titles.joined(separator: " / "))"
            guard let index = menu.items.firstIndex(where: { wanted.titles.contains($0.title) }) else {
                report.expect(false, "\(where_) is there")
                continue
            }
            report.expect(true, "\(where_) is there")
            report.expect(index > previous, "\(where_) is in order")
            previous = index
            let item = menu.items[index]
            if let key = wanted.key {
                // AppKit localises a key equivalent for the current layout (⌘0 is ⌘à on AZERTY), so a digit or a
                // letter is only required to be one character under the right modifiers.
                let sameKey = item.keyEquivalent == key || (key.count == 1 && item.keyEquivalent.count == 1 && !key.first!.isLetter)
                report.expect(sameKey, "\(where_) has its key", detail: "got \"\(item.keyEquivalent)\", expected \"\(key)\"")
                report.expectEqual(item.keyEquivalentModifierMask, wanted.modifiers, "\(where_) has its modifiers")
            } else {
                report.expect(item.keyEquivalent.isEmpty, "\(where_) carries no shortcut")
            }
            if let isEnabled = wanted.isEnabled {
                report.expectEqual(item.isEnabled, isEnabled, "\(where_) is \(isEnabled ? "enabled" : "disabled") with nothing selected")
            }
        }
    }

    /// View lists the pin sentences in sidebar order, and their order sets ⌘1 to ⌘9.
    private static func checkPins(_ report: inout CheckReport, in main: NSMenu, model: AppModel) {
        guard let view = MainMenu.menu(titled: "View", in: main) else { return }
        let sentences = model.sidebar.pins.prefix(Pin.maximum).map(\.pin.sentence)
        let titles = view.items.map(\.title)
        report.expect(!sentences.isEmpty, "the fake session has pins to list")
        report.expect(sentences.allSatisfy(titles.contains), "every pin is a View item", detail: "\(sentences)")
        let shown = titles.filter(sentences.contains)
        report.expectEqual(shown, Array(sentences), "the pins are in sidebar order")
        for (position, sentence) in sentences.enumerated() {
            guard let item = view.items.first(where: { $0.title == sentence }) else { continue }
            report.expect(item.keyEquivalent.count == 1 && item.keyEquivalentModifierMask == .command,
                          "pin \(position + 1) answers to one ⌘ key", detail: "\"\(item.keyEquivalent)\"")
        }
    }

    /// Two items on the same keys means one of them never fires. The list's own ⌘0 to ⌘9 make this easy to get wrong.
    private static func checkUniqueShortcuts(_ report: inout CheckReport, _ items: [NSMenuItem]) {
        var seen: [String: String] = [:]
        var clashes: [String] = []
        for item in items where !item.keyEquivalent.isEmpty && !item.isHidden {
            let shortcut = "\(item.keyEquivalentModifierMask.rawValue)-\(item.keyEquivalent)"
            if let other = seen[shortcut], other != item.title { clashes.append("\(other) / \(item.title)") }
            seen[shortcut] = item.title
        }
        report.expect(clashes.isEmpty, "no two items share a shortcut", detail: clashes.joined(separator: ", "))
    }

    // MARK: Reading the menu bar

    private static func items(of menu: NSMenu) -> [NSMenuItem] {
        menu.items + menu.items.compactMap(\.submenu).flatMap(items(of:))
    }

    private static func describe(_ menu: NSMenu, indent: String) {
        for item in menu.items {
            let shortcut = item.keyEquivalent.isEmpty ? "" : "  [\(glyphs(item))]"
            let state = (item.isSeparatorItem ? "---" : item.title + shortcut
                + (item.isEnabled ? "" : "  (disabled)") + (item.state == .on ? "  ✓" : "")) + (item.isHidden ? "  (hidden)" : "")
            print(indent + state)
            item.submenu.map { describe($0, indent: indent + "    ") }
        }
    }

    private static func glyphs(_ item: NSMenuItem) -> String {
        let flags = item.keyEquivalentModifierMask
        var out = ""
        if flags.contains(.control) { out += "⌃" }
        if flags.contains(.option) { out += "⌥" }
        if flags.contains(.shift) { out += "⇧" }
        if flags.contains(.command) { out += "⌘" }
        let names = ["\u{8}": "⌫", "\u{7F}": "⌫", "\u{F700}": "↑", "\u{F701}": "↓", "\r": "↩", " ": "Space"]
        return out + (names[item.keyEquivalent] ?? item.keyEquivalent)
    }
}
