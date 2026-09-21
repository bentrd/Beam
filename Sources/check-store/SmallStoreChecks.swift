import BeamModels
import BeamStore
import Foundation

func checkSmallStores(_ report: inout CheckReport) async throws {
    let database = try Database.inMemory()
    guard case let .added(source) = try await database.addSource(Fixtures.candidate("articles")) else { return }
    let ids = try await database.upsertItems((1...3).map { Fixtures.feedItem($0) }, sourceID: source.id, repoName: nil, now: Fixtures.now).newIDs

    // Articles
    let passages = [Passage(kind: .heading, text: "Déjà vu"), Passage(kind: .paragraph, text: "Un paragraphe « accentué ».", section: "Déjà vu"),
                    Passage(kind: .code, text: "let x = \"quoted\"\n\treturn x", section: "Déjà vu"), Passage(kind: .listItem, text: "One"), Passage(kind: .quote, text: "Two")]
    let contents: [ArticleContent] = [.ready(passages: passages, images: 4, tables: 2), .unavailable(reason: "HTTP 403"), .external]
    for (id, content) in zip(ids, contents) { try await database.putArticle(content, itemID: id, fetched: Fixtures.now) }
    for (id, content) in zip(ids, contents) {
        let stored = try await database.article(itemID: id)
        report.expectEqual(stored, StoredArticle(content: content, fetched: Fixtures.now), "article round-trips: \(String(describing: content).prefix(24))…")
    }
    try await database.putArticle(.ready(passages: Array(passages.prefix(2)), images: 0, tables: 0), itemID: ids[1], fetched: Fixtures.now.addingTimeInterval(60))
    report.expectEqual(try await database.article(itemID: ids[1])?.fetched, Fixtures.now.addingTimeInterval(60), "a retry replaces the stored failure")
    try await database.removeArticle(itemID: ids[0])
    report.expectTrue(try await database.article(itemID: ids[0]) == nil, "removeArticle forgets it")
    let orphan = await failure { try await database.putArticle(.external, itemID: 31_337) }
    report.expectTrue(orphan != nil, "an article for an unknown item is refused by the foreign key")

    // Spend
    let paris = TimeZone(identifier: "Europe/Paris") ?? .current
    let lateEvening = Date(timeIntervalSince1970: 1_790_027_400)   // 2026-09-21 21:50 UTC = 23:50 in Paris
    report.expectEqual(SpendLedger.day(for: lateEvening, timeZone: paris), "2026-09-21", "the day key is the local day")
    report.expectEqual(SpendLedger.day(for: lateEvening.addingTimeInterval(900), timeZone: paris), "2026-09-22", "and it turns at local midnight, not UTC's")
    report.expectEqual(try await database.tokensSpent(onDay: "2026-09-21"), 0, "a day never written is zero")
    report.expectEqual(try await database.addTokensSpent(600, onDay: "2026-09-21"), 600, "adding returns the day's total")
    report.expectEqual(try await database.addTokensSpent(47_000, onDay: "2026-09-21"), 47_600, "and accumulates")
    report.expectEqual(try await database.tokensSpent(onDay: "2026-09-22"), 0, "days are separate")
    let negative = await failure { _ = try await database.addTokensSpent(-1, onDay: "2026-09-21") }
    report.expectTrue(negative != nil, "a negative count is refused")

    try await database.setTokensSpent(50_000, onDay: "2026-09-21")
    report.expectEqual(try await database.tokensSpent(onDay: "2026-09-21"), 50_000, "setting replaces the day's total")

    // The ledger has the shape of the judge's SpendPersisting protocol: tokens(on:) and setTokens(_:on:).
    let ledger = SpendLedger(database: database)
    let today = SpendLedger.day(for: Fixtures.now)
    try await ledger.setTokens(1_000, on: today)
    report.expectEqual(try await ledger.add(tokens: 234, on: today), 1_234, "SpendLedger writes through to the same table")
    report.expectEqual(try await ledger.tokens(on: today), 1_234, "and reads it back")
    report.expectEqual(try await database.tokensSpent(onDay: today), 1_234, "as the database sees it")

    // Meta
    report.expectTrue(try await database.meta("model") == nil, "an unset key is nil")
    try await database.setMeta("model", to: "jev-1.13.0")
    try await database.setMeta("model", to: "jev-1.14.0")
    report.expectEqual(try await database.meta("model"), "jev-1.14.0", "set overwrites")
    try await database.setMeta("empty", to: "")
    report.expectEqual(try await database.meta("empty"), "", "an empty value is a value")
    try await database.setMeta("model", to: nil)
    report.expectTrue(try await database.meta("model") == nil, "nil deletes")
}
