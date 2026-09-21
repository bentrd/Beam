import BeamFeeds
import BeamModels
import Foundation

private func asSource(_ entry: CatalogEntry, id: Int64) -> Source {
    Source(id: id, kind: entry.candidate.kind, title: entry.candidate.title, feedURL: entry.candidate.feedURL, siteURL: entry.candidate.siteURL)
}

/// The network is "available" when Hacker News answers; anything else that fails after that is a real failure.
private func networkIsAvailable() async -> Bool {
    (try? await HTTPClient.live(HTTPRequest(url: HackerNews.feedURL)))?.isSuccess == true
}

func checkLive(_ report: inout CheckReport) async {
    report.section("Live")
    let liveChecks = ["starters yield 20+ items in under 5 s", "a blog homepage resolves", "a GitHub repository resolves", "a YouTube /channel/ address resolves"]
    if CheckEnvironment.isOffline {
        return liveChecks.forEach { report.skip($0, because: "--offline") }
    }
    guard await networkIsAvailable() else {
        return liveChecks.forEach { report.skip($0, because: "no network") }
    }

    let started = Date()
    let results = await Refresher().refreshAll(Catalog.starters.enumerated().map { asSource($0.element, id: Int64($0.offset + 1)) })
    let elapsed = Date().timeIntervalSince(started)
    for result in results {
        report.expect(result.error == nil && !result.items.isEmpty, "starter \"\(result.source.title)\" delivers items", detail: result.error?.reason ?? "empty")
        report.note("\(result.source.title): \(result.items.count) items, e.g. \"\(result.items.first?.title ?? "")\"")
    }
    let total = results.reduce(0) { $0 + $1.items.count }
    report.expect(total >= 20 && elapsed < 5, "the three starters yield 20+ items in under 5 s", detail: "\(total) items in \(String(format: "%.2f", elapsed)) s")
    report.note("\(total) items in \(String(format: "%.2f", elapsed)) s")
    let items = results.flatMap(\.items)
    report.expect(items.allSatisfy { !$0.title.isEmpty && !$0.guid.isEmpty && $0.snippet.count <= 300 && !$0.snippet.contains("<p>") }, "every live item has a title, an identity and a clean snippet")
    report.expect(results.first { $0.source.kind == .githubReleases }?.repoName == "mlx", "MLX releases carry repoName \"mlx\"")

    let resolver = SourceResolver()
    let cases: [(String, String, SourceKind)] = [
        ("a blog homepage resolves", "https://simonwillison.net", .feed),
        ("a GitHub repository resolves", "https://github.com/ml-explore/mlx", .githubReleases),
        ("a YouTube /channel/ address resolves", "https://www.youtube.com/channel/UCYO_jab_esuFRV4b17AJtAw", .youtube),
    ]
    for (name, input, kind) in cases {
        let found = await resolver.resolve(input)
        report.expect(found.first?.kind == kind, name, detail: "\(input) gave \(found)")
        if let first = found.first { report.note("\(input) -> \"\(first.title)\" \(first.feedURL.absoluteString)") }
    }
}

/// `check-feeds --catalog`: fetches every catalog entry with the real transport. Not part of the default run,
/// because a third party's bad day must not turn this lane red; run it before changing the catalog.
func checkCatalogLive(_ report: inout CheckReport) async {
    report.section("Catalog, live (arXiv entries are 3 s apart; Reddit allows about one request a minute)")
    let sources = Catalog.entries.enumerated().map { asSource($0.element, id: Int64($0.offset + 1)) }
    for await result in Refresher().refresh(sources) {
        let newest = result.items.compactMap(\.published).max().map { ISO8601DateFormatter().string(from: $0) } ?? "undated"
        report.expect(!result.items.isEmpty, "\(result.source.title): \(result.items.count) items, newest \(newest)", detail: result.error?.reason ?? "empty feed")
    }
}
