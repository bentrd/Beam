import Foundation

/// The schema, as a list of migrations applied in order. `PRAGMA user_version` records how many have run.
///
/// Rules for whoever adds version 2: append a new script, never edit a shipped one.
///
/// Conventions: every REAL date is seconds since 2001-01-01 UTC (see `Date.sqlValue`).
/// `removed` is the soft-delete stamp behind Undo: a removed row keeps everything that hangs off it,
/// is invisible to every list and count, and is deleted for good the next time the database opens.
enum Schema {
    static let migrations = [version1]

    /// Brings the file up to date, one transaction per version, so a crash midway leaves a valid older schema.
    static func migrate(_ connection: Connection) throws {
        let current = try connection.scalar("PRAGMA user_version") { $0.int(0) }
        guard current <= migrations.count else {
            throw StoreError.newerSchema(found: current, supported: migrations.count)
        }
        for version in current..<migrations.count {
            try connection.transaction {
                try connection.execute(script: migrations[version])
                try connection.execute(script: "PRAGMA user_version = \(version + 1)")
            }
        }
    }

    static func version(of connection: Connection) throws -> Int {
        try connection.scalar("PRAGMA user_version") { $0.int(0) }
    }

    private static let version1 = """
    CREATE TABLE source(
        id INTEGER PRIMARY KEY,
        kind TEXT NOT NULL,
        title TEXT NOT NULL,
        feed_url TEXT NOT NULL UNIQUE,
        site_url TEXT,
        position INTEGER NOT NULL,
        last_fetch REAL,
        last_error TEXT,
        failing_since REAL,
        removed REAL
    );

    -- `fetched` is when Beam first saw the item and never changes; `seen` is when it last appeared in its feed (to the day),
    -- which keeps the yearly purge from deleting old posts a feed still lists (they would come back as new, unread).
    -- `content` is last so list queries, which never select it, do not touch its overflow pages.
    CREATE TABLE item(
        id INTEGER PRIMARY KEY,
        source_id INTEGER NOT NULL REFERENCES source(id) ON DELETE CASCADE,
        guid TEXT NOT NULL,
        url TEXT,
        title TEXT NOT NULL,
        snippet TEXT NOT NULL,
        published REAL,
        fetched REAL NOT NULL,
        seen REAL NOT NULL,
        opened REAL,
        read INTEGER NOT NULL DEFAULT 0,
        repo_name TEXT,
        text_hash TEXT NOT NULL,
        content TEXT,
        UNIQUE(source_id, guid)
    );
    -- List order is COALESCE(published, fetched), newest first, id breaking ties. Queries must spell it the same way.
    CREATE INDEX item_sort ON item(COALESCE(published, fetched) DESC, id DESC);
    CREATE INDEX item_source_sort ON item(source_id, COALESCE(published, fetched) DESC, id DESC);
    CREATE INDEX item_source_url ON item(source_id, url);
    -- Partial indexes of unread rows only: the sidebar counts and Hide Read Items never wade through what was read,
    -- which for a regular reader is nearly everything.
    CREATE INDEX item_unread ON item(source_id, COALESCE(published, fetched) DESC, id DESC) WHERE read = 0;
    CREATE INDEX item_unread_sort ON item(COALESCE(published, fetched) DESC, id DESC) WHERE read = 0;

    CREATE TABLE pin(
        id INTEGER PRIMARY KEY,
        sentence TEXT NOT NULL UNIQUE,
        position INTEGER NOT NULL,
        created REAL NOT NULL,
        last_viewed REAL,
        removed REAL
    );

    -- A cache keyed by content, not by item: editing an item changes its text_hash and the old rows simply stop matching.
    CREATE TABLE judgment(
        text_hash TEXT NOT NULL,
        sentence_hash TEXT NOT NULL,
        model TEXT NOT NULL,
        p REAL NOT NULL CHECK (p >= 0 AND p <= 1),
        at REAL NOT NULL,
        PRIMARY KEY(text_hash, sentence_hash, model)
    ) WITHOUT ROWID;
    CREATE INDEX judgment_sentence ON judgment(sentence_hash, model);

    CREATE TABLE article(
        item_id INTEGER PRIMARY KEY REFERENCES item(id) ON DELETE CASCADE,
        state TEXT NOT NULL,
        reason TEXT,
        passages TEXT,
        images INTEGER NOT NULL DEFAULT 0,
        tables INTEGER NOT NULL DEFAULT 0,
        fetched REAL NOT NULL
    );

    CREATE TABLE spend(day TEXT PRIMARY KEY, tokens INTEGER NOT NULL) WITHOUT ROWID;
    CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID;
    """
}
