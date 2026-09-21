import BeamEngine
import BeamModels
import Foundation

/// PRODUCT.md MUST 4 — Pins: twenty new items cost exactly twenty requests whatever the pin count, because
/// every pin rides in the same request; an edited title costs exactly one more.
@MainActor
enum PinsCheck {
    static let name = "pins"

    static let address = "https://pins.example/feed.xml"

    static func run(_ report: inout CheckReport, offline: Bool, key: String?) async {
        report.section("Pins (MUST 4) — one request per item, whatever the pin count")
        for pins in [1, 3, 9] {
            await cost(&report, pins: pins)
        }
        report.section("Pins (MUST 4) — what a pin shows")
        await behaviour(&report)
    }

    /// Twenty items arrive at a library that already has `pins` pins.
    private static func cost(_ report: inout CheckReport, pins: Int) async {
        let web = StubWeb()
        web.serve(address, Fixtures.rss(title: "Pinned", site: "https://pins.example", count: 0))
        let jev = StubJev()
        guard let lab = try? await Lab.offline(starters: [Lab.candidate("Pinned", address)], jev: jev, web: web) else {
            report.expect(false, "an engine with \(pins) pins")
            return
        }
        for index in 0..<pins {
            _ = await lab.engine.pin(sentence: "\(Fixtures.sentence) \(index)")
        }
        report.expectEqual(jev.count, 0, "\(pins) pins over an empty library cost nothing")

        jev.reset()
        web.serve(address, Fixtures.rss(title: "Pinned", site: "https://pins.example", count: 20, found: 6, unsure: 4))
        await lab.engine.refresh()
        report.expectEqual(jev.count, 20, "20 new items cost exactly 20 requests with \(pins) pins")
        report.expect(jev.all.allSatisfy { $0.frames.count == pins },
                      "every request carries all \(pins) pins at once",
                      detail: "frames per request: \(Set(jev.all.map(\.frames.count)).sorted())")

        // The same twenty again: nothing has changed, so nothing is sent.
        jev.reset()
        await lab.engine.refresh()
        report.expectEqual(jev.count, 0, "refreshing again with nothing new sends nothing")

        // One edited title changes that item's judged text, and only that item is judged again.
        jev.reset()
        web.serve(address, edited(count: 20))
        await lab.engine.refresh()
        report.expectEqual(jev.count, 1, "one edited title costs exactly one more request")
    }

    private static func behaviour(_ report: inout CheckReport) async {
        let web = StubWeb()
        web.serve(address, Fixtures.rss(title: "Pinned", site: "https://pins.example", count: 30, found: 8, unsure: 6))
        let jev = StubJev()
        guard let lab = try? await Lab.offline(starters: [Lab.candidate("Pinned", address)], jev: jev, web: web) else {
            report.expect(false, "an engine to pin in")
            return
        }
        let outcome = await lab.engine.pin(sentence: Fixtures.sentence)
        guard case let .pinned(pin) = outcome else {
            report.expect(false, "a sentence pins")
            return
        }
        report.expect(true, "a sentence pins")
        report.expectEqual(jev.count, 30, "a new pin judges what is already there, once per item")

        let listed = await lab.search(nil, scope: .pin(pin.id))
        let rows = listed.last?.rows ?? []
        report.expectEqual(rows.count, 8, "a pin lists exactly its found rows")
        report.expect(rows.allSatisfy { !$0.isMarked }, "a pin's rows carry no mark")
        report.expect(isByDate(rows), "and are ordered by date, newest first")
        report.expectEqual(listed.last?.lastNewRowID, rows.last?.id,
                           "the separator runs under the last row new since the pin was viewed")

        let sidebar = await lab.sidebar()
        report.expectEqual(sidebar.pins.first?.newFound, 8, "the pin's badge counts what it found")
        await lab.engine.markPinViewed(id: pin.id)
        let viewed = await lab.sidebar()
        report.expectEqual(viewed.pins.first?.newFound, 0, "leaving the pin empties its badge")

        // Nine pins maximum.
        for index in 1..<Pin.maximum {
            _ = await lab.engine.pin(sentence: "another sentence \(index)")
        }
        let tenth = await lab.engine.pin(sentence: "one pin too many")
        if case .limitReached = tenth {
            report.expect(true, "the tenth pin is refused")
        } else {
            report.expect(false, "the tenth pin is refused")
        }

        // Removal has no alert: Undo is the safety net.
        await lab.engine.removePin(id: pin.id)
        let without = await lab.sidebar()
        report.expectEqual(without.pins.count, Pin.maximum - 1, "removing a pin removes it")
        report.expectEqual(lab.engine.undoTitle, "Undo Remove Pin", "and Undo offers to put it back")
        let undone = await lab.engine.undo()
        let restored = await lab.sidebar()
        report.expectEqual(undone, "Undo Remove Pin", "Undo says what it undid")
        report.expectEqual(restored.pins.count, Pin.maximum, "and the pin is back")
    }

    private static func isByDate(_ rows: [Row]) -> Bool {
        zip(rows, rows.dropFirst()).allSatisfy { $0.item.sortDate >= $1.item.sortDate }
    }

    /// The same feed with one title changed: the item keeps its row and its read state, and its judged text is new.
    private static func edited(count: Int) -> String {
        var body = Fixtures.rss(title: "Pinned", site: "https://pins.example", count: count, found: 6, unsure: 4)
        body = body.replacingOccurrences(of: "\(Fixtures.Relevance.found.title) 0",
                                         with: "\(Fixtures.Relevance.found.title) 0, revised")
        return body
    }
}
