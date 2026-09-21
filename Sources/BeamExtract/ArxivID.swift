import BeamModels
import Foundation

/// arXiv serves most recent papers as real HTML at `arxiv.org/html/<id>`, which reads far better than the abstract
/// page a feed or a Hacker News link points at.
enum ArxivID {
    private static let modern = #"\d{4}\.\d{4,5}(?:v\d+)?"#
    private static let legacy = #"[a-z\-]+(?:\.[A-Z]{2})?/\d{7}(?:v\d+)?"#

    /// The identifier in an `arxiv.org/abs/…`, `/pdf/…` or `/html/…` address.
    static func find(in url: URL) -> String? {
        guard let host = url.host?.lowercased(), host == "arxiv.org" || host.hasSuffix(".arxiv.org") else { return nil }
        guard let range = url.path.range(of: "^/(?:abs|pdf|html)/(?:\(modern)|\(legacy))", options: .regularExpression) else { return nil }
        return url.path[range].split(separator: "/", maxSplits: 2).dropFirst().joined(separator: "/")
    }

    /// Feed items name the paper in their link, or only in a GUID such as `oai:arXiv.org:2509.12345v1`.
    static func find(in item: Item) -> String? {
        if let url = item.url, let identifier = find(in: url) { return identifier }
        return item.guid.range(of: modern, options: .regularExpression).map { String(item.guid[$0]) }
    }

    static func htmlURL(for identifier: String) -> URL? { URL(string: "https://arxiv.org/html/\(identifier)") }
}
