import BeamModels
import BeamStore
import Foundation

func checkUndo(_ report: inout CheckReport, in folder: TemporaryFolder) async throws {
    let file = folder.file("undo.sqlite")
    let database = try Database(fileURL: file)
    let now = Fixtures.now
    let sentence = Hashing.sha256("a pinned sentence")
    let model = "jev-1.13.0"

    var sources: [Source] = []
    for name in ["kept", "removed", "last"] {
        if case let .added(source) = try await database.addSource(Fixtures.candidate(name)) { sources.append(source) }
    }
    _ = try await database.upsertItems((1...3).map { Fixtures.feedItem($0) }, sourceID: sources[0].id, repoName: nil, now: now)
    let ids = try await database.upsertItems((11...16).map { Fixtures.feedItem($0) }, sourceID: sources[1].id, repoName: nil, now: now).newIDs
    try await database.markOpened(itemID: ids[0], at: now)
    try await database.setRead(true, itemIDs: [ids[1]])
    let article = ArticleContent.ready(passages: [Passage(kind: .heading, text: "Intro"), Passage(kind: .paragraph, text: "Body", section: "Intro")], images: 2, tables: 1)
    try await database.putArticle(article, itemID: ids[0], fetched: now)
    let itemsBefore = try await database.newestItems(in: .source(sources[1].id), limit: 10)
    try await database.putJudgments(itemsBefore.map { CachedJudgment(textHash: $0.textHash, sentenceHash: sentence, model: model, probability: 0.7, at: now) })
    let countsBefore = try await database.unreadCounts()

    // Remove Source hides it everywhere.
    let removed = try await database.removeSource(id: sources[1].id, at: now)
    report.expectEqual(removed?.id, sources[1].id, "removeSource returns the source as it was")
    report.expectEqual(try await database.sources().map(\.title), ["kept", "last"], "the sidebar no longer lists it")
    report.expectEqual(try await database.sources().map(\.position), [0, 1], "positions close up")
    report.expectTrue(try await database.newestItems(limit: 100).allSatisfy { $0.sourceID != sources[1].id }, "All Items no longer lists its items")
    report.expectTrue(try await database.newestItems(in: .source(sources[1].id), limit: 100).isEmpty, "nor does its own scope")
    report.expectEqual(try await database.itemCount(), 3, "nor are they counted")
    report.expectEqual(try await database.unreadCounts(), UnreadCounts(total: 3, bySource: [sources[0].id: 3]), "nor badged")
    report.expectTrue(try await database.source(id: sources[1].id) == nil, "source(id:) does not find it")
    report.expectTrue(try await database.removeSource(id: sources[1].id) == nil, "removing it twice is a no-op")

    // Undo Remove Source.
    let restored = try await database.restoreSource(id: sources[1].id)
    report.expectEqual(restored, sources[1], "Undo returns the source exactly as it was, position included")
    report.expectEqual(try await database.sources().map(\.title), ["kept", "removed", "last"], "back in its place in the sidebar")
    report.expectEqual(try await database.newestItems(in: .source(sources[1].id), limit: 10), itemsBefore, "with its items, read states and opened dates")
    report.expectEqual(try await database.unreadCounts(), countsBefore, "and its unread count")
    report.expectEqual(try await database.article(itemID: ids[0])?.content, article, "and its cached article")
    let judged = try await database.judgments(sentenceHash: sentence, model: model, textHashes: itemsBefore.map(\.textHash))
    report.expectEqual(judged.count, itemsBefore.count, "and its judgments: the list repaints without a request")
    report.expectEqual(try await database.restoreSource(id: sources[1].id), sources[1], "restoring a live source changes nothing")

    // Adding the same feed back is the other way to undo.
    _ = try await database.removeSource(id: sources[1].id, at: now)
    var readded: Source?
    if case let .added(source) = try await database.addSource(Fixtures.candidate("removed")) { readded = source }
    report.expectEqual(readded?.id, sources[1].id, "adding a feed removed this session revives it")
    report.expectEqual(try await database.newestItems(in: .source(sources[1].id), limit: 10).filter(\.read).count, 2, "read states included")

    // Undo lasts until Beam quits.
    _ = try await database.removeSource(id: sources[1].id, at: now)
    guard case let .pinned(pin) = try await database.addPin(sentence: "gone tomorrow", at: now) else { return }
    _ = try await database.removePin(id: pin.id, at: now)
    try await database.close()

    let nextLaunch = try Database(fileURL: file)
    let tooLate = await failure { _ = try await nextLaunch.restoreSource(id: sources[1].id) }
    report.expectEqual(tooLate, .notFound("source \(sources[1].id)"), "after a relaunch the removal is permanent")
    let pinTooLate = await failure { _ = try await nextLaunch.restorePin(id: pin.id) }
    report.expectEqual(pinTooLate, .notFound("pin \(pin.id)"), "for pins too")
    report.expectTrue(try await nextLaunch.item(id: ids[0]) == nil, "its items are really gone")
    report.expectEqual(try RawSQLite.strings("SELECT COUNT(*) FROM item", at: file), ["3"], "nothing of it is left in the file")
    try await nextLaunch.close()
}
