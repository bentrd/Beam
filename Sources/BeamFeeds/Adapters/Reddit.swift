import BeamModels
import Foundation

/// Subreddits through their Atom feed. Best-effort by decree (PRODUCT.md MUST 2): Reddit throttles hard, so
/// requests go one at a time through `HostGate.reddit`, name the app honestly, and honour `Retry-After`.
public enum Reddit {
    public static func candidate(subreddit: String) -> SourceCandidate? {
        guard let feedURL = URL(string: "https://www.reddit.com/r/\(subreddit)/.rss") else { return nil }
        return SourceCandidate(kind: .reddit, title: "r/\(subreddit)", feedURL: feedURL,
                               siteURL: URL(string: "https://www.reddit.com/r/\(subreddit)/"))
    }

    /// `reddit.com/r/swift`, `old.reddit.com/r/swift/top`, or the shorthand `r/swift` and `/r/swift`.
    static func subreddit(in text: String) -> String? {
        var segments = text.split(separator: "/").map(String.init)
        if let url = URL(string: text), let host = url.bareHost {
            guard host == "reddit.com" || host.hasSuffix(".reddit.com") else { return nil }
            segments = url.pathSegments
        }
        guard segments.count >= 2, segments[0].lowercased() == "r" else { return nil }
        let name = segments[1]
        let isValid = (2...21).contains(name.count) && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
        return isValid ? name : nil
    }

    static func matches(feedURL: URL) -> Bool {
        guard let host = feedURL.bareHost else { return false }
        return host == "reddit.com" || host.hasSuffix(".reddit.com")
    }

    // MARK: Items

    /// Every Reddit entry ends "submitted by /u/name [link] [comments]". It is not the post, and it would be judged.
    private static let signatureInText = #"\s*submitted by\s+/u/\S+(\s+to\s+r/\S+)?(\s*\[link\])?(\s*\[comments\])?\s*$"#
    private static let signatureInHTML = #"(?:&#32;|\s)*submitted by(?:&#32;|\s)*<a [^>]*>\s*/u/.*$"#

    static func refine(_ items: [FeedItem]) -> [FeedItem] {
        items.map { item in
            var refined = item
            let text = item.content.map(HTMLText.plainText(fromHTML:)) ?? item.snippet
            let post = text.replacingOccurrences(of: signatureInText, with: "", options: [.regularExpression, .caseInsensitive])
            refined.snippet = HTMLText.snippet(fromPlainText: post)
            refined.content = post.count > refined.snippet.count
                ? item.content?.replacingOccurrences(of: signatureInHTML, with: "", options: [.regularExpression, .caseInsensitive])
                : nil
            return refined
        }
    }
}
