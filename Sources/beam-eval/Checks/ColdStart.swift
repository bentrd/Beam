import BeamEngine
import BeamFeeds
import BeamModels
import Foundation

/// PRODUCT.md MUST 1 — Cold start: wiped and keyless, 20+ items within 5 s, one of them opens readable,
/// and not one byte goes to TypeSafe.
@MainActor
enum ColdStartCheck {
    static let name = "cold-start"

    static func run(_ report: inout CheckReport, offline: Bool, key: String?) async {
        report.section("Cold start (MUST 1) — fixtures")
        await fromFixtures(&report)
        guard !offline else {
            report.skip("cold start on the real web", because: "--offline")
            return
        }
        report.section("Cold start (MUST 1) — the real starter sources")
        await fromTheWeb(&report)
    }

    private static func fromFixtures(_ report: inout CheckReport) async {
        let web = StubWeb()
        web.serve("https://a.example/feed.xml", Fixtures.rss(title: "Fixture A", site: "https://a.example", count: 14, found: 4, unsure: 4))
        web.serve("https://b.example/feed.xml", Fixtures.rss(title: "Fixture B", site: "https://b.example", count: 14,
                                                             found: 2, unsure: 2, guidPrefix: "post"))
        let pages = StubPages()
        pages.serve("https://a.example/item-0", html: Fixtures.article(title: "The first item", paragraphs: Array(repeating: .nothing, count: 14)))
        let jev = StubJev()

        let started = ContinuousClock.now
        guard let lab = try? await Lab.offline(starters: [Lab.candidate("Fixture A", "https://a.example/feed.xml"),
                                                          Lab.candidate("Fixture B", "https://b.example/feed.xml")],
                                               hasKey: false, jev: jev, web: web, pages: pages) else {
            report.expect(false, "a wiped launch builds an engine")
            return
        }
        let listed = await lab.search(nil)
        let ready = ContinuousClock.now - started
        let rows = listed.last?.rows ?? []

        report.expect(rows.count >= 20, "20 or more items are listed", detail: "\(rows.count) rows")
        report.expect(ready < .seconds(5), "they are there within 5 s", detail: Wait.milliseconds(ready))
        report.expectEqual(jev.count, 0, "a keyless launch sends nothing to TypeSafe")
        report.expect(rows.allSatisfy { $0.check == nil }, "a list with no sentence ranks nothing")

        guard let first = rows.first(where: { $0.item.url?.absoluteString == "https://a.example/item-0" }) else {
            report.expect(false, "the fixture article is in the list")
            return
        }
        let read = await lab.read(first.id)
        let article = read.last
        report.expectEqual(article?.phase, .ready, "one of them opens readable")
        report.expect((article?.passages.count ?? 0) >= 10, "with its paragraphs",
                      detail: "\(article?.passages.count ?? 0) passages")
        report.expectEqual(jev.count, 0, "opening it with no key still sends nothing")
        report.expect(article?.item.read == true, "opening an item marks it read")

        // With no key a submitted sentence says so rather than pretending to search.
        let searched = await lab.search("anything at all")
        report.expectEqual(searched.last?.foot.text, "Add a key to search.", "the foot asks for a key")
        report.expectEqual(searched.last?.foot.actionTitle, "Open Settings", "and offers Settings")
        report.expectEqual(jev.count, 0, "a sentence with no key sends nothing")
        let status = await lab.engine.keyStatus()
        report.expectEqual(status, KeyStatus.missing, "the key status is missing")
    }

    private static func fromTheWeb(_ report: inout CheckReport) async {
        let started = ContinuousClock.now
        guard let lab = try? await Lab.live(starters: Catalog.starters, key: "") else {
            report.expect(false, "a wiped launch builds an engine")
            return
        }
        let listed = await lab.search(nil, within: .seconds(20))
        let ready = ContinuousClock.now - started
        let rows = listed.last?.rows ?? []
        report.expect(rows.count >= 20, "the three starter sources give 20+ items", detail: "\(rows.count) rows")
        report.expect(ready < .seconds(5), "within 5 s", detail: Wait.milliseconds(ready))
        let sidebar = await lab.sidebar()
        report.expectEqual(sidebar.sources.count, 3, "the three starter sources are in the sidebar")
        report.note("sources: " + sidebar.sources.map { "\($0.source.title) (\($0.unread))" }.joined(separator: ", "))
    }
}
