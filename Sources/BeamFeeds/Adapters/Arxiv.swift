import BeamModels
import Foundation

/// arXiv through its export API. `rss.arxiv.org` is empty at weekends (EVIDENCE.md); the API is not.
/// All requests go through `HostGate.arxiv`: arXiv asks API clients for one request every three seconds.
public enum Arxiv {
    public static let resultsPerRequest = 100

    /// The stored identity of a category source. The result count is added per request.
    public static func feedURL(category: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "export.arxiv.org"
        components.path = "/api/query"
        components.queryItems = [
            URLQueryItem(name: "search_query", value: "cat:\(category)"),
            URLQueryItem(name: "sortBy", value: "submittedDate"),
            URLQueryItem(name: "sortOrder", value: "descending"),
        ]
        return components.url
    }

    public static func candidate(category: String) -> SourceCandidate? {
        guard let feedURL = feedURL(category: category) else { return nil }
        return SourceCandidate(kind: .arxiv, title: "arXiv \(category)", feedURL: feedURL,
                               siteURL: URL(string: "https://arxiv.org/list/\(category)/recent"))
    }

    static func requestURL(for feedURL: URL) -> URL { feedURL.settingQueryItem("max_results", to: String(resultsPerRequest)) }

    static func matches(feedURL: URL) -> Bool { feedURL.bareHost == "export.arxiv.org" && feedURL.path.hasPrefix("/api/query") }

    // MARK: Categories

    /// arXiv's archives. A typed word is only a category if it starts with one of these, so "example.com" is not.
    private static let archives: Set<String> = [
        "astro-ph", "cond-mat", "cs", "econ", "eess", "gr-qc", "hep-ex", "hep-lat", "hep-ph", "hep-th", "math", "math-ph",
        "nlin", "nucl-ex", "nucl-th", "physics", "q-bio", "q-fin", "quant-ph", "stat",
    ]

    /// Accepts "cs.LG", "cs.lg", "stat.ML", "hep-th", "cond-mat.mes-hall" and returns arXiv's own spelling, else nil.
    public static func category(named text: String) -> String? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard (1...2).contains(parts.count), archives.contains(parts[0].lowercased()) else { return nil }
        guard parts.count == 2 else { return parts[0].lowercased() }
        let subject = parts[1]
        guard (2...12).contains(subject.count), subject.allSatisfy({ $0.isASCII && ($0.isLetter || $0 == "-") }) else { return nil }
        // Two-letter subjects are written in capitals (cs.LG); the long ones in lowercase (cond-mat.mes-hall).
        return parts[0].lowercased() + "." + (subject.count == 2 ? subject.uppercased() : subject.lowercased())
    }

    /// The category of an arxiv.org listing page: `/list/cs.LG/recent`, `/list/cs.LG/new`, `/list/cs.LG`.
    static func category(inListingURL url: URL) -> String? {
        guard url.bareHost == "arxiv.org" else { return nil }
        let segments = url.pathSegments
        guard segments.count >= 2, segments[0] == "list" else { return nil }
        return category(named: segments[1])
    }

    // MARK: Items

    /// arXiv identifies a paper as `http://arxiv.org/abs/2509.01234v2`. The version suffix changes with every
    /// revision, so identity drops it (a revision is an edit, not a new paper), and links move to https.
    static func refine(_ items: [FeedItem]) -> [FeedItem] {
        items.map { item in
            var refined = item
            refined.guid = secure(item.guid).replacingOccurrences(of: #"v\d+$"#, with: "", options: .regularExpression)
            refined.url = item.url.flatMap { URL(string: secure($0.absoluteString)) }
            return refined
        }
    }

    private static func secure(_ address: String) -> String {
        address.hasPrefix("http://arxiv.org/") ? "https://" + address.dropFirst("http://".count) : address
    }
}
