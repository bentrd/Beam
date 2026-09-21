import Foundation

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

/// Split one long block into passages at sentence ends, never exceeding ~1,200 characters.
func splitLong(_ text: String, limit: Int = 1200) -> [String] {
    guard text.count > limit else { return [text] }
    var out: [String] = [], current = ""
    text.enumerateSubstrings(in: text.startIndex..., options: [.bySentences]) { sentence, _, _, _ in
        guard let sentence else { return }
        if current.count + sentence.count > limit, current.count > 200 { out.append(current.trimmingCharacters(in: .whitespaces)); current = "" }
        current += sentence
    }
    if !current.trimmingCharacters(in: .whitespaces).isEmpty { out.append(current.trimmingCharacters(in: .whitespaces)) }
    return out
}

/// Many news sites embed the whole article as schema.org JSON-LD `articleBody`.
func articleBody(in doc: XMLDocument) -> String? {
    func find(_ any: Any) -> String? {
        if let d = any as? [String: Any] {
            if let body = d["articleBody"] as? String, body.count > 600 { return body }
            for v in d.values { if let hit = find(v) { return hit } }
        } else if let a = any as? [Any] { for v in a { if let hit = find(v) { return hit } } }
        return nil
    }
    for node in (try? doc.nodes(forXPath: "//script[@type='application/ld+json']")) ?? [] {
        guard let raw = node.stringValue?.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: raw) else { continue }
        if let body = find(json) { return body }
    }
    return nil
}

func extract(_ data: Data, response: URLResponse? = nil) throws -> (title: String, passages: [Passage]) {
    let html = decode(data, response: response)
    let doc = try XMLDocument(xmlString: html, options: [.documentTidyHTML, .nodeLoadExternalEntitiesNever])
    let embedded = articleBody(in: doc)
    for junk in try doc.nodes(forXPath: "//script|//style|//noscript|//nav|//footer|//aside|//form|//iframe|//svg|//button|//figure/figcaption|//*[contains(@class,'reference') or contains(@class,'reflist') or contains(@class,'citation')]") {
        junk.detach()
    }
    let title = (try? doc.nodes(forXPath: "//title").first).flatMap { $0 }.map(text(of:)) ?? ""

    func collect(from root: XMLNode) -> [Passage] {
        var passages: [Passage] = []
        for node in (try? root.nodes(forXPath: ".//h1|.//h2|.//h3|.//h4|.//p|.//li|.//blockquote|.//pre|.//div[not(*) or count(text()[string-length(normalize-space(.))>80])>0]")) ?? [] {
            guard let el = node as? XMLElement, let name = el.name else { continue }
            if ["p", "div"].contains(name), let up = el.parent?.name, ["li", "blockquote", "p"].contains(up) { continue }
            if name == "div", ((try? el.nodes(forXPath: ".//p|.//li|.//div")) ?? []).count > 0 { continue }   // only leaf-ish text divs
            let t = text(of: el)
            let linked = ((try? el.nodes(forXPath: ".//a")) ?? []).map(text(of:)).joined().count
            let isHeading = name.hasPrefix("h")
            if t.count < (isHeading ? 3 : 40) { continue }
            if !isHeading, Double(linked) / Double(max(t.count, 1)) > 0.6 { continue }
            if isHeading { passages.append(Passage(kind: "heading", text: t)) }
            else { for piece in splitLong(t) { passages.append(Passage(kind: name, text: piece)) } }
        }
        return passages
    }
    func words(_ ps: [Passage]) -> Int { ps.filter { $0.kind != "heading" }.reduce(0) { $0 + $1.text.split(separator: " ").count } }

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
    var best = scores.values.max(by: { $0.score < $1.score }).map { collect(from: $0.node) } ?? []
    // Fallbacks when the scorer found too little: semantic containers, then embedded JSON-LD text.
    if words(best) < 150 {
        for xpath in ["//article", "//main", "//*[@role='main']", "//body"] {
            if let root = try? doc.nodes(forXPath: xpath).first, case let alt = collect(from: root), words(alt) > words(best) { best = alt; if words(best) >= 150 { break } }
        }
    }
    if words(best) < 150, let embedded {
        let paras = embedded.components(separatedBy: CharacterSet.newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.count > 40 }
        let alt = (paras.count > 2 ? paras : splitLong(embedded, limit: 600)).flatMap { splitLong($0) }.map { Passage(kind: "p", text: $0) }
        if words(alt) > words(best) { best = alt }
    }
    return (title, best)
}
