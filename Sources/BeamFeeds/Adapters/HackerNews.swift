import BeamModels
import Foundation

/// The Hacker News front page through Algolia's search API: one request, no key (PRODUCT.md addendum).
public enum HackerNews {
    /// The stored identity of the source. The page size is added per request, so changing it never orphans a stored source.
    public static let feedURL = URL(literal: "https://hn.algolia.com/api/v1/search?tags=front_page")
    public static let siteURL = URL(literal: "https://news.ycombinator.com/")
    public static let candidate = SourceCandidate(kind: .hackerNews, title: "Hacker News", feedURL: feedURL, siteURL: siteURL)

    /// The front page holds 30 stories; Algolia returns 20 unless asked.
    static func requestURL(for feedURL: URL) -> URL { feedURL.settingQueryItem("hitsPerPage", to: "30") }

    /// Any news.ycombinator.com address means "the front page": there is nothing else on that host to follow.
    static func matches(_ url: URL) -> Bool {
        url.bareHost == "news.ycombinator.com" || (url.bareHost == "hn.algolia.com" && url.path.hasPrefix("/api/"))
    }

    /// A story's snippet is the domain it links to: with a bare title, that is the only other signal the judge
    /// gets (PRODUCT.md section 5, "HN: title plus domain"). Text posts carry their own words instead.
    public static func items(fromSearchResponse data: Data) throws -> [FeedItem] {
        let response: SearchResponse
        do { response = try JSONDecoder().decode(SearchResponse.self, from: data) } catch { throw FeedError.notAFeed }
        return response.hits.compactMap { hit -> FeedItem? in
            let title = HTMLText.collapseWhitespace(hit.title ?? "")
            guard !title.isEmpty else { return nil }
            let discussion = URL(string: "https://news.ycombinator.com/item?id=\(hit.objectID)")
            let link = hit.url.flatMap { URL(string: $0.trimmingCharacters(in: .whitespaces)) }
            let text = hit.storyText.map { HTMLText.snippet(fromHTML: $0) } ?? ""
            let snippet = link?.bareHost ?? (text.isEmpty ? "news.ycombinator.com" : text)
            return FeedItem(guid: hit.objectID, url: link ?? discussion, title: title, snippet: snippet,
                            content: hit.storyText, published: hit.createdAtSeconds.map(Date.init(timeIntervalSince1970:)))
        }
    }

    private struct SearchResponse: Decodable { let hits: [Hit] }

    private struct Hit: Decodable {
        let objectID: String
        let title: String?
        let url: String?
        let storyText: String?
        let createdAtSeconds: TimeInterval?

        enum CodingKeys: String, CodingKey {
            case objectID, title, url
            case storyText = "story_text"
            case createdAtSeconds = "created_at_i"
        }
    }
}
