import BeamModels
import BeamStore
import Foundation

private struct Interruption: Error {}

func checkItemLifecycle(_ report: inout CheckReport) async throws {
    let database = try Database.inMemory()
    guard case let .added(source) = try await database.addSource(Fixtures.candidate("lifecycle")) else { return }
    let now = Fixtures.now

    // Transactions close on every path.
    let orphan = await failure { _ = try await database.upsertItems([Fixtures.feedItem(1)], sourceID: 9_999, repoName: nil, now: now) }
    report.expectEqual(orphan, .notFound("source 9999"), "items for an unknown source are refused by name")

    let sourceID = source.id
    do {
        try await database.transaction { database in
            _ = try database.upsertItems((1...5).map { Fixtures.feedItem($0) }, sourceID: sourceID, repoName: nil, now: now)
            _ = try database.addPin(sentence: "rolled back with the rest")
            throw Interruption()
        }
    } catch is Interruption {}
    report.expectEqual(try await database.itemCount(), 0, "an error inside transaction{} rolls back the nested upsert")
    report.expectTrue(try await database.pins().isEmpty, "and everything else in it")

    let committed = try await database.transaction { database in
        try database.upsertItems((1...5).map { Fixtures.feedItem($0) }, sourceID: sourceID, repoName: nil, now: now).newIDs.count
    }
    report.expectEqual(committed, 5, "the connection is usable afterwards: the failed transaction was closed")
    report.expectEqual(try await database.itemCount(), 5, "and a successful transaction{} commits")

    // An edit to the content or the link invalidates the cached article; an edit to the title does not.
    let items = try await database.newestItems(limit: 5)
    let article = ArticleContent.ready(passages: [Passage(kind: .paragraph, text: "Body")], images: 0, tables: 0)
    for item in items.prefix(2) { try await database.putArticle(article, itemID: item.id, fetched: now) }
    _ = try await database.upsertItems([Fixtures.feedItem(1, title: "Retitled"), Fixtures.feedItem(2, content: "<p>Rewritten</p>")], sourceID: sourceID, repoName: nil, now: now)
    report.expectTrue(try await database.article(itemID: items[0].id) != nil, "a retitled item keeps its cached article")
    report.expectTrue(try await database.article(itemID: items[1].id) == nil, "an item whose content changed loses its cached article")

    // Purge: older than a year, and gone from its feed for as long.
    let twoYearsAgo = now.addingTimeInterval(-730 * Fixtures.day)
    guard case let .added(archive) = try await database.addSource(Fixtures.candidate("archive")) else { return }
    let old = (1...4).map { Fixtures.feedItem(200 + $0, published: twoYearsAgo) }
    let oldIDs = try await database.upsertItems(old, sourceID: archive.id, repoName: nil, now: twoYearsAgo).newIDs
    try await database.putArticle(article, itemID: oldIDs[0], fetched: twoYearsAgo)
    // The feed still lists the last two today.
    _ = try await database.upsertItems(Array(old[2...]), sourceID: archive.id, repoName: nil, now: now)
    try await database.putJudgments([CachedJudgment(textHash: "old", sentenceHash: "s", model: "m", probability: 0.9, at: twoYearsAgo),
                                     CachedJudgment(textHash: "recent", sentenceHash: "s", model: "m", probability: 0.9, at: now)])
    try await database.addTokensSpent(500, onDay: SpendLedger.day(for: twoYearsAgo))

    // A dormant blog: every post is old and the server has answered "not modified" ever since, so nothing re-listed them.
    guard case let .added(dormant) = try await database.addSource(Fixtures.candidate("dormant")) else { return }
    _ = try await database.upsertItems((1...3).map { Fixtures.feedItem(300 + $0, published: twoYearsAgo) }, sourceID: dormant.id, repoName: nil, now: twoYearsAgo)

    let purged = try await database.purge(olderThan: Database.oneYearBefore(now))
    report.expectEqual(purged, PurgeResult(items: 2, judgments: 1), "purge removes old items that left their feed, and old judgments")
    report.expectEqual(try await database.newestItems(in: .source(archive.id), limit: 10).map(\.id), Array(oldIDs[2...]),
                       "old posts a feed still lists are kept (they would return as unread otherwise)")
    report.expectEqual(try await database.itemCount(in: .source(dormant.id)), 3, "and so are the posts of a feed that has not changed in two years")
    report.expectTrue(try await database.article(itemID: oldIDs[0]) == nil, "a purged item's article goes with it")
    report.expectEqual(try await database.judgments(sentenceHash: "s", model: "m", textHashes: ["old", "recent"]), ["recent": 0.9], "recent judgments stay")
    report.expectEqual(try await database.tokensSpent(onDay: SpendLedger.day(for: twoYearsAgo)), 500, "spend days are never purged (the breaker must not be resettable)")
    report.expectEqual(try await database.itemCount(in: .source(sourceID)), 5, "recent items are untouched")
}
