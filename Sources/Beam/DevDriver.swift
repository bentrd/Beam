// TEMPORARY: development driver, deleted before hand-off. Drives the real window with synthesized events.
import AppKit
import BeamModels
import BeamUI

@MainActor
enum DevDriver {
    static weak var model: AppModel?
    static var window: NSWindow? { NSApp.windows.first { $0.isVisible && $0.contentView != nil && $0.frame.width > 600 } }

    static func startIfAsked() {
        guard let script = UserDefaults.standard.string(forKey: "devdrive") else { return }
        setvbuf(stdout, nil, _IONBF, 0)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.0))
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .seconds(0.7))
            print("active=\(NSApp.isActive) main=\(NSApp.mainWindow?.title ?? "nil") key=\(NSApp.keyWindow?.title ?? "nil")")
            switch script {
            case "menus": dumpMenus()
            case "keys": await keys()
            case "pin1": model?.selectPin(at: 0)
            case "lit":
                model?.selectPin(at: 0); await pause(0.6)
                if let id = model?.rows.first?.id { model?.open(id, trigger: .key) }
            case "searchlit":
                typeText("running models locally on a laptop"); returnKey(); await pause(0.8); returnKey()
            case "streaming":
                typeText("machine learning research papers"); returnKey()
            case "source":
                model?.select(.source(4))
            case "addsource":
                model?.presentAddSource()
            case "keysheet":
                typeText("anything at all"); returnKey()
            case "narrow":
                window?.setContentSize(NSSize(width: 840, height: 560)); await pause(0.5); model?.select(.source(4))
            case "showfile": showMenu(1)
            case "showview": showMenu(3)
            case "showedit": showMenu(2)
            case "search": await search()
            case "click": await click()
            case "sidebar": await sidebar()
            default: break
            }
        }
    }

    static func log(_ label: String) {
        guard let m = model else { return }
        let responder = window?.firstResponder.map { String(describing: Swift.type(of: $0)) } ?? "nil"
        print("[\(label)] sentence=\(m.sentence ?? "nil") scope=\(m.scope) rows=\(m.rows.count) sel=\(m.selectedItemID.map(String.init) ?? "nil") open=\(m.openItemID.map(String.init) ?? "nil") phase=\(m.readerSnapshot?.phase.rawValue ?? "nil") focus=\(m.focusedPane.map { "\($0)" } ?? "nil") fieldFocused=\(m.isSearchFieldFocused) responder=\(responder) foot=\(m.listFoot.text)|\(m.listFoot.actionTitle ?? "") empty=\(m.emptyMessage ?? "nil") title=\(NSApp.mainWindow?.title ?? "nil")")
        fflush(stdout)
    }

    static func key(_ code: UInt16, _ chars: String, flags: NSEvent.ModifierFlags = []) {
        guard let window else { return print("no main window") }
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            if let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                            windowNumber: window.windowNumber, context: nil, characters: chars,
                                            charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code) {
                NSApp.sendEvent(event)
            }
        }
    }
    static func returnKey() { key(36, "\r") }
    static func down() { key(125, String(UnicodeScalar(NSDownArrowFunctionKey)!), flags: [.function, .numericPad]) }
    static func up() { key(126, String(UnicodeScalar(NSUpArrowFunctionKey)!), flags: [.function, .numericPad]) }
    static func space() { key(49, " ") }
    static func escape() { key(53, "\u{1B}") }

    static func typeText(_ text: String) {
        guard let editor = window?.firstResponder as? NSTextView else { return print("first responder is not a text view: \(String(describing: window?.firstResponder))") }
        editor.insertText(text, replacementRange: editor.selectedRange())
    }

    static func pause(_ seconds: Double) async { try? await Task.sleep(for: .seconds(seconds)) }

    static func search() async {
        log("launch")
        typeText("machine learning models")
        returnKey(); await pause(0.1); log("after Return (running)")
        await pause(0.5); log("t+0.6")
        await pause(2.5); log("settled")
        returnKey(); await pause(0.6); log("Return again: open top")
        down(); await pause(0.3); log("Down: preview next")
        down(); await pause(0.3); log("Down: preview next")
        space(); await pause(0.8); log("Space: open")
        returnKey(); await pause(0.3); log("Return on open row (no change)")
        up(); await pause(0.2); up(); await pause(0.2); log("Up x2: first row")
        up(); await pause(0.3); log("Up from first row: field")
        escape(); await pause(0.5); log("Esc: cleared")
        print("DONE"); fflush(stdout)
    }

    static func tables(in view: NSView) -> [NSTableView] {
        (view as? NSTableView).map { [$0] } ?? [] + view.subviews.flatMap(tables)
    }

    static func click(row: Int, in table: NSTableView, count: Int = 1) {
        guard let window = table.window else { return }
        let rect = table.rect(ofRow: row)
        let point = table.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: count, pressure: 1) {
                NSApp.postEvent(event, atStart: false)
            }
        }
    }

    static func click() async {
        guard let root = window?.contentView else { return print("no window: \(NSApp.windows.map { "\($0.title) \($0.frame) \($0.isVisible)" })") }
        let all = allTables(root)
        print("tables: \(all.map { "\($0.numberOfRows) rows, \(Swift.type(of: $0))" })")
        guard let list = all.max(by: { $0.numberOfRows < $1.numberOfRows }) else { return }
        click(row: 2, in: list); await pause(0.8); log("clicked row 2")
        down(); await pause(0.3); log("Down after click")
        click(row: 6, in: list); await pause(0.8); log("clicked row 6")
        click(row: 6, in: list, count: 2); await pause(0.8); log("double-clicked row 6")
        dumpMenus()
        print("DONE"); fflush(stdout)
    }

    static func allTables(_ view: NSView) -> [NSTableView] {
        var found: [NSTableView] = []
        if let table = view as? NSTableView { found.append(table) }
        for child in view.subviews { found += allTables(child) }
        return found
    }

    static func sidebar() async {
        guard let root = window?.contentView else { return print("no window: \(NSApp.windows.map { "\($0.title) \($0.frame) \($0.isVisible)" })") }
        let all = allTables(root)
        guard let side = all.min(by: { $0.numberOfRows < $1.numberOfRows }) else { return }
        print("sidebar rows: \(side.numberOfRows)")
        click(row: 2, in: side); await pause(0.8); log("clicked pin 1")
        click(row: 8, in: side); await pause(0.8); log("clicked a source")
        dumpMenus()
        key(29, "à", flags: .command); await pause(0.6); log("cmd-à (All Items)")
        key(18, "&", flags: .command); await pause(0.6); log("cmd-& (pin 1)")
        dumpMenus()
        print("DONE"); fflush(stdout)
    }

    static func undoTitle() -> String { NSApp.mainMenu?.item(at: 2)?.submenu.map { $0.delegate?.menuNeedsUpdate?($0); $0.update(); return $0.items.first.map { "\($0.title)\($0.isEnabled ? "" : " (disabled)")" } ?? "?" } ?? "?" }

    static func keys() async {
        guard let m = model, let root = window?.contentView else { return }
        print("textStep=\(m.preferences.textSizeStep)")
        key(24, "=", flags: .command); await pause(0.3); print("after cmd-= textStep=\(m.preferences.textSizeStep)")
        key(24, "+", flags: [.command, .shift]); await pause(0.3); print("after cmd-shift-+ textStep=\(m.preferences.textSizeStep)")
        key(27, "-", flags: .command); await pause(0.3); key(27, "-", flags: .command); await pause(0.3); print("after cmd-- x2 textStep=\(m.preferences.textSizeStep)")
        guard let side = allTables(root).min(by: { $0.numberOfRows < $1.numberOfRows }) else { return }
        click(row: 3, in: side); await pause(0.8); log("clicked pin 2")
        key(37, "l", flags: .command); await pause(0.4); log("cmd-L")
        key(51, "\u{7F}", flags: .command); await pause(0.5); log("cmd-delete with field focused (must not remove)")
        click(row: 3, in: side); await pause(0.5)
        dumpMenus()
        key(51, "\u{7F}", flags: .command); await pause(0.8); log("cmd-delete (7F) with sidebar focused")
        print("pins=\(m.sidebar.pins.count)")
        key(51, "\u{8}", flags: .command); await pause(0.8); log("cmd-delete (08) with sidebar focused")
        print("pins=\(m.sidebar.pins.map(\.pin.sentence)) undo=\(undoTitle())")
        key(6, "z", flags: .command); await pause(0.8)
        print("after cmd-Z pins=\(m.sidebar.pins.map(\.pin.sentence)) undo=\(undoTitle())")
        key(2, "d", flags: .command); await pause(0.8); log("cmd-D with no sentence")
        print("DONE")
    }

    static func showMenu(_ index: Int) {
        guard let menu = NSApp.mainMenu?.item(at: index)?.submenu, let view = window?.contentView else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { menu.cancelTracking() }
        menu.popUp(positioning: nil, at: NSPoint(x: 330, y: 30), in: view)
    }

    static func dumpMenus() {
        func dump(_ menu: NSMenu, indent: String) {
            menu.delegate?.menuNeedsUpdate?(menu)
            menu.update()
            for item in menu.items {
                if item.isSeparatorItem { print("\(indent)---\(item.isHidden ? " (hidden)" : "")"); continue }
                if item.isHidden { print("\(indent)(hidden) \(item.title)"); continue }
                var mods = ""
                let f = item.keyEquivalentModifierMask
                if f.contains(.control) { mods += "⌃" }; if f.contains(.option) { mods += "⌥" }; if f.contains(.shift) { mods += "⇧" }; if f.contains(.command) { mods += "⌘" }
                let key = item.keyEquivalent.isEmpty ? "" : "  [\(mods)\(item.keyEquivalent == "\u{8}" ? "⌫" : item.keyEquivalent)]"
                print("\(indent)\(item.title)\(key)\(item.isEnabled ? "" : "  (disabled)")\(item.state == .on ? "  ✓" : "")")
                if let sub = item.submenu { dump(sub, indent: indent + "    ") }
            }
        }
        if let main = NSApp.mainMenu { dump(main, indent: "") }
        fflush(stdout)
    }
}
