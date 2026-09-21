import Foundation

/// What a purge deleted, for the log.
public struct PurgeResult: Hashable, Sendable {
    public var items: Int
    public var judgments: Int

    public init(items: Int = 0, judgments: Int = 0) {
        self.items = items; self.judgments = judgments
    }
}

extension Database {
    /// Beam keeps a year. Calendar arithmetic, so leap years do not drift the cutoff.
    public static func oneYearBefore(_ now: Date = Date()) -> Date {
        Calendar(identifier: .gregorian).date(byAdding: .year, value: -1, to: now) ?? now.addingTimeInterval(-365 * 86_400)
    }

    /// Deletes what is older than `cutoff`: items (their articles cascade) and cached judgments.
    ///
    /// An item goes only when it is old *and* its feed no longer lists it. A small blog lists its 2019 posts forever;
    /// purging them by date alone would bring them back on the next refresh, as new and unread, every time.
    /// "Still listed" means seen in the source's latest reading, which `MAX(seen)` dates to within `seenPrecision`.
    /// A feed that answers "not modified" or fails for a year is not read at all, so its items keep their standing.
    @discardableResult
    public func purge(olderThan cutoff: Date = Database.oneYearBefore()) throws -> PurgeResult {
        try connection.transaction {
            let items = try connection.execute("""
                WITH listing(source_id, latest) AS MATERIALIZED (SELECT source_id, MAX(seen) FROM item GROUP BY source_id)
                DELETE FROM item
                WHERE COALESCE(published, fetched) < ?1
                  AND seen <= (SELECT latest FROM listing WHERE listing.source_id = item.source_id) - ?2
                """, [cutoff, Self.seenPrecision])
            let judgments = try connection.execute("DELETE FROM judgment WHERE at < ?", [cutoff])
            return PurgeResult(items: items, judgments: judgments)
        }
    }

    /// Makes every removal permanent now, instead of at the next launch. After this, Undo has nothing to restore.
    public func purgeRemoved() throws {
        try Housekeeping.purgeRemoved(connection)
    }
}

/// Work that also runs while the database opens, before the actor exists.
enum Housekeeping {
    /// Deletes removed sources (items and articles cascade) and removed pins, plus the judgments
    /// that only those sources' items could reach. Judgments of a removed pin's sentence stay until they age out:
    /// typing the same sentence again finds them, and they hold no text.
    static func purgeRemoved(_ connection: Connection) throws {
        try connection.transaction {
            let hasRemovedSources = try connection.scalar("SELECT EXISTS(SELECT 1 FROM source WHERE removed IS NOT NULL)") { $0.bool(0) }
            if hasRemovedSources {
                try connection.execute("""
                    DELETE FROM judgment
                    WHERE text_hash IN (SELECT text_hash FROM item WHERE source_id IN (SELECT id FROM source WHERE removed IS NOT NULL))
                      AND text_hash NOT IN (SELECT text_hash FROM item WHERE source_id NOT IN (SELECT id FROM source WHERE removed IS NOT NULL))
                    """)
                try connection.execute("DELETE FROM source WHERE removed IS NOT NULL")
            }
            try connection.execute("DELETE FROM pin WHERE removed IS NOT NULL")
        }
    }
}
