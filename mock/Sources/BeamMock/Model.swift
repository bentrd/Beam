import Foundation
import SwiftUI

enum Band { case found, unsure, nothing }

struct Row: Identifiable, Hashable {
    let id: Int
    let title: String, snippet: String, source: String, age: String
    let p: Double
    var found: Bool { p >= 0.60 }
}

struct Block: Identifiable {
    enum Kind { case heading, body }
    let id: Int
    let kind: Kind
    let text: String
    let p: Double?
    /// Inside articles the bands are 0.75 / 0.25.
    var band: Band { guard let p else { return .nothing }; return p >= 0.75 ? .found : (p > 0.25 ? .unsure : .nothing) }
}

enum MockScene: String { case lit, saturated, plain }

@Observable final class Mock {
    let scene: MockScene
    var sentence: String
    var rows: [Row] = []
    var total = 0
    var selection: Int?
    var sidebarSelection: String? = "All Items"
    var articleTitle = ""
    var blocks: [Block] = []
    var currentHit: Int?          // index into `hits`
    var jumpRequest = 0

    let pins: [(String, Int)] = [("on-device ML on Apple Silicon", 3), ("game modding", 1), ("trucs sur la vie privée et la surveillance", 0)]
    let sources = ["Hacker News", "Lobsters", "Simon Willison", "r/macapps", "MLX releases", "arXiv cs.LG", "Apple Machine Learning Research"]

    var saturated: Bool {
        let judged = blocks.filter { $0.p != nil }
        guard judged.count >= 24 else { return false }
        return Double(judged.filter { $0.band == .found }.count) / Double(judged.count) > 0.35
    }
    var hits: [Int] { saturated ? [] : blocks.filter { $0.band != .nothing }.map(\.id) }
    var foundCount: Int { blocks.filter { $0.band == .found }.count }
    var unsureCount: Int { blocks.filter { $0.band == .unsure }.count }

    init(scene: MockScene) {
        self.scene = scene
        let data = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("data")
        func json(_ name: String) -> [String: Any] {
            guard let d = try? Data(contentsOf: data.appendingPathComponent(name)), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [:] }
            return o
        }
        let list = json("list.json")
        let article = json(scene == .saturated ? "article-saturated.json" : "article.json")
        sentence = scene == .plain ? "" : (article["query"] as? String ?? "")
        total = list["total"] as? Int ?? 0

        var all: [Row] = ((list["rows"] as? [[String: Any]]) ?? []).enumerated().map { i, r in
            Row(id: i, title: r["title"] as? String ?? "", snippet: r["snippet"] as? String ?? "", source: r["source"] as? String ?? "", age: r["age"] as? String ?? "", p: r["p"] as? Double ?? 0)
        }
        if scene == .plain {
            rows = Array(all.prefix(60))
        } else {
            // The long article is real and really judged, but is not in today's feeds: placed here so the mock can open it.
            if let i = all.firstIndex(where: { $0.title.hasPrefix("Things we learned") }) {
                let r = all[i]; all[i] = Row(id: r.id, title: r.title, snippet: r.snippet, source: r.source, age: r.age, p: scene == .saturated ? 0.95 : 0.78)
            }
            rows = all.filter { $0.p >= 0.45 }.sorted { (($0.p * 20).rounded(), $1.id) > (($1.p * 20).rounded(), $0.id) }
            selection = rows.first(where: { $0.title.hasPrefix("Things we learned") })?.id
        }
        articleTitle = "Things we learned about LLMs in 2024"
        let passages = (article["passages"] as? [[String: Any]]) ?? []
        blocks = passages.enumerated().compactMap { i, p in
            let text = p["text"] as? String ?? ""
            if i == 0, text == articleTitle { return nil }
            return Block(id: i, kind: (p["kind"] as? String) == "heading" ? .heading : .body, text: text, p: p["p"] as? Double)
        }
    }

    func step(_ delta: Int) {
        guard !hits.isEmpty else { return }
        currentHit = ((currentHit ?? (delta > 0 ? -1 : 0)) + delta + hits.count) % hits.count
        jumpRequest += 1
    }
}
