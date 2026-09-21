import BeamEngine
import BeamFeeds
import BeamJev
import BeamModels
import Foundation

/// PRODUCT.md MUST 3 — Search over 300 items: the first found row under 1.5 s, settled under 3 s, and a repeat
/// of the same sentence that costs nothing at all.
@MainActor
enum SearchCheck {
    static let name = "search"

    /// Judging order decides when good rows arrive, never which rows exist. Checked through the engine rather
    /// than the sorter, because what matters is the order the requests actually left in.
    private static func judgingOrder(_ report: inout CheckReport) async {
        report.section("Search (MUST 3) — the likeliest candidates are judged first")
        let web = StubWeb()
        web.serve("https://order.example/feed.xml",
                  Fixtures.rss(title: "Order", site: "https://order.example", count: 120, found: 12, unsure: 12))
        let jev = StubJev()
        guard let lab = try? await Lab.offline(starters: [Lab.candidate("Order", "https://order.example/feed.xml")],
                                               jev: jev, web: web) else {
            report.expect(false, "an engine over a 120-item library")
            return
        }
        let listed = await lab.search(Fixtures.sentence)
        let asks = jev.all

        report.expectEqual(asks.count, 120, "every item in the window is judged, whatever the order")
        let titles = asks.compactMap { $0.state["title"] }
        report.expectEqual(Set(titles).count, titles.count, "no item is judged twice")

        // The fixture's relevant titles share words with the sentence; they should go out in the first wave.
        let words = Set(Fixtures.sentence.lowercased().split(separator: " ").map(String.init))
        func shares(_ title: String) -> Bool {
            !Set(title.lowercased().split(separator: " ").map(String.init)).intersection(words).isEmpty
        }
        let early = titles.prefix(24).filter(shares).count
        let total = titles.filter(shares).count
        report.expect(early >= min(total, 12), "the items whose words echo the sentence go out first",
                      detail: "\(early) of the first 24 asks, \(total) in the library")

        let rows = listed.last?.rows ?? []
        report.expect(rows.contains { $0.isMarked }, "and the list still finds them")
    }

    static func run(_ report: inout CheckReport, offline: Bool, key: String?) async {
        report.section("Search (MUST 3) — 400 fixture items")
        await overFixtures(&report)
        await judgingOrder(&report)
        guard !offline else {
            report.skip("search timings on the real web", because: "--offline")
            return
        }
        guard let key else {
            report.skip("search timings on the real web", because: "no key in the environment")
            return
        }
        report.section("Search (MUST 3) — 300 real items, live")
        await live(&report, key: key)
    }

    private static func overFixtures(_ report: inout CheckReport) async {
        let web = StubWeb()
        // Three sources, so the round-robin has something to spread over, and 400 items, so there are older ones.
        for (index, name) in ["a", "b", "c"].enumerated() {
            web.serve("https://\(name).example/feed.xml", feed(name, count: index == 0 ? 160 : 120, from: index + 1))
        }
        let jev = StubJev()
        guard let lab = try? await Lab.offline(starters: ["a", "b", "c"].map {
            Lab.candidate("Fixture \($0)", "https://\($0).example/feed.xml")
        }, jev: jev, web: web) else {
            report.expect(false, "an engine over 400 items")
            return
        }
        let total = (await lab.search(nil)).last?.rows.count ?? 0
        report.expectEqual(total, 400, "400 items are listed with no sentence")
        report.expectEqual(jev.count, 0, "listing them ranks nothing and sends nothing")

        jev.reset()
        let searched = await lab.search(Fixtures.sentence)
        let settled = searched.last
        let rows = settled?.rows ?? []
        let marked = rows.filter(\.isMarked)

        report.expectEqual(jev.count, Windows.newest, "one request per item of the newest 300, and no more")
        report.expect(jev.all.allSatisfy { $0.frames.count == 1 }, "each request carries the one active sentence")
        report.expect(!marked.isEmpty, "the search finds rows", detail: "\(marked.count) found, \(rows.count) listed")
        report.expect(rows.count > marked.count, "and lists unsure ones behind them")
        report.expect(rows.prefix(marked.count).allSatisfy(\.isMarked), "found rows come before unsure ones")
        report.expect(isOrdered(rows), "rows are ordered by probability rounded to 0.05, then by date")
        report.expect(rows.allSatisfy { ($0.check?.probability ?? 0) >= Bands.listUnsure },
                      "nothing below 0.45 is listed")

        let sources = Set(marked.map(\.item.sourceID))
        report.expect(sources.count >= 2, "found rows come from more than one source", detail: "\(sources.count) sources")

        // "Newest 300 of 400 checked. Check 100 older"
        report.expectEqual(settled?.foot.text, "Newest 300 of 400 checked.", "the foot says how far the run reached")
        report.expectEqual(settled?.foot.actionTitle, "Check 100 older", "and offers the rest")

        // The same sentence again: every answer is already known, so nothing is sent.
        jev.reset()
        let repeated = await lab.search(Fixtures.sentence)
        report.expectEqual(jev.count, 0, "repeating the same sentence sends nothing")
        report.expectEqual(repeated.last?.rows.map(\.id), rows.map(\.id), "and lists exactly the same rows")
        report.expect(repeated.count <= 2, "a cached sentence arrives in one snapshot", detail: "\(repeated.count) snapshots")

        // Arrowing rows is a preview: it fetches nothing and sends nothing.
        jev.reset()
        var previews = 0
        for row in rows.prefix(20) where lab.engine.preview(itemID: row.id) != nil { previews += 1 }
        report.expectEqual(previews, min(20, rows.count), "every arrowed row previews")
        report.expectEqual(jev.count, 0, "arrowing 20 rows sends nothing")

        // Clicking a source during a search filters what is already checked, locally.
        jev.reset()
        let filtered = await lab.search(Fixtures.sentence, scope: .source(rows[0].item.sourceID))
        report.expectEqual(jev.count, 0, "clicking a source during a search sends nothing")
        report.expect(filtered.last?.rows.allSatisfy { $0.item.sourceID == rows[0].item.sourceID } == true,
                      "and shows only that source's rows")

        // "Check 100 older" widens the run that is already there rather than starting another.
        jev.reset()
        let asked = Wait.Flag()
        let extended = await Wait.collect(lab.engine.list(ListRequest(scope: .all, sentence: Fixtures.sentence)),
                                          until: { snapshot in
            guard !snapshot.isRunning else { return false }
            guard asked.set() else {
                lab.engine.checkOlder()
                return false
            }
            return true
        })
        report.expectEqual(jev.count, 100, "checking older judges exactly the 100 items that were left")
        report.expectEqual(extended.last?.foot.text, "400 items checked", "and the foot then counts them all")
    }

    /// One of the three fixture sources, each publishing its own text.
    ///
    /// Two feeds carrying a byte-identical title and snippet are one text to Beam — "Cache key: sha256(text) +
    /// sha256(framed sentence) + model id" (PRODUCT.md section 3) — so judging one of them answers the other, and
    /// a check that counts requests per item would be counting something else. Real sites do not publish each
    /// other's items; the generator's bare index did.
    private static func feed(_ name: String, count: Int, from day: Int) -> String {
        Fixtures.rss(title: "Fixture \(name.uppercased())", site: "https://\(name).example", count: count,
                     found: 10, unsure: 10, from: day, guidPrefix: "\(name)item")
            .replacingOccurrences(of: "A paragraph about", with: "A paragraph from \(name) about")
    }

    /// Rows come back in a scattered order; what matters is that the list is sorted before it is published.
    private static func isOrdered(_ rows: [Row]) -> Bool {
        let keys = rows.map { row -> (Double, Date) in
            (((row.check?.probability ?? 0) * 20).rounded(), row.item.sortDate)
        }
        return zip(keys, keys.dropFirst()).allSatisfy { first, second in
            first.0 > second.0 || (first.0 == second.0 && first.1 >= second.1)
        }
    }

    private static func live(_ report: inout CheckReport, key: String) async {
        let wanted = ["Hugging Face Blog", "Lobsters", "Simon Willison's Weblog", "Hacker News"]
        let starters = Catalog.entries.filter { wanted.contains($0.candidate.title) }
        guard let lab = try? await Lab.live(starters: starters, key: key) else {
            report.expect(false, "an engine on the real web")
            return
        }
        let chronological = await lab.search(nil, within: .seconds(30))
        let available = chronological.last?.rows.count ?? 0
        guard available >= Windows.newest else {
            report.skip("the 300-item timings", because: "only \(available) items arrived from the live feeds")
            return
        }
        report.expect(true, "300 or more live items are in the library", detail: "\(available) items")

        let sentence = "on-device machine learning on Apple silicon"
        let trace = await lab.search(sentence, within: .seconds(30))
        let firstFound = trace.first { $0.rows.contains(where: \.isMarked) }
        let settled = trace.first { !$0.isRunning }
        report.expect(firstFound != nil && firstFound! < .milliseconds(1_500), "the first found row arrives under 1.5 s",
                      detail: Wait.milliseconds(firstFound))
        report.expect(settled != nil && settled! < .seconds(3), "the run settles under 3 s", detail: Wait.milliseconds(settled))
        let rows = trace.last?.rows ?? []
        report.note("\(rows.filter(\.isMarked).count) found, \(rows.count) listed, foot: \"\(trace.last?.foot.text ?? "")\"")
        for row in rows.filter(\.isMarked).prefix(5) { report.note("  found: \(row.item.title)") }

        let spent = await lab.engine.dollarsToday()
        report.note(String(format: "the live search cost $%.4f", spent))

        // Offline in the sense that matters: the answers are known, so the same sentence costs nothing more.
        let before = await lab.engine.dollarsToday()
        let again = await lab.search(sentence, within: .seconds(30))
        let after = await lab.engine.dollarsToday()
        report.expectEqual(after, before, "repeating the live search spends nothing")
        report.expectEqual(again.last?.rows.map(\.id), rows.map(\.id), "and lists the same rows")
    }
}
