import BeamModels
import Foundation

/// What a refresh changed, so the engine judges exactly these items and nothing else.
public struct UpsertResult: Hashable, Sendable {
    /// Items seen for the first time, in feed order.
    public var newIDs: [Int64] = []
    /// Items whose judged text (title, snippet or repo name) changed. Their old judgments no longer match.
    public var editedIDs: [Int64] = []

    public init(newIDs: [Int64] = [], editedIDs: [Int64] = []) {
        self.newIDs = newIDs; self.editedIDs = editedIDs
    }
}

extension Database {
    /// How stale `seen` may get before a refresh rewrites it. The purge works in years, so a day's precision is plenty,
    /// and re-reading an unchanged feed every half hour costs no writes at all. The purge allows for the same slack.
    static let seenPrecision: TimeInterval = 86_400

    /// Stores one fetch of one source, in one transaction.
    ///
    /// An incoming item is the same as a stored one when the GUID matches, else when the link matches
    /// (feeds do regenerate GUIDs). A match keeps its row, and with it `read`, `opened` and `fetched`;
    /// when its title or snippet changed, `text_hash` changes too and the item reads "not checked" until judged again.
    ///
    /// - Parameter repoName: "mlx" for a release feed, where it becomes part of the judged text; nil for every other source.
    ///   It has no default on purpose: passing it on one refresh path and forgetting it on another would flip the
    ///   text hash back and forth, and every flip is an edit that gets judged again.
    /// - Parameter now: becomes `fetched` for new items; a parameter so checks can travel in time.
    @discardableResult
    public func upsertItems(_ feedItems: [FeedItem], sourceID: Int64, repoName: String?, now: Date = Date()) throws -> UpsertResult {
        try connection.transaction {
            let sourceExists = try connection.first("SELECT 1 FROM source WHERE id = ?", [sourceID]) { _ in true } ?? false
            guard sourceExists else { throw StoreError.notFound("source \(sourceID)") }

            var result = UpsertResult()
            // Reversed, so the feed's first entry gets the highest id: undated items, which all share one `fetched`
            // time and are ordered by id, then list in the feed's own order.
            for feedItem in Self.withoutRepeats(feedItems).reversed() {
                // Hashing the judged text goes through Foundation's JSON encoder, which autoreleases;
                // draining per item keeps a 50,000-item import flat instead of hundreds of megabytes tall.
                try autoreleasepool {
                    let incoming = Item(sourceID: sourceID, guid: Self.identity(of: feedItem), url: feedItem.url, title: feedItem.title,
                                        snippet: feedItem.snippet, content: feedItem.content, published: feedItem.published,
                                        fetched: now, repoName: repoName)
                    if let stored = try storedMatch(for: incoming) {
                        if try refresh(stored, with: incoming, now: now) { result.editedIDs.append(stored.id) }
                    } else {
                        result.newIDs.append(try insert(incoming))
                    }
                }
            }
            result.newIDs.reverse()
            result.editedIDs.reverse()
            return result
        }
    }

    // MARK: Identity

    /// A feed can list the same entry twice. The first occurrence wins, so a duplicated GUID with two different
    /// titles cannot make the row flip between them, reporting an edit (and costing a judgment) on every refresh.
    private static func withoutRepeats(_ feedItems: [FeedItem]) -> [FeedItem] {
        var identities = Set<String>()
        var links = Set<String>()
        return feedItems.filter { feedItem in
            guard identities.insert(identity(of: feedItem)).inserted else { return false }
            guard let link = feedItem.url?.absoluteString else { return true }
            return links.insert(link).inserted
        }
    }

    /// The GUID, else the link, else a hash of the text: two entries with an empty GUID must not collapse into one row.
    private static func identity(of feedItem: FeedItem) -> String {
        if !feedItem.guid.isEmpty { return feedItem.guid }
        return feedItem.url?.absoluteString ?? Hashing.sha256(feedItem.title + "\n" + feedItem.snippet)
    }

    // MARK: Matching and writing

    /// The few stored facts needed to decide whether anything changed. `content` is compared inside SQLite, never loaded.
    private struct StoredMatch {
        var id: Int64
        var guid: String
        var url: String?
        var textHash: String
        var lacksPublished: Bool
        var seen: Date
        var hasSameContent: Bool
    }

    private func storedMatch(for incoming: Item) throws -> StoredMatch? {
        let columns = "id, guid, url, text_hash, published IS NULL, seen, content IS ?1"
        let read: (Row) -> StoredMatch = { row in
            StoredMatch(id: row.int64(0), guid: row.string(1), url: row.optionalString(2), textHash: row.string(3),
                        lacksPublished: row.bool(4), seen: row.date(5), hasSameContent: row.bool(6))
        }
        if let byGUID = try connection.first("SELECT \(columns) FROM item WHERE source_id = ?2 AND guid = ?3",
                                             [incoming.content, incoming.sourceID, incoming.guid], read) {
            return byGUID
        }
        guard let url = incoming.url else { return nil }
        return try connection.first("SELECT \(columns) FROM item WHERE source_id = ?2 AND url = ?3 ORDER BY id LIMIT 1",
                                    [incoming.content, incoming.sourceID, url], read)
    }

    private func insert(_ item: Item) throws -> Int64 {
        try connection.execute("""
            INSERT INTO item(source_id, guid, url, title, snippet, published, fetched, seen, repo_name, text_hash, content)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, [item.sourceID, item.guid, item.url, item.title, item.snippet, item.published, item.fetched, item.fetched,
                  item.repoName, item.textHash, item.content])
        return try connection.lastInsertedID
    }

    /// Brings a stored row up to date with the feed. Returns true when the judged text changed.
    /// `published` is only ever filled in, never moved: a feed that re-dates its entries must not reshuffle the list.
    private func refresh(_ stored: StoredMatch, with incoming: Item, now: Date) throws -> Bool {
        let incomingURL = incoming.url?.absoluteString
        let textHash = incoming.textHash
        let textChanged = stored.textHash != textHash
        let sourceTextChanged = !stored.hasSameContent || stored.url != incomingURL
        let changed = textChanged || sourceTextChanged || stored.guid != incoming.guid
            || (stored.lacksPublished && incoming.published != nil)
            || now.timeIntervalSince(stored.seen) > Self.seenPrecision
        guard changed else { return false }

        try connection.execute("""
            UPDATE item SET guid = ?, url = ?, title = ?, snippet = ?, published = COALESCE(published, ?), seen = MAX(seen, ?),
                            repo_name = ?, text_hash = ?, content = ? WHERE id = ?
            """, [incoming.guid, incoming.url, incoming.title, incoming.snippet, incoming.published, now,
                  incoming.repoName, textHash, incoming.content, stored.id])
        // The cached article was extracted from the old content or the old address.
        if sourceTextChanged { try connection.execute("DELETE FROM article WHERE item_id = ?", [stored.id]) }
        return textChanged
    }
}
