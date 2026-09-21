import BeamModels
import Foundation

enum Fixtures {
    /// A fixed instant, so every run sees the same dates.
    static let now = Date(timeIntervalSinceReferenceDate: 780_000_000)
    static let day: TimeInterval = 86_400

    static func candidate(_ name: String, kind: SourceKind = .feed) -> SourceCandidate {
        SourceCandidate(kind: kind, title: name, feedURL: url("https://\(name).example/feed.xml"), siteURL: url("https://\(name).example/"))
    }

    static func feedItem(_ number: Int, title: String? = nil, snippet: String? = nil, guid: String? = nil,
                         content: String? = nil, published: Date? = now) -> FeedItem {
        FeedItem(guid: guid ?? "guid-\(number)", url: url("https://posts.example/\(number)"), title: title ?? "Title \(number)",
                 snippet: snippet ?? "Snippet of item \(number).", content: content,
                 published: published.map { $0.addingTimeInterval(-Double(number) * 60) })
    }

    static func url(_ string: String) -> URL {
        guard let url = URL(string: string) else { fatalError("fixture URL '\(string)' is not a URL") }
        return url
    }

    // MARK: Synthetic volume

    private static let words = ["swift", "kernel", "latency", "model", "paper", "release", "silicon", "privacy", "compiler", "feed",
                                "reader", "ranking", "paragraph", "sentence", "cache", "index", "metal", "tensor", "battery", "layout"]

    /// A deterministic, realistic item: an eight-word title, a snippet near the 300-character cap,
    /// full feed content on every tenth item, no date on every twentieth.
    static func syntheticItem(source: Int, number: Int, sourceCount: Int) -> FeedItem {
        var state = UInt64(source) &* 1_000_003 &+ UInt64(number) &* 7_919 &+ 17
        func word() -> String {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return words[Int((state >> 33) % UInt64(words.count))]
        }
        let title = (0..<8).map { _ in word() }.joined(separator: " ")
        let snippet = String((0..<44).map { _ in word() }.joined(separator: " ").prefix(300))
        let content = number % 10 == 0 ? "<p>" + (0..<600).map { _ in word() }.joined(separator: " ") + "</p>" : nil
        // One item every 630 s across all sources: 50,000 of them span the year Beam keeps.
        let published = number % 20 == 19 ? nil : now.addingTimeInterval(-Double(number * sourceCount + source) * 630)
        return FeedItem(guid: "s\(source)-\(number)", url: url("https://source\(source).example/post/\(number)"),
                        title: title, snippet: snippet, content: content, published: published)
    }
}
