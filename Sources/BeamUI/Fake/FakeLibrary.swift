import BeamModels
import Foundation

/// Why the captured data could not be served. Surfaced at launch: a fake backend without its data is useless.
public enum FakeDataError: Error, CustomStringConvertible {
    case missing(String)
    case unreadable(String, underlying: Error)

    public var description: String {
        switch self {
        case .missing(let name): return "FakeData/\(name) is not in the BeamUI resource bundle."
        case .unreadable(let name, let underlying): return "FakeData/\(name) could not be decoded: \(underlying)"
        }
    }
}

/// The captured session behind `FakeBackend`: 203 real feed items judged against one real sentence, and one real
/// article judged twice (a narrow sentence that lights twelve paragraphs, a broad one that saturates it).
struct FakeLibrary {
    struct Article {
        let itemID: Int64
        let passages: [Passage]
        let omittedImages: Int
        /// Real probabilities by passage index, keyed by normalised sentence.
        let checks: [String: [Int: Double]]
    }

    var sources: [Source]
    var items: [Item]
    /// The sentence the list was really judged against, normalised, with the probability of every item.
    let listSentence: String
    let listChecks: [Int64: Double]
    let article: Article

    /// The sentence that saturates the captured article.
    var saturatingSentence: String { article.checks.keys.first { $0 != listSentence } ?? "" }

    static func load(now: Date = Date()) throws -> FakeLibrary {
        let list: ListFile = try decode("list")
        let lit: ArticleFile = try decode("article")
        let saturated: ArticleFile = try decode("article-saturated")

        let sources = FakeSources.starting(now: now)
        let sourceIDs = Dictionary(uniqueKeysWithValues: sources.map { ($0.title, $0.id) })
        var items: [Item] = []
        var checks: [Int64: Double] = [:]
        var articleItemID: Int64 = 0

        for (index, record) in list.rows.enumerated() {
            guard let sourceID = sourceIDs[record.source] else { continue }
            let id = Int64(index + 1)
            let age = FakeSources.seconds(fromAge: record.age)
            let isArticle = record.title == lit.title
            // Rows keep their captured order inside a source: the index breaks ties between equal ages.
            let published = now.addingTimeInterval(-age - Double(index) * 0.001)
            items.append(Item(id: id, sourceID: sourceID, guid: "fake-\(id)",
                              url: isArticle ? lit.url : FakeSources.link(for: record, in: sources.first { $0.id == sourceID }),
                              title: record.title, snippet: record.snippet, published: published, fetched: now,
                              read: age >= 2 * 86_400))
            checks[id] = record.p
            if isArticle { articleItemID = id }
        }
        // The long article is real and really judged, but its title and snippet alone scored 0.11:
        // raised so the lit article can be opened from its own search, as in the approved mock.
        if articleItemID != 0 { checks[articleItemID] = 0.78 }

        let passages = FakePassages.passages(from: lit.passages, droppingTitle: lit.title)
        let article = Article(itemID: articleItemID, passages: passages, omittedImages: 14, checks: [
            FakeJudge.normalise(lit.query): FakePassages.checks(from: lit.passages, droppingTitle: lit.title),
            FakeJudge.normalise(saturated.query): FakePassages.checks(from: saturated.passages, droppingTitle: saturated.title),
        ])
        return FakeLibrary(sources: sources, items: items.sorted { $0.sortDate > $1.sortDate },
                           listSentence: FakeJudge.normalise(list.query), listChecks: checks, article: article)
    }

    private static func decode<T: Decodable>(_ name: String) throws -> T {
        guard let url = resources.url(forResource: name, withExtension: "json", subdirectory: "FakeData") else {
            throw FakeDataError.missing("\(name).json")
        }
        do { return try JSONDecoder().decode(T.self, from: Data(contentsOf: url)) }
        catch { throw FakeDataError.unreadable("\(name).json", underlying: error) }
    }

    /// `Bundle.module` only looks beside the executable and at the absolute build path, and traps when both miss.
    /// A packaged app keeps SwiftPM's bundle in Contents/Resources, so that is tried first.
    private static let resources: Bundle = {
        let places = [Bundle.main.resourceURL, Bundle.main.bundleURL, Bundle.main.executableURL?.deletingLastPathComponent()]
        for case let place? in places {
            if let bundle = Bundle(url: place.appendingPathComponent("Beam_BeamUI.bundle")) { return bundle }
        }
        return .module
    }()
}

// MARK: File shapes

struct ListFile: Decodable {
    struct Row: Decodable { let title, snippet, source, age: String; let p: Double }
    let query: String
    let rows: [Row]
}

struct ArticleFile: Decodable {
    struct Block: Decodable { let kind, text: String; let p: Double? }
    let title: String
    let url: URL
    let query: String
    let passages: [Block]
}

// MARK: Passages

enum FakePassages {
    /// The captured article opens with its own title as a heading; the reader header already shows it.
    private static func body(_ blocks: [ArticleFile.Block], droppingTitle title: String) -> [ArticleFile.Block] {
        if let first = blocks.first, first.kind == "heading", first.text == title { return Array(blocks.dropFirst()) }
        return blocks
    }

    static func passages(from blocks: [ArticleFile.Block], droppingTitle title: String) -> [Passage] {
        var section = ""
        return body(blocks, droppingTitle: title).map { block in
            let kind: Passage.Kind
            switch block.kind {
            case "heading": kind = .heading; section = block.text
            case "blockquote": kind = .quote
            case "li": kind = .listItem
            case "pre": kind = .code
            default: kind = .paragraph
            }
            return Passage(kind: kind, text: block.text, section: kind == .heading ? "" : section)
        }
    }

    /// Headings and code are shown, never judged: a probability captured for a `pre` block is dropped.
    static func checks(from blocks: [ArticleFile.Block], droppingTitle title: String) -> [Int: Double] {
        var result: [Int: Double] = [:]
        for (index, block) in body(blocks, droppingTitle: title).enumerated() where block.kind != "heading" && block.kind != "pre" {
            if let p = block.p, p.isFinite, (0...1).contains(p) { result[index] = p }
        }
        return result
    }
}
