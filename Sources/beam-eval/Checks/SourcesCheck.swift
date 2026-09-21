import BeamEngine
import BeamModels
import Foundation

/// PRODUCT.md MUST 2 — Sources: a blog homepage, a channel address and a repository resolve to feeds; dirty
/// feeds parse; the same entry twice is one item.
@MainActor
enum SourcesCheck {
    static let name = "sources"

    static func run(_ report: inout CheckReport, offline: Bool, key: String?) async {
        report.section("Sources (MUST 2) — resolving fixtures")
        await resolving(&report)
        report.section("Sources (MUST 2) — dirty feeds")
        await dirtyFeeds(&report)
        guard !offline else {
            report.skip("resolving real addresses", because: "--offline")
            return
        }
        report.section("Sources (MUST 2) — the real web")
        await live(&report)
    }

    private static func resolving(_ report: inout CheckReport) async {
        let web = StubWeb()
        web.serve("https://blog.example/", Fixtures.homepage(feed: "/posts.xml"), contentType: "text/html; charset=utf-8")
        web.serve("https://blog.example/posts.xml", Fixtures.rss(title: "A Blog", site: "https://blog.example", count: 3))
        web.serve("https://www.youtube.com/feeds/videos.xml?channel_id=UC1234567890abcdefghijkl", Fixtures.youtube(channelID: "UC1234567890abcdefghijkl"))
        web.serve("https://github.com/ml-explore/mlx/releases.atom", Fixtures.releases(repository: "mlx"))

        guard let lab = try? await Lab.offline(hasKey: false, web: web) else {
            report.expect(false, "an engine to resolve with")
            return
        }
        let blog = await lab.engine.resolve("blog.example")
        report.expect(candidate(blog)?.feedURL.absoluteString == "https://blog.example/posts.xml",
                      "a blog homepage resolves through its <link rel=alternate>", detail: describe(blog))

        let channel = await lab.engine.resolve("https://www.youtube.com/channel/UC1234567890abcdefghijkl")
        report.expectEqual(candidate(channel)?.kind, SourceKind.youtube, "a /channel/UC… address resolves as YouTube")

        let repository = await lab.engine.resolve("https://github.com/ml-explore/mlx")
        report.expectEqual(candidate(repository)?.kind, SourceKind.githubReleases, "a GitHub repository resolves to its releases")

        guard let found = candidate(blog) else { return }
        let added = await lab.engine.addSource(found)
        guard case .added = added else {
            report.expect(false, "the blog is added")
            return
        }
        report.expect(true, "the blog is added")
        let again = await lab.engine.resolve("blog.example")
        if case .alreadyAdded = again {
            report.expect(true, "resolving it again says it is already added")
        } else {
            report.expect(false, "resolving it again says it is already added", detail: describe(again))
        }
        let rows = await lab.search(nil)
        report.expectEqual(rows.last?.rows.count, 3, "its items are fetched as soon as it is added")

        // Release items are judged as "<repo> <tag>", because "v0.30.6" alone is unjudgeable (EVIDENCE.md).
        guard let release = candidate(repository) else { return }
        _ = await lab.engine.addSource(release)
        let all = await lab.search(nil)
        let tag = all.last?.rows.first { $0.item.title == "v0.30.6" }
        report.expectEqual(tag?.item.repoName, "mlx", "a release item carries its repository name")
        report.expectEqual(tag?.item.judgedText["title"], "mlx v0.30.6", "and is judged as \"mlx v0.30.6\"")
    }

    private static func dirtyFeeds(_ report: inout CheckReport) async {
        let web = StubWeb()
        web.serve("https://dirty.example/feed.xml", Fixtures.dirty)
        guard let lab = try? await Lab.offline(starters: [Lab.candidate("Dirty", "https://dirty.example/feed.xml")],
                                               hasKey: false, web: web) else {
            report.expect(false, "an engine to parse with")
            return
        }
        let listed = await lab.search(nil)
        let rows = listed.last?.rows ?? []
        report.expectEqual(rows.count, 6, "six entries survive a BOM, entities, CDATA and six date formats")
        report.expect(rows.allSatisfy { $0.item.published != nil }, "every one of them has a date")
        report.expect(rows.allSatisfy { !$0.item.title.contains("&") }, "entities are decoded, not shown")
        report.expect(rows.contains { $0.item.title.contains("Café") }, "including the ones that are not XML's")
        report.expect(rows.allSatisfy { !$0.item.snippet.contains("<b>") }, "CDATA markup is stripped from snippets")
        let dates = Set(rows.compactMap(\.item.published))
        report.expectEqual(dates.count, 6, "the six date formats give six distinct dates")
    }

    private static func live(_ report: inout CheckReport) async {
        guard let lab = try? await Lab.live(starters: [], key: "", refreshesOnLaunch: false) else {
            report.expect(false, "an engine to resolve with")
            return
        }
        let blog = await lab.engine.resolve("https://daringfireball.net")
        report.expect(candidate(blog) != nil, "a real blog homepage resolves", detail: describe(blog))
        let channel = await lab.engine.resolve("https://www.youtube.com/channel/UCXuqSBlHAE6Xw-yeJA0Tunw")
        report.expectEqual(candidate(channel)?.kind, SourceKind.youtube, "a real /channel/UC… address resolves")
        let repository = await lab.engine.resolve("https://github.com/ml-explore/mlx")
        report.expectEqual(candidate(repository)?.kind, SourceKind.githubReleases, "a real GitHub repository resolves")
    }

    private static func candidate(_ outcome: ResolveOutcome) -> SourceCandidate? {
        if case let .found(candidates) = outcome { return candidates.first }
        return nil
    }

    private static func describe(_ outcome: ResolveOutcome) -> String {
        switch outcome {
        case let .found(candidates): return "found \(candidates.map { $0.feedURL.absoluteString }.joined(separator: ", "))"
        case let .alreadyAdded(source): return "already added: \(source.title)"
        case .notFound: return "not found"
        }
    }
}
