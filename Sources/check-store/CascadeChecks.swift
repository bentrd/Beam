import BeamModels
import BeamStore
import Foundation

func checkCascade(_ report: inout CheckReport) async throws {
    let database = try Database.inMemory()
    guard case let .added(doomed) = try await database.addSource(Fixtures.candidate("doomed")),
          case let .added(survivor) = try await database.addSource(Fixtures.candidate("survivor")) else { return }
    let now = Fixtures.now
    let sentence = "s"
    let model = "m"

    // Item 1 exists in both sources with the same text, so its judgment is shared.
    let doomedIDs = try await database.upsertItems((1...4).map { Fixtures.feedItem($0) }, sourceID: doomed.id, repoName: nil, now: now).newIDs
    let survivorIDs = try await database.upsertItems([Fixtures.feedItem(1), Fixtures.feedItem(9)], sourceID: survivor.id, repoName: nil, now: now).newIDs
    for id in doomedIDs + survivorIDs { try await database.putArticle(.unavailable(reason: "paywall"), itemID: id, fetched: now) }
    let doomedItems = try await database.newestItems(in: .source(doomed.id), limit: 10)
    let survivorItems = try await database.newestItems(in: .source(survivor.id), limit: 10)
    let hashes = Set((doomedItems + survivorItems).map(\.textHash))
    try await database.putJudgments(hashes.map { CachedJudgment(textHash: $0, sentenceHash: sentence, model: model, probability: 0.5, at: now) })
    try await database.putJudgments([CachedJudgment(textHash: Hashing.sha256("a passage"), sentenceHash: sentence, model: model, probability: 0.8, at: now)])
    report.expectEqual(hashes.count, 5, "fixture: five distinct texts, one shared between the sources")

    _ = try await database.removeSource(id: doomed.id, at: now)
    try await database.purgeRemoved()

    var itemsLeft = 0
    var articlesLeft = 0
    for id in doomedIDs {
        if try await database.item(id: id) != nil { itemsLeft += 1 }
        if try await database.article(itemID: id) != nil { articlesLeft += 1 }
    }
    report.expectEqual(itemsLeft, 0, "deleting a source deletes its items")
    report.expectEqual(articlesLeft, 0, "and their articles")
    report.expectEqual(try await database.itemCount(), 2, "the other source's items are untouched")
    report.expectTrue(try await database.article(itemID: survivorIDs[0]) != nil, "with their articles")

    let left = try await database.judgments(sentenceHash: sentence, model: model, textHashes: Array(hashes) + [Hashing.sha256("a passage")])
    let expected = Set(survivorItems.map(\.textHash)).union([Hashing.sha256("a passage")])
    report.expectEqual(Set(left.keys), expected, "judgments only the deleted items could reach are dropped; shared and passage judgments stay")

    let gone = await failure { _ = try await database.restoreSource(id: doomed.id) }
    report.expectEqual(gone, .notFound("source \(doomed.id)"), "a purged source cannot be restored")
}
