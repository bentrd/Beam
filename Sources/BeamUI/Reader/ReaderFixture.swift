import BeamModels
import Foundation

/// The captured article in `FakeData`, for showing the reader by itself (`reader-demo`) without a backend.
///
/// It is one real article ("Things we learned about LLMs in 2024") judged against two real sentences:
/// a narrow one that lights twelve paragraphs, and a broad one that saturates it.
public struct ReaderFixture: Sendable {
    public enum Article: String, Sendable {
        /// "running models locally on a laptop": 12 found, 8 unsure.
        case lit = "article"
        /// "large language models": 150 of 159 paragraphs found.
        case saturated = "article-saturated"
    }

    public enum LoadError: Error, CustomStringConvertible {
        case missing(String)
        case unreadable(String, underlying: Error)

        public var description: String {
            switch self {
            case .missing(let name): return "FakeData/\(name).json is not in the BeamUI resource bundle."
            case .unreadable(let name, let underlying): return "FakeData/\(name).json could not be read: \(underlying)"
            }
        }
    }

    public let item: Item
    public let sourceTitle: String
    /// The sentence the probabilities were measured for.
    public let sentence: String
    public let passages: [Passage]
    /// Measured probabilities by passage index. Headings and code have none: they are never judged.
    public let probabilities: [Int: Double]
    public let omittedImages: Int

    public static func load(_ article: Article) throws -> ReaderFixture {
        let name = article.rawValue
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "FakeData") else {
            throw LoadError.missing(name)
        }
        let file: File
        do { file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url)) } catch {
            throw LoadError.unreadable(name, underlying: error)
        }
        return ReaderFixture(file)
    }

    private init(_ file: File) {
        var section = ""
        var passages: [Passage] = []
        var probabilities: [Int: Double] = [:]
        for record in file.passages {
            let kind = Self.kind(record.kind)
            if kind == .heading { section = record.text }
            let passage = Passage(kind: kind, text: record.text, section: kind == .heading ? "" : section)
            if passage.isJudgeable, let p = record.p { probabilities[passages.count] = p }
            passages.append(passage)
        }
        let snippet = passages.first { $0.kind == .paragraph }?.text ?? ""
        item = Item(id: 1, sourceID: 1, guid: file.url.absoluteString, url: file.url, title: file.title,
                    snippet: String(snippet.prefix(300)), published: Self.published, read: true)
        sourceTitle = "Simon Willison"
        sentence = file.query
        self.passages = passages
        self.probabilities = probabilities
        omittedImages = 14
    }

    /// The captured page carries its date in its address (…/2024/Dec/31/…); the capture itself kept text only.
    private static let published = Date(timeIntervalSince1970: 1_735_646_400)

    private static func kind(_ tag: String) -> Passage.Kind {
        switch tag {
        case "heading": return .heading
        case "blockquote": return .quote
        case "li": return .listItem
        case "pre": return .code
        default: return .paragraph
        }
    }

    private struct File: Decodable {
        struct Record: Decodable {
            let kind: String
            let text: String
            let p: Double?
        }
        let title: String
        let url: URL
        let query: String
        let passages: [Record]
    }
}
