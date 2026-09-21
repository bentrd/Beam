import BeamFeeds
import BeamModels
import Foundation

func checkCatalog(_ report: inout CheckReport) {
    report.section("Catalog")
    let entries = Catalog.entries
    report.expect((26...30).contains(entries.count), "about 25 sources plus the three starters", detail: "\(entries.count)")
    report.expectEqual(Catalog.starters.map(\.candidate.title), ["Hacker News", "MLX releases", "Apple Machine Learning Research"], "the three starters, in order")
    report.expect(entries.filter(\.isStarter) == Catalog.starters, "only the starters are marked isStarter")
    report.expectEqual(Set(entries.map(\.id)).count, entries.count, "no feed is listed twice")
    report.expect(entries.allSatisfy { $0.candidate.feedURL.scheme == "https" && $0.candidate.siteURL?.scheme == "https" }, "every address is https, and every entry has a site")
    report.expect(entries.allSatisfy { SourceKind(feedURL: $0.candidate.feedURL) == $0.candidate.kind }, "every entry's kind is the kind its address implies")
    report.expect(entries.allSatisfy { !$0.blurb.isEmpty && !$0.blurb.hasSuffix(".") && $0.blurb.count <= 64 && !$0.candidate.title.isEmpty }, "every entry has a title and a short blurb")
    report.expect(Set(entries.map(\.candidate.kind)).isSuperset(of: [.feed, .hackerNews, .arxiv, .githubReleases, .youtube]), "the catalog shows off every kind of source it can")

    report.expectEqual(Catalog.entries(matching: "").count, entries.count, "an empty filter shows everything")
    report.expectEqual(Catalog.entries(matching: "  MLX ").map(\.candidate.title), ["MLX releases"], "filter: by title, case and spaces ignored")
    report.expect(Catalog.entries(matching: "french").count >= 3, "filter: by subject, through the blurb")
    report.expectEqual(Catalog.entries(matching: "daringfireball").map(\.candidate.title), ["Daring Fireball"], "filter: by address")
    report.expectEqual(Catalog.entries(matching: "cafe noir").count, 0, "filter: every word must match")
    report.expectEqual(Catalog.entries(matching: "news apple").map(\.candidate.title).sorted(), Catalog.entries(matching: "apple news").map(\.candidate.title).sorted(), "filter: word order does not matter")
}
