import Foundation

/// A response that is JSON wearing a web page's Content-Type.
///
/// Some servers content-negotiate an ActivityPub or JSON-API representation and still label it `text/html`
/// (WordPress's ActivityPub plugin does exactly this), so the header guard in `PageFetcher` cannot catch it.
/// Handed to the HTML parser, the JSON survives as one enormous paragraph and the reader shows `{"@context":…`
/// where the article should be — which is the worst kind of failure, because it looks like content.
///
/// The article is usually in there: ActivityStreams keeps the post's HTML in `content`, schema.org keeps it in
/// `articleBody`. So this reads the body out where it can, and says plainly that the page was not a page where
/// it cannot, rather than letting raw JSON reach the reader either way.
public enum JSONPage {
    /// Fields that carry a post's own HTML, in the order worth trusting.
    private static let bodyKeys = ["content", "articleBody", "body", "html", "text"]
    /// Shorter than this and it is a teaser or a label, not an article.
    private static let minimumLength = 200

    /// `nil` when the text is not JSON at all — the ordinary case, which must stay cheap.
    public static func body(of text: String) -> Outcome? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, first == "{" || first == "[",
              let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data)
        else { return nil }
        guard let found = search(json, depth: 0) else { return .notAPage }
        return .fragment(found)
    }

    public enum Outcome {
        /// The post's own HTML, ready for the ordinary fragment pipeline.
        case fragment(String)
        /// JSON with nothing readable in it: a feed index, an API envelope, an error object.
        case notAPage
    }

    private static func search(_ value: Any, depth: Int) -> String? {
        guard depth < 6 else { return nil }
        if let dictionary = value as? [String: Any] {
            for key in bodyKeys {
                if let body = dictionary[key] as? String, body.count >= minimumLength { return body }
            }
            // `contentMap` holds one translation per language; any of them is better than nothing.
            if let map = dictionary["contentMap"] as? [String: String],
               let body = map.values.first(where: { $0.count >= minimumLength }) { return body }
            for nested in dictionary.values { if let hit = search(nested, depth: depth + 1) { return hit } }
        } else if let array = value as? [Any] {
            for nested in array { if let hit = search(nested, depth: depth + 1) { return hit } }
        }
        return nil
    }
}
