import Foundation

// Risk 2 eval: how often does dependency-free extraction produce a readable article on real links?
struct Hit: Decodable { let title: String?; let url: String? }
struct Page: Decodable { let hits: [Hit] }

let config = URLSessionConfiguration.ephemeral
config.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15",
                                "Accept-Language": "en-US,en;q=0.9,fr;q=0.8"]
config.timeoutIntervalForRequest = 15
let session = URLSession(configuration: config)

var urls: [(String, String)] = []
for tag in ["front_page", "story"] {
    let api = URL(string: "https://hn.algolia.com/api/v1/search\(tag == "story" ? "_by_date" : "")?tags=\(tag)&hitsPerPage=40")!
    if let (d, _) = try? await session.data(from: api), let page = try? JSONDecoder().decode(Page.self, from: d) {
        for h in page.hits { if let u = h.url, let t = h.title { urls.append((t, u)) } }
    }
}
urls += [("Le Monde Pixels article", "https://www.lemonde.fr/pixels/article/2024/02/20/balatro-le-jeu-de-cartes-qui-rend-accro_6217520_4408996.html"),
         ("Numerama", "https://www.numerama.com/tech/"), ("Korben", "https://korben.info/"),
         ("Next.ink", "https://next.ink/"), ("The Verge article", "https://www.theverge.com/2024/6/10/24175405/wwdc-apple-ai-news-features-ios-18-macos-15-iphone-ipad-mac"),
         ("Ars Technica", "https://arstechnica.com/gadgets/2025/06/apple-liquid-glass/"), ("Medium", "https://medium.com/@karpathy/software-2-0-a64152b37c35"),
         ("Substack", "https://www.oneusefulthing.org/p/15-times-to-use-ai-and-5-not-to")]
var seen = Set<String>(); urls = urls.filter { seen.insert($0.1).inserted }
print("\(urls.count) links")

enum Outcome: String { case good, thin, empty, http, error, notHTML }
struct Row { let title: String; let url: String; let outcome: Outcome; let passages: Int; let words: Int; let note: String }

let rows: [Row] = await withTaskGroup(of: Row.self) { group in
    for (title, raw) in urls {
        group.addTask {
            guard let url = URL(string: raw) else { return Row(title: title, url: raw, outcome: .error, passages: 0, words: 0, note: "bad url") }
            do {
                let (data, resp) = try await session.data(from: url)
                let http = resp as? HTTPURLResponse
                let type = http?.value(forHTTPHeaderField: "Content-Type") ?? ""
                if let code = http?.statusCode, code >= 400 { return Row(title: title, url: raw, outcome: .http, passages: 0, words: 0, note: "HTTP \(code)") }
                if !type.contains("html") { return Row(title: title, url: raw, outcome: .notHTML, passages: 0, words: 0, note: String(type.prefix(30))) }
                let (_, passages) = try extract(data, response: resp)
                let body = passages.filter { $0.kind != "heading" }
                let words = body.reduce(0) { $0 + $1.text.split(separator: " ").count }
                let outcome: Outcome = body.isEmpty ? .empty : (words < 150 || body.count < 3 ? .thin : .good)
                return Row(title: title, url: raw, outcome: outcome, passages: body.count, words: words, note: "")
            } catch { return Row(title: title, url: raw, outcome: .error, passages: 0, words: 0, note: String(error.localizedDescription.prefix(40))) }
        }
    }
    var out: [Row] = []; for await r in group { out.append(r) }; return out
}
let by = Dictionary(grouping: rows, by: \.outcome)
print("\nOUTCOMES: " + [Outcome.good, .thin, .empty, .http, .notHTML, .error].map { "\($0.rawValue) \(by[$0]?.count ?? 0)" }.joined(separator: " · "))
let html = rows.filter { $0.outcome != .notHTML }
print(String(format: "readable: %.0f%% of HTML links (%d of %d)\n", 100 * Double(by[.good]?.count ?? 0) / Double(max(html.count, 1)), by[.good]?.count ?? 0, html.count))
for o in [Outcome.thin, .empty, .http, .error, .notHTML] {
    for r in (by[o] ?? []).prefix(12) { print("\(o.rawValue.uppercased().padding(toLength: 8, withPad: " ", startingAt: 0)) \(r.passages)p \(r.words)w \(r.note)  \(URL(string: r.url)?.host ?? "")  — \(r.title.prefix(48))") }
}
let good = (by[.good] ?? []).map(\.words).sorted()
if !good.isEmpty { print("\ngood articles: median \(good[good.count/2]) words, min \(good.first!), max \(good.last!)") }
