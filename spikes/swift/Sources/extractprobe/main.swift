import Foundation
import SQLite3

// ---- readability-style extraction with Foundation only -------------------------------------
struct Passage { let kind: String; let text: String }

func text(of node: XMLNode) -> String {
    (node.stringValue ?? "").replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Decode using the HTTP charset, then a <meta charset>, then UTF-8, then Latin-1. Tidy guesses wrong on its own.
func decode(_ data: Data, response: URLResponse?) -> String {
    var candidates: [String.Encoding] = []
    func add(_ name: String?) {
        guard let name, !name.isEmpty else { return }
        let cf = CFStringConvertIANACharSetNameToEncoding(name as CFString)
        if cf != kCFStringEncodingInvalidId { candidates.append(String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))) }
    }
    add(response?.textEncodingName)
    if let head = String(data: data.prefix(4096), encoding: .isoLatin1),
       let m = head.range(of: #"charset\s*=\s*["']?([A-Za-z0-9_\-]+)"#, options: [.regularExpression, .caseInsensitive]) {
        add(String(head[m]).components(separatedBy: CharacterSet(charactersIn: "=\"' ")).last)
    }
    candidates += [.utf8, .isoLatin1]
    for enc in candidates { if let s = String(data: data, encoding: enc) { return s } }
    return String(decoding: data, as: UTF8.self)
}

func extract(_ data: Data, response: URLResponse? = nil) throws -> (title: String, passages: [Passage]) {
    let html = decode(data, response: response)
    let doc = try XMLDocument(xmlString: html, options: [.documentTidyHTML, .nodeLoadExternalEntitiesNever])
    for junk in try doc.nodes(forXPath: "//script|//style|//noscript|//nav|//footer|//aside|//form|//iframe|//svg|//button|//figure/figcaption") {
        junk.detach()
    }
    let title = (try? doc.nodes(forXPath: "//title").first).flatMap { $0 }.map(text(of:)) ?? ""

    var scores: [ObjectIdentifier: (node: XMLNode, score: Double)] = [:]
    for p in try doc.nodes(forXPath: "//p|//pre|//blockquote") {
        let t = text(of: p)
        guard t.count > 40 else { continue }
        let s = 1.0 + Double(t.filter { $0 == "," }.count) + min(Double(t.count) / 100.0, 3.0)
        var parent = p.parent, share = 1.0
        for _ in 0..<3 {
            guard let node = parent, node.kind == .element else { break }
            let id = ObjectIdentifier(node)
            scores[id] = (node, (scores[id]?.score ?? 0) + s * share)
            parent = node.parent; share /= 2
        }
    }
    guard let best = scores.values.max(by: { $0.score < $1.score })?.node else { return (title, []) }

    var passages: [Passage] = []
    for node in try best.nodes(forXPath: ".//h1|.//h2|.//h3|.//h4|.//p|.//li|.//blockquote|.//pre") {
        guard let el = node as? XMLElement, let name = el.name else { continue }
        // skip blocks nested inside another block we already take (li > p, blockquote > p)
        if name == "p", let up = el.parent?.name, ["li", "blockquote"].contains(up) { continue }
        let t = text(of: el)
        let linked = ((try? el.nodes(forXPath: ".//a")) ?? []).map(text(of:)).joined().count
        let isHeading = name.hasPrefix("h")
        if t.count < (isHeading ? 3 : 40) { continue }
        if !isHeading, Double(linked) / Double(max(t.count, 1)) > 0.6 { continue }   // link farms
        passages.append(Passage(kind: isHeading ? "heading" : name, text: t))
    }
    return (title, passages)
}

// ---- SQLite sanity: system library, no dependencies -------------------------------------------
var db: OpaquePointer?
precondition(sqlite3_open(":memory:", &db) == SQLITE_OK)
precondition(sqlite3_exec(db, "CREATE VIRTUAL TABLE t USING fts5(body); INSERT INTO t VALUES('beam of light');", nil, nil, nil) == SQLITE_OK, "fts5 missing")
print("sqlite \(String(cString: sqlite3_libversion())) with FTS5: ok\n")

let urls = CommandLine.arguments.dropFirst()
let config = URLSessionConfiguration.ephemeral
config.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0 (Macintosh; Apple Silicon Mac OS X 26_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"]
config.timeoutIntervalForRequest = 20
let session = URLSession(configuration: config)
for raw in urls {
    guard let url = URL(string: raw) else { continue }
    let clock = ContinuousClock(); let t0 = clock.now
    do {
        let (data, response) = try await session.data(from: url)
        let t1 = clock.now
        let (title, passages) = try extract(data, response: response)
        let words = passages.reduce(0) { $0 + $1.text.split(separator: " ").count }
        let body = passages.filter { $0.kind != "heading" }
        print("■ \(raw.prefix(78))")
        print("  http \((response as? HTTPURLResponse)?.statusCode ?? 0) · \(data.count / 1024) KB · fetch \(t1 - t0) · parse \(clock.now - t1)")
        print("  “\(title.prefix(70))” → \(passages.count) passages (\(body.count) body), \(words) words")
        for p in body.prefix(2) { print("    · \(p.text.prefix(110))") }
        if let last = body.last { print("    … \(last.text.prefix(90))") }
    } catch { print("■ \(raw.prefix(70))\n  FAILED: \(error.localizedDescription)") }
}
