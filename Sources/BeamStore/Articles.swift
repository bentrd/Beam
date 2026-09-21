import BeamModels
import Foundation

/// An extracted article as it was stored, with its age so the engine can decide when a failure deserves another try.
public struct StoredArticle: Hashable, Sendable {
    public var content: ArticleContent
    public var fetched: Date

    public init(content: ArticleContent, fetched: Date) {
        self.content = content; self.fetched = fetched
    }
}

extension Database {
    /// The article cached for an item, or nil when none was stored (or the item's content or link changed since).
    /// Throws `corrupt` when the stored passages cannot be decoded; storing a fresh extraction repairs it.
    public func article(itemID: Int64) throws -> StoredArticle? {
        try connection.first("SELECT state, reason, passages, images, tables, fetched FROM article WHERE item_id = ?", [itemID]) { row in
            let content: ArticleContent
            switch row.string(0) {
            case ArticleState.ready:
                do {
                    let passages = try JSONDecoder().decode([Passage].self, from: Data(row.string(2).utf8))
                    content = .ready(passages: passages, images: row.int(3), tables: row.int(4))
                } catch {
                    throw StoreError.corrupt("passages of article \(itemID): \(error)")
                }
            case ArticleState.unavailable:
                content = .unavailable(reason: row.string(1))
            case ArticleState.external:
                content = .external
            default:
                throw StoreError.corrupt("article state '\(row.string(0))' of item \(itemID)")
            }
            return StoredArticle(content: content, fetched: row.date(5))
        }
    }

    /// Stores (or replaces) the article of an item. Passages are kept as JSON: they are only ever read back whole.
    public func putArticle(_ content: ArticleContent, itemID: Int64, fetched: Date = Date()) throws {
        let state: String
        var reason: String?
        var passagesJSON: String?
        var images = 0
        var tables = 0
        switch content {
        case let .ready(passages, imageCount, tableCount):
            state = ArticleState.ready
            passagesJSON = String(decoding: try JSONEncoder().encode(passages), as: UTF8.self)
            images = imageCount
            tables = tableCount
        case let .unavailable(why):
            state = ArticleState.unavailable
            reason = why
        case .external:
            state = ArticleState.external
        }
        try connection.execute("""
            INSERT INTO article(item_id, state, reason, passages, images, tables, fetched) VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(item_id) DO UPDATE SET state = excluded.state, reason = excluded.reason, passages = excluded.passages,
                images = excluded.images, tables = excluded.tables, fetched = excluded.fetched
            """, [itemID, state, reason, passagesJSON, images, tables, fetched])
    }

    /// Forgets the cached article, so the next open extracts again (Retry on a failed article).
    public func removeArticle(itemID: Int64) throws {
        try connection.execute("DELETE FROM article WHERE item_id = ?", [itemID])
    }
}

/// The `article.state` column. Spelled out here rather than derived from `ArticleContent`,
/// so renaming a Swift case can never orphan stored rows.
private enum ArticleState {
    static let ready = "ready"
    static let unavailable = "unavailable"
    static let external = "external"
}
