import BeamEngine
import BeamJev
import BeamModels
import Foundation

/// PRODUCT.md MUST 6 — Honesty: when three requests in ten fail, exactly those items and paragraphs read
/// "not checked", and the word "nothing" is never said about any of them.
@MainActor
enum HonestyCheck {
    static let name = "honesty"
    private static let feed = "https://honest.example/feed.xml"

    static func run(_ report: inout CheckReport, offline: Bool, key: String?) async {
        report.section("Honesty (MUST 6) — a list with three failures in ten")
        await lists(&report)
        report.section("Honesty (MUST 6) — an article with three failures in ten")
        await articles(&report)
        report.section("Honesty (MUST 6) — a run that cannot go on")
        await stopping(&report)
    }

    /// Every tenth item, by a stable share of them, refuses to be judged.
    private static func failsThreeInTen(_ state: [String: String]) -> Bool {
        let title = state["title"] ?? state["passage"] ?? ""
        return abs(title.hashValue) % 10 < 3
    }

    private static func lists(_ report: inout CheckReport) async {
        let web = StubWeb()
        web.serve(feed, Fixtures.rss(title: "Honest", site: "https://honest.example", count: 100, found: 20, unsure: 20))
        let jev = StubJev(fails: failsThreeInTen)
        guard let lab = try? await Lab.offline(starters: [Lab.candidate("Honest", feed)], jev: jev, web: web) else {
            report.expect(false, "an engine that fails three requests in ten")
            return
        }
        let trace = await lab.search(Fixtures.sentence)
        guard let settled = trace.last else {
            report.expect(false, "the run settles")
            return
        }
        let refused = Set(jev.all.filter { failsThreeInTen($0.state) }.compactMap { $0.state["title"] })
        report.expect(!refused.isEmpty, "some items were refused", detail: "\(refused.count) of 100")
        report.expect(settled.rows.allSatisfy { !refused.contains($0.item.judgedText["title"] ?? "") },
                      "a refused item is never listed as if it had been ranked")
        report.expectEqual(settled.foot.text, "\(refused.count) not checked.", "the foot counts exactly the refusals")
        report.expectEqual(settled.foot.actionTitle, "Retry", "and offers to try again")
        report.expect(settled.foot.isProminent, "in label colour, because it is not mere status")

        let saidNothing = trace.values.contains { ($0.emptyMessage ?? "").contains("Nothing found") }
        report.expect(!saidNothing, "\"Nothing found\" is never said while items are unchecked")
        report.expect(trace.values.allSatisfy { !$0.foot.text.contains("Nothing") }, "and never appears in the foot")

        // Retry, with the failures gone: everything is checked and the foot says so.
        jev.stopFailing()
        jev.reset()
        let retried = Wait.Flag()
        let after = await Wait.collect(lab.engine.list(ListRequest(scope: .all, sentence: Fixtures.sentence)),
                                       until: { snapshot in
            guard !snapshot.isRunning else { return false }
            guard retried.set() else {
                lab.engine.retryList()
                return false
            }
            return true
        })
        report.expectEqual(jev.count, refused.count, "Retry sends exactly the requests that failed")
        report.expectEqual(after.last?.foot.text, "100 items checked", "and the foot then counts them all")
    }

    private static func articles(_ report: inout CheckReport) async {
        let web = StubWeb()
        web.serve(feed, Fixtures.rss(title: "Honest", site: "https://honest.example", count: 2, found: 1))
        let pages = StubPages()
        let paragraphs = Array(repeating: Fixtures.Relevance.found, count: 4)
            + Array(repeating: Fixtures.Relevance.nothing, count: 36)
        pages.serve("https://honest.example/item-0", html: Fixtures.article(title: "A failing article", paragraphs: paragraphs))
        let jev = StubJev(fails: failsThreeInTen)
        guard let lab = try? await Lab.offline(starters: [Lab.candidate("Honest", feed)], jev: jev, web: web, pages: pages) else {
            report.expect(false, "an engine that fails three requests in ten")
            return
        }
        let listed = await lab.search(nil)
        guard let row = listed.last?.rows.first(where: { $0.item.url?.lastPathComponent == "item-0" }) else {
            report.expect(false, "the article is listed")
            return
        }
        let opened = await lab.read(row.id, carrying: Fixtures.sentence)
        guard let article = opened.last else {
            report.expect(false, "the article opens")
            return
        }
        let judgeable = article.passages.indices.filter { article.passages[$0].isJudgeable }
        let unchecked = judgeable.filter { article.isUnchecked(at: $0) }
        report.expect(!unchecked.isEmpty, "some paragraphs were refused", detail: "\(unchecked.count) of \(judgeable.count)")
        report.expect(unchecked.allSatisfy { article.checks[$0] == .failed }, "each one reads \"not checked\", never \"nothing\"")
        report.expect(unchecked.allSatisfy { article.band(at: $0) == .nothing } , "and carries no mark")
        report.expectEqual(article.foot.text, "\(judgeable.count - unchecked.count) of \(judgeable.count) checked.",
                           "the foot counts what was checked")
        report.expectEqual(article.foot.actionTitle, "Retry", "and offers to try again")
        report.expect(!opened.values.contains { $0.foot.text.contains("Nothing") },
                      "\"Nothing found\" is never said about an article with gaps")
    }

    /// Ten failures in a row stop a run: the rest of the library is not worth the wait.
    private static func stopping(_ report: inout CheckReport) async {
        let web = StubWeb()
        web.serve(feed, Fixtures.rss(title: "Honest", site: "https://honest.example", count: 60, found: 10))
        let jev = StubJev(fails: { _ in true })
        guard let lab = try? await Lab.offline(starters: [Lab.candidate("Honest", feed)], jev: jev, web: web,
                                               maxInFlight: 4) else {
            report.expect(false, "an engine where everything fails")
            return
        }
        let trace = await lab.search(Fixtures.sentence)
        report.expectEqual(trace.last?.foot.text, "Stopped after repeated errors.", "a run that keeps failing stops")
        report.expectEqual(trace.last?.foot.actionTitle, "Retry", "and offers to try again")
        report.expect(jev.count < 60 * JevClient.tries, "it stops rather than asking for all 60 items",
                      detail: "\(jev.count) attempts")
        report.expect(trace.last?.rows.isEmpty == true, "nothing was ranked")
        report.expect((trace.last?.emptyMessage ?? "").isEmpty, "and nothing claims there was nothing to find")
    }
}
