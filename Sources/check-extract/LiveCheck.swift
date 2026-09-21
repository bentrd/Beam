import BeamExtract
import BeamModels
import Foundation

/// PRODUCT.md risk 2, live: of today's Hacker News front-page links that are HTML, at least 70% must come back readable.
enum LiveCheck {
    static let sampleSize = 30
    static let requiredShare = 0.70

    private struct FrontPage: Decodable { struct Hit: Decodable { let title: String?; let url: String? }; let hits: [Hit] }
    private enum Outcome { case readable(passages: Int), miss(String), notHTML(String) }

    static func run(_ report: inout CheckReport) async {
        report.section("Live: Hacker News front page")
        if CheckEnvironment.isOffline { report.skip("front-page links are readable", because: "--offline"); return }
        guard let api = URL(string: "https://hn.algolia.com/api/v1/search?tags=front_page&hitsPerPage=60"),
              let (data, _) = try? await URLSession(configuration: .ephemeral).data(from: api),
              let page = try? JSONDecoder().decode(FrontPage.self, from: data) else {
            report.skip("front-page links are readable", because: "the Algolia API is not reachable")
            return
        }
        let links = page.hits.compactMap { hit in hit.url.flatMap(URL.init(string:)).map { (title: hit.title ?? "", url: $0) } }.prefix(sampleSize)
        let loader = ArticleLoader()
        let outcomes = await withTaskGroup(of: (String, URL, Outcome).self) { group -> [(String, URL, Outcome)] in
            for link in links {
                group.addTask {
                    let item = Item(sourceID: 0, guid: link.url.absoluteString, url: link.url, title: link.title, snippet: "")
                    switch await loader.load(item: item, sourceKind: .hackerNews) {
                    case let .ready(passages, _, _): return (link.title, link.url, .readable(passages: passages.count))
                    case .external: return (link.title, link.url, .notHTML("video"))
                    case let .unavailable(reason):
                        return (link.title, link.url, reason.hasPrefix("Not a web page") ? .notHTML(reason) : .miss(reason))
                    }
                }
            }
            var all: [(String, URL, Outcome)] = []
            for await outcome in group { all.append(outcome) }
            return all
        }

        var readable = 0, misses: [String] = [], excluded: [String] = []
        for (title, url, outcome) in outcomes {
            let label = "\(url.host ?? "?") — \(title.prefix(60))"
            switch outcome {
            case .readable: readable += 1
            case let .miss(reason): misses.append("\(reason): \(label)")
            case let .notHTML(reason): excluded.append("\(reason): \(label)")
            }
        }
        let html = readable + misses.count
        let share = html == 0 ? 0 : Double(readable) / Double(html)
        report.note("\(links.count) links, \(excluded.count) not HTML (excluded), \(html) HTML")
        for line in excluded.sorted() { report.note("excluded  \(line)") }
        for line in misses.sorted() { report.note("miss      \(line)") }
        report.expect(html >= 10, "enough HTML links to measure (\(html))")
        report.expect(share >= requiredShare, String(format: "readable: %.0f%% of HTML links (%d of %d), at least 70%% required", share * 100, readable, html))
    }
}
