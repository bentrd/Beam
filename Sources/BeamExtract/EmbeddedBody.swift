import Foundation

/// Many news sites render their text with JavaScript but still publish it, for search engines, as schema.org JSON-LD
/// `articleBody`. When the markup yields nothing readable, that string is the article.
enum EmbeddedBody {
    /// Shorter bodies are teasers ("Read the full story…"), not articles.
    static let minimumLength = 600

    /// The embedded article as a minimal HTML fragment, one `<p>` per line, or nil when the page carries none.
    /// Going back through the HTML pipeline lets tidy deal with the entities and stray tags publishers leave in.
    static func fragment(in html: String) -> String? {
        for payload in HTMLPreprocessor.jsonLDPayloads(in: html) {
            guard let data = payload.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data),
                  let body = search(json, depth: 0) else { continue }
            return body.components(separatedBy: .newlines).map { "<p>\($0)</p>" }.joined(separator: "\n")
        }
        return nil
    }

    private static func search(_ value: Any, depth: Int) -> String? {
        guard depth < 8 else { return nil }
        if let dictionary = value as? [String: Any] {
            if let body = dictionary["articleBody"] as? String, body.count >= minimumLength { return body }
            for nested in dictionary.values { if let hit = search(nested, depth: depth + 1) { return hit } }
        } else if let array = value as? [Any] {
            for nested in array { if let hit = search(nested, depth: depth + 1) { return hit } }
        }
        return nil
    }
}
