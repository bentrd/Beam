import BeamEngine
import BeamModels
import Foundation

/// PRODUCT.md MUST 5 — The reader: an article opens lit, the right paragraph and only the right paragraph,
/// Find by Meaning re-lights this article alone, and arrowing rows costs nothing.
@MainActor
enum ReaderCheck {
    static let name = "reader"
    private static let feed = "https://reader.example/feed.xml"

    static func run(_ report: inout CheckReport, offline: Bool, key: String?) async {
        report.section("Reader (MUST 5) — marks, saturation and Find by Meaning")
        await marks(&report)
        report.section("Reader (MUST 5) — pre-judging the top results")
        await prejudging(&report)
        guard !offline else {
            report.skip("the GitHub Terms fixture with the real judge", because: "--offline")
            return
        }
        guard let key else {
            report.skip("the GitHub Terms fixture with the real judge", because: "no key in the environment")
            return
        }
        report.section("Reader (MUST 5) — GitHub Terms, live")
        await githubTerms(&report, key: key)
    }

    private static func marks(_ report: inout CheckReport) async {
        let web = StubWeb()
        web.serve(feed, Fixtures.rss(title: "Reader", site: "https://reader.example", count: 4, found: 2, unsure: 1))
        let pages = StubPages()
        let focused = Array(repeating: Fixtures.Relevance.found, count: 3)
            + Array(repeating: Fixtures.Relevance.unsure, count: 3)
            + Array(repeating: Fixtures.Relevance.nothing, count: 24)
        let broad = Array(repeating: Fixtures.Relevance.found, count: 20)
            + Array(repeating: Fixtures.Relevance.nothing, count: 10)
        pages.serve("https://reader.example/item-0", html: Fixtures.article(title: "A focused article", paragraphs: focused))
        pages.serve("https://reader.example/item-1", html: Fixtures.article(title: "A broad article", paragraphs: broad))
        pages.serve("https://reader.example/item-2", html: Fixtures.thin)

        let jev = StubJev()
        guard let lab = try? await Lab.offline(starters: [Lab.candidate("Reader", feed)], jev: jev, web: web, pages: pages) else {
            report.expect(false, "an engine to read in")
            return
        }
        let listed = await lab.search(Fixtures.sentence)
        let rows = listed.last?.rows ?? []
        guard let focusedRow = rows.first(where: { $0.item.url?.lastPathComponent == "item-0" }),
              let broadRow = rows.first(where: { $0.item.url?.lastPathComponent == "item-1" }) else {
            report.expect(false, "the fixture articles are listed")
            return
        }

        jev.reset()
        let opened = await lab.read(focusedRow.id, carrying: Fixtures.sentence)
        guard let article = opened.last else {
            report.expect(false, "the article opens")
            return
        }
        let judgeable = article.passages.indices.filter { article.passages[$0].isJudgeable }
        let found = judgeable.filter { article.band(at: $0) == .found }
        let unsure = judgeable.filter { article.band(at: $0) == .unsure }

        report.expectEqual(article.phase, .ready, "the article opens")
        report.expectEqual(judgeable.count, 30, "its 30 paragraphs are judgeable")
        report.expectEqual(jev.count, 30, "one request per paragraph, and no more")
        report.expectEqual(found.count, 3, "three paragraphs are found")
        report.expectEqual(unsure.count, 3, "three are unsure")
        report.expect(!article.isSaturated, "three found of thirty is not saturation")
        report.expectEqual(article.hits, (found + unsure).sorted(), "hits are found and unsure paragraphs in reading order")
        report.expectEqual(article.foot.text, "3 found, 3 unsure", "the foot says what was found")
        report.expect(article.passages.contains { $0.kind == .heading }, "headings are shown")
        report.expect(article.checks.keys.allSatisfy { article.passages[$0].isJudgeable }, "and never judged")

        // Find by Meaning re-lights this article alone; closing it restores the carried marks from memory.
        let gardening = "autumn balconies watering"
        jev.reset()
        let asked = Wait.Flag()
        let asking = await Wait.collect(lab.engine.open(itemID: focusedRow.id, carrying: Fixtures.sentence),
                                        until: { snapshot in
            guard snapshot.phase == .ready, !snapshot.isRunning else { return false }
            guard asked.set() else {
                lab.engine.find(gardening)
                return false
            }
            return true
        })
        let answered = asking.last
        let askedFound = (answered?.passages.indices.filter { answered?.band(at: $0) == .found } ?? []).count
        report.expectEqual(answered?.sentence, gardening, "Find by Meaning takes over the article's marks")
        report.expectEqual(answered?.isFindActive, true, "and says it is active")
        report.expectEqual(askedFound, 24, "the question lights its own paragraphs")
        report.expectEqual(jev.count, 24 + 6, "only the paragraphs it has no answer for are sent")

        jev.reset()
        let restored = Wait.Flag()
        let closing = await Wait.collect(lab.engine.open(itemID: focusedRow.id, carrying: Fixtures.sentence),
                                         until: { snapshot in
            guard snapshot.phase == .ready, !snapshot.isRunning else { return false }
            guard restored.set() else {
                lab.engine.find(nil)
                return false
            }
            return true
        })
        report.expectEqual(closing.last?.sentence, Fixtures.sentence, "closing the field restores the carried sentence")
        report.expectEqual(closing.last?.hits.count, 6, "with its marks")
        report.expectEqual(jev.count, 0, "and nothing is sent to get them back")

        // Saturation: when the sentence is the whole article, Beam draws nothing and says so.
        let saturated = await lab.read(broadRow.id, carrying: Fixtures.sentence)
        guard let broadArticle = saturated.last else {
            report.expect(false, "the broad article opens")
            return
        }
        report.expect(broadArticle.isSaturated, "20 found of 30 is saturation")
        report.expect(broadArticle.hits.isEmpty, "a saturated article has no hits to walk")
        report.expectEqual(broadArticle.foot.text, "Most of this article is about this.", "and one calm sentence")
        report.expectEqual(broadArticle.foot.actionTitle, "Find something narrower.", "with the way out")
        report.expectEqual(broadArticle.foot.help, "20 of 30 paragraphs", "the count lives in the help tag")
        report.expect(broadArticle.passages.indices.allSatisfy { broadArticle.band(at: $0) == .nothing },
                      "no paragraph is tinted")

        // A page with nothing to read is the failed state, never an empty article.
        if let thinRow = rows.first(where: { $0.item.url?.lastPathComponent == "item-2" }) {
            let thin = await lab.read(thinRow.id, carrying: Fixtures.sentence)
            report.expectEqual(thin.last?.phase, .unavailable, "a page with no text is unavailable, not empty")
        }

        // Arrowing rows previews and sends nothing.
        jev.reset()
        for row in rows { _ = lab.engine.preview(itemID: row.id) }
        report.expectEqual(jev.count, 0, "arrowing every row sends nothing")
        report.expectEqual(pages.requests, 3, "and fetches nothing new")
    }

    private static func prejudging(_ report: inout CheckReport) async {
        let web = StubWeb()
        web.serve(feed, Fixtures.rss(title: "Reader", site: "https://reader.example", count: 6, found: 3, unsure: 1))
        let pages = StubPages()
        let paragraphs = Array(repeating: Fixtures.Relevance.found, count: 3)
            + Array(repeating: Fixtures.Relevance.nothing, count: 27)
        for index in 0..<3 {
            pages.serve("https://reader.example/item-\(index)", html: Fixtures.article(title: "Article \(index)", paragraphs: paragraphs))
        }
        let jev = StubJev()
        guard let lab = try? await Lab.offline(starters: [Lab.candidate("Reader", feed)], jev: jev, web: web, pages: pages) else {
            report.expect(false, "an engine to pre-judge in")
            return
        }

        // Off by default: paragraphs of unopened articles are not sent.
        report.expect(!lab.engine.prejudgesTopResults, "pre-judging is off by default")
        _ = await lab.search(Fixtures.sentence)
        let afterSearch = jev.count
        _ = await Wait.until({ false }, within: .milliseconds(300))
        report.expectEqual(jev.count, afterSearch, "with it off, a settled search sends nothing more")

        lab.engine.prejudgesTopResults = true
        jev.reset()
        let listed = await lab.search(Fixtures.sentence)
        let top = listed.last?.rows.filter(\.isMarked).prefix(Windows.prejudgedRows).map(\.id) ?? []
        report.expectEqual(top.count, 3, "three rows are found")
        let judged = await Wait.until({ jev.count >= 90 }, within: .seconds(10))
        report.expect(judged, "the top three articles are judged ahead, 30 paragraphs each", detail: "\(jev.count) requests")

        jev.reset()
        let started = ContinuousClock.now
        let opened = await lab.read(top[0], carrying: Fixtures.sentence)
        let lit = ContinuousClock.now - started
        report.expectEqual(jev.count, 0, "opening a pre-judged row sends nothing")
        report.expectEqual(opened.last?.hits.count, 3, "and it is lit from the first snapshot")
        report.expect(lit < .milliseconds(300), "which takes under 300 ms", detail: Wait.milliseconds(lit))
    }

    private static func githubTerms(_ report: inout CheckReport, key: String) async {
        guard let terms = Fixtures.githubTerms else {
            report.expect(false, "the GitHub Terms fixture is in the bundle")
            return
        }
        let web = StubWeb()
        web.serve(feed, Fixtures.feed(title: "Terms", site: "https://reader.example", items: [
            Fixtures.item(guid: "terms", title: "GitHub Terms of Service", snippet: "The terms that govern the service.",
                          link: "https://docs.github.com/en/site-policy/github-terms/github-terms-of-service",
                          date: Fixtures.rfc822(day: 15, minute: 1)),
        ]))
        let pages = StubPages()
        pages.serve("https://docs.github.com/en/site-policy/github-terms/github-terms-of-service", bytes: terms)

        guard let lab = try? await Lab.judging(key: key, starters: [Lab.candidate("Terms", feed)], web: web, pages: pages) else {
            report.expect(false, "an engine with the real judge")
            return
        }
        let listed = await lab.search(nil)
        guard let row = listed.last?.rows.first else {
            report.expect(false, "the terms are listed")
            return
        }
        let sentence = "which jurisdiction's law governs disputes"
        let started = ContinuousClock.now
        let opened = await lab.read(row.id, carrying: sentence, within: .seconds(60))
        let lit = ContinuousClock.now - started
        guard let article = opened.last else {
            report.expect(false, "the terms open")
            return
        }
        let judgeable = article.passages.indices.filter { article.passages[$0].isJudgeable }
        let found = judgeable.filter { article.band(at: $0) == .found }
        report.expect(judgeable.count > 100, "the terms extract to a long article", detail: "\(judgeable.count) paragraphs")
        report.expectEqual(found.count, 1, "\"\(sentence)\" lights exactly one paragraph")
        report.expect(article.hits.contains(where: found.contains), "Find Next reaches it")
        report.expect(!article.isSaturated, "one paragraph of many is not saturation")
        report.expect(lit < .seconds(5), "the article is judged in a few seconds", detail: Wait.milliseconds(lit))
        if let index = found.first {
            let text = article.passages[index].text
            report.expect(text.contains("California") || text.lowercased().contains("jurisdiction"),
                          "and it is the paragraph that answers the question", detail: String(text.prefix(120)))
        }
        let spent = await lab.engine.dollarsToday()
        report.note(String(format: "judging %d paragraphs cost $%.4f", judgeable.count, spent))
    }
}
