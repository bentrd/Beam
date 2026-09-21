import BeamModels
import Foundation

/// Decides, for one recorded entry, which title, link, date, snippet and identity Beam keeps.
struct FeedItemBuilder {
    /// Relative links resolve against this: the address the feed was actually served from.
    let baseURL: URL
    let now: Date

    /// A feed dated further ahead than this is wrong, not early; see `published(for:)`.
    private static let futureTolerance: TimeInterval = 24 * 3600

    func item(from entry: RawEntry) -> FeedItem? {
        let url = link(for: entry)
        let body = entry.summary ?? entry.mediaDescription ?? entry.content
        let snippet = body.map(Self.snippet) ?? ""
        let title = title(for: entry, snippet: snippet, url: url)
        guard !title.isEmpty else { return nil }
        let published = published(for: entry)
        return FeedItem(guid: guid(for: entry, url: url, title: title, published: published), url: url, title: title,
                        snippet: snippet, content: content(for: entry, snippet: snippet), published: published)
    }

    // MARK: Title

    /// Inline markup a title may carry. Anything else in angle brackets is what the title is about ("The <dialog> element").
    private static let inlineTags: Set<String> = ["a", "b", "i", "em", "strong", "span", "code", "sup", "sub", "u", "cite", "small", "mark"]

    static func plainTitle(_ raw: RawText) -> String {
        switch raw.kind {
        case .plain: return HTMLText.collapseWhitespace(raw.text)
        case .html: return HTMLText.plainText(fromHTML: raw.text)
        case .looseTitle:
            return HTMLText.collapseWhitespace(HTMLText.decodeEntities(HTMLText.strippingTags(from: raw.text, only: inlineTags)))
        }
    }

    /// Untitled entries (microblogs, link posts) take their opening words, so a row is never blank.
    private func title(for entry: RawEntry, snippet: String, url: URL?) -> String {
        for candidate in [entry.title, entry.mediaTitle].compactMap({ $0 }) {
            let title = Self.plainTitle(candidate)
            if !title.isEmpty { return title }
        }
        if !snippet.isEmpty { return HTMLText.snippet(fromPlainText: snippet, limit: 100) }
        guard let url else { return "" }
        return (url.host ?? "") + url.path
    }

    // MARK: Snippet and content

    /// Lines that publishing tools add to every excerpt and that say nothing about the item. They would be judged
    /// as if they did, and the WordPress footer even names the source, which the judge must never see
    /// (PRODUCT.md section 5).
    private static let boilerplate: [NSRegularExpression] = [
        // WordPress, in English and in French.
        #"\s*The post .{1,300} (?:first )?appeared first on .{1,120}$"#,
        #"\s*L['’]article .{1,300} est apparu en premier sur .{1,120}$"#,
        // "… Read More <title>" closing an excerpt; only after the end of a sentence, so prose about reading more survives.
        #"(?<=[.!?…\]»])\s*(?:Read more|Continue reading|Lire la suite)\b.{0,200}$"#,
        // Link aggregators whose whole description is a link to the discussion.
        #"^Comments$"#,
    ].compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive, .dotMatchesLineSeparators]) }

    static func snippet(from raw: RawText) -> String {
        var text = raw.kind == .plain ? HTMLText.collapseWhitespace(raw.text) : HTMLText.plainText(fromHTML: raw.text)
        for pattern in boilerplate {
            text = pattern.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }
        return HTMLText.snippet(fromPlainText: text)
    }

    /// The fullest body the feed carries, kept only when it says more than the snippet already does.
    private func content(for entry: RawEntry, snippet: String) -> String? {
        let bodies = [entry.content, entry.summary, entry.mediaDescription].compactMap { $0 }
        guard let fullest = bodies.max(by: { $0.text.count < $1.text.count }) else { return nil }
        let text = fullest.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let plainLength = fullest.kind == .plain ? text.count : HTMLText.plainText(fromHTML: text).count
        return plainLength > snippet.count ? text : nil
    }

    // MARK: Link

    /// Atom links that point somewhere other than the item itself.
    private static let nonArticleRelations: Set<String> = ["self", "enclosure", "replies", "edit", "hub", "license", "next", "previous"]

    private func link(for entry: RawEntry) -> URL? {
        rawLink(for: entry).map(Self.removingCampaignParameters)
    }

    /// `utm_source=rss` and its siblings tell the publisher which reader sent the click. Beam does not say.
    static func removingCampaignParameters(from url: URL) -> URL {
        guard let query = url.query, query.contains("utm_"), var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return url }
        // The percent-encoded items, so the parameters that stay are byte for byte what the publisher wrote.
        let kept = (components.percentEncodedQueryItems ?? []).filter { !$0.name.lowercased().hasPrefix("utm_") }
        components.percentEncodedQueryItems = kept.isEmpty ? nil : kept
        return components.url ?? url
    }

    private func rawLink(for entry: RawEntry) -> URL? {
        if let text = entry.linkText, let url = resolve(text) { return url }
        let alternates = entry.links.filter { $0.rel == "alternate" }
        let preferred = alternates.first(where: { $0.type == nil || $0.type?.contains("html") == true }) ?? alternates.first
            ?? entry.links.first(where: { !Self.nonArticleRelations.contains($0.rel) })
        if let preferred, let url = resolve(preferred.href) { return url }
        if entry.guidIsPermalink, let guid = entry.guid, guid.lowercased().hasPrefix("http"), let url = resolve(guid) { return url }
        if let about = entry.about, let url = resolve(about) { return url }
        return nil
    }

    /// Only web addresses: a `tag:` or `urn:` identifier is not something Open Original can open.
    func resolve(_ reference: String) -> URL? {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed, relativeTo: baseURL)?.absoluteURL,
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", url.host != nil else { return nil }
        return url
    }

    // MARK: Identity and date

    /// The feed's own identifier, else the link, else a hash of what little there is; the store dedupes on this.
    private func guid(for entry: RawEntry, url: URL?, title: String, published: Date?) -> String {
        if let guid = entry.guid ?? entry.about, !guid.isEmpty { return guid }
        if let url { return url.absoluteString }
        let stamp = published.map { String(Int($0.timeIntervalSince1970)) } ?? ""
        return "sha256:" + Hashing.sha256(title + "\n" + stamp)
    }

    /// A date more than a day ahead would pin the item to the top of every list for as long as the feed is wrong,
    /// so it is dropped and the item sorts by when Beam first saw it.
    private func published(for entry: RawEntry) -> Date? {
        let date = [entry.published, entry.updated].compactMap { $0 }.lazy.compactMap(FeedDate.parse).first
        guard let date, date.timeIntervalSince(now) <= Self.futureTolerance else { return nil }
        return date
    }
}
