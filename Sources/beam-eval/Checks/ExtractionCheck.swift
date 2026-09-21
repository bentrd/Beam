import BeamExtract
import BeamModels
import Foundation

/// PRODUCT.md MUST 7 — Extraction: saved pages keep their paragraphs, a paywall falls back visibly rather than
/// pretending to be an empty article, and the live share of readable links is measured and printed.
///
/// The failure taxonomy is the point. An article Beam cannot read must say so, because "Nothing found in 0
/// paragraphs checked" on a page that never extracted is the one lie the reader must never tell.
@MainActor
enum ExtractionCheck {
    static let name = "extraction"

    static func run(_ report: inout CheckReport, offline: Bool, key: String?) async {
        report.section("Extraction (MUST 7) — a page of known shape")
        await knownShape(&report)

        report.section("Extraction (MUST 7) — a real saved agreement")
        await savedAgreement(&report)

        report.section("Extraction (MUST 7) — what cannot be read says so")
        await failures(&report)

        guard !offline else {
            report.skip("the live readable share", because: "--offline")
            return
        }
        report.section("Extraction (MUST 7) — today's Hacker News links")
        await liveShare(&report)
    }

    /// Every paragraph of a page whose shape we chose must survive, with its heading attached.
    private static func knownShape(_ report: inout CheckReport) async {
        let shape: [Fixtures.Relevance] = [.found, .nothing, .unsure, .nothing, .found, .nothing, .nothing, .unsure,
                                           .nothing, .found, .unsure, .nothing, .nothing, .unsure, .found, .nothing]
        let pages = StubPages()
        pages.serve("https://shape.example/article", html: Fixtures.article(title: "A known article", paragraphs: shape))
        let item = Item(sourceID: 1, guid: "shape", url: URL(string: "https://shape.example/article"),
                        title: "A known article", snippet: "")

        switch await ArticleLoader(fetcher: pages).load(item: item, sourceKind: .feed) {
        case let .ready(passages, images, tables):
            let judgeable = passages.filter(\.isJudgeable)
            report.expectEqual(judgeable.count, shape.count, "every paragraph survives")
            report.expect(passages.contains { $0.kind == .heading }, "its headings are kept")
            report.expect(passages.allSatisfy { $0.kind != .heading || !$0.isJudgeable }, "a heading is never judged")
            report.expect(judgeable.allSatisfy { $0.section == "The section" },
                          "each paragraph carries the heading above it",
                          detail: judgeable.first.map { "\"\($0.section)\"" } ?? "none")
            report.expectEqual(images, 0, "it counts no images")
            report.expectEqual(tables, 0, "it counts no tables")
        case let .unavailable(reason): report.expect(false, "a well-formed page extracts", detail: reason)
        case .external: report.expect(false, "a well-formed page extracts", detail: "reported external")
        }
    }

    /// The GitHub agreement: 23 pages of real markup, the same document the reader check lights.
    private static func savedAgreement(_ report: inout CheckReport) async {
        guard let terms = Fixtures.githubTerms else {
            report.expect(false, "the GitHub Terms fixture is in the bundle")
            return
        }
        let address = "https://docs.github.com/en/site-policy/github-terms/github-terms-of-service"
        let pages = StubPages()
        pages.serve(address, bytes: terms)
        let item = Item(sourceID: 1, guid: "terms", url: URL(string: address), title: "GitHub Terms of Service", snippet: "")

        let clock = ContinuousClock()
        let started = clock.now
        let content = await ArticleLoader(fetcher: pages).load(item: item, sourceKind: .feed)
        let elapsed = clock.now - started

        guard case let .ready(passages, _, _) = content else {
            report.expect(false, "the agreement extracts", detail: "\(content)")
            return
        }
        let judgeable = passages.filter(\.isJudgeable)
        report.expect(judgeable.count >= 80, "it yields its paragraphs", detail: "\(judgeable.count) judgeable")
        report.expect(judgeable.count <= 400, "and never more than the cap", detail: "\(judgeable.count)")
        report.expect(elapsed < .seconds(2), "within two seconds", detail: Wait.milliseconds(elapsed))
        let shortest = judgeable.filter { $0.text.count < 40 }
        report.expect(shortest.isEmpty, "no fragment shorter than 40 characters survives",
                      detail: shortest.prefix(3).map { "\($0.kind): \"\($0.text)\"" }.joined(separator: " · "))
        report.expect(judgeable.allSatisfy { $0.text.count <= 1_400 }, "long passages are split at a sentence end")
        report.expect(judgeable.contains { !$0.section.isEmpty }, "passages carry their section headings")
        report.expect(!passages.contains { $0.text.contains("â€™") || $0.text.contains("Ã©") },
                      "the bytes decode before the parser guesses, so there is no mojibake")
        report.expect(judgeable.contains { $0.text.lowercased().contains("governed by") },
                      "the governing-law paragraph is among them")
        report.expect(!judgeable.contains { $0.text.hasPrefix("↑") },
                      "reference and citation lists are dropped")
    }

    /// A paywall, a JavaScript shell, a page that will not load and a video: four ways to be unreadable, four
    /// honest answers.
    private static func failures(_ report: inout CheckReport) async {
        let pages = StubPages()
        pages.serve("https://paywall.example/story", html: Fixtures.paywalled)
        pages.serve("https://shell.example/app", html: Fixtures.thin)

        func load(_ address: String, kind: SourceKind = .feed) async -> ArticleContent {
            let item = Item(sourceID: 1, guid: address, url: URL(string: address), title: "A title", snippet: "A snippet")
            return await ArticleLoader(fetcher: pages).load(item: item, sourceKind: kind)
        }

        if case .unavailable = await load("https://paywall.example/story") {
            report.expect(true, "a paywalled page falls back instead of pretending")
        } else {
            report.expect(false, "a paywalled page falls back instead of pretending")
        }
        if case .unavailable = await load("https://shell.example/app") {
            report.expect(true, "a page with nothing to read is unavailable, not an empty article")
        } else {
            report.expect(false, "a page with nothing to read is unavailable, not an empty article")
        }
        if case .unavailable = await load("https://gone.example/missing") {
            report.expect(true, "a page that will not load says why")
        } else {
            report.expect(false, "a page that will not load says why")
        }
        if case .external = await load("https://www.youtube.com/watch?v=x", kind: .youtube) {
            report.expect(true, "a video opens in the browser rather than the reader")
        } else {
            report.expect(false, "a video opens in the browser rather than the reader")
        }
    }

    /// The number PRODUCT.md asks to be published: of the HTML links on today's front page, how many can be read.
    private static func liveShare(_ report: inout CheckReport) async {
        struct Hit: Decodable { let title: String?; let url: String? }
        struct Page: Decodable { let hits: [Hit] }

        let api = URL(string: "https://hn.algolia.com/api/v1/search?tags=front_page&hitsPerPage=30")!
        guard let (data, _) = try? await URLSession.shared.data(from: api),
              let page = try? JSONDecoder().decode(Page.self, from: data) else {
            report.skip("the live readable share", because: "Hacker News did not answer")
            return
        }
        let links = page.hits.compactMap { hit -> (String, URL)? in
            guard let title = hit.title, let raw = hit.url, let url = URL(string: raw) else { return nil }
            return (title, url)
        }
        guard !links.isEmpty else {
            report.skip("the live readable share", because: "no links on the front page")
            return
        }

        let loader = ArticleLoader()
        var readable = 0, html = 0
        var misses: [String] = []
        await withTaskGroup(of: (String, ArticleContent).self) { group in
            for (title, url) in links {
                group.addTask {
                    let item = Item(sourceID: 1, guid: url.absoluteString, url: url, title: title, snippet: "")
                    return (title, await loader.load(item: item, sourceKind: .feed))
                }
            }
            for await (title, content) in group {
                switch content {
                case let .ready(passages, _, _):
                    html += 1
                    let words = passages.filter(\.isJudgeable).reduce(0) { $0 + $1.text.split(separator: " ").count }
                    if words >= 150 { readable += 1 } else { misses.append("\(title) — thin (\(words) words)") }
                case let .unavailable(reason):
                    // A PDF, a video or a dead link was never an article: only real pages count against the share.
                    if reason.contains("Not a web page") || reason.contains("HTTP 4") || reason.contains("HTTP 5") {
                        misses.append("\(title) — \(reason)")
                    } else {
                        html += 1
                        misses.append("\(title) — \(reason)")
                    }
                case .external:
                    continue
                }
            }
        }
        let share = html > 0 ? Double(readable) / Double(html) : 0
        report.note(String(format: "readable: %.0f%% of %d HTML links (%d of today's %d front-page links)",
                           share * 100, html, readable, links.count))
        for miss in misses.prefix(8) { report.note("miss: \(miss)") }
        report.expect(share >= 0.70, "at least 70% of today's HTML links are readable",
                      detail: String(format: "%.0f%%", share * 100))
    }
}
