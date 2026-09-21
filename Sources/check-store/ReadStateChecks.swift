import BeamModels
import BeamStore
import Foundation

func checkReadState(_ report: inout CheckReport) async throws {
    let database = try Database.inMemory()
    guard case let .added(first) = try await database.addSource(Fixtures.candidate("first")),
          case let .added(second) = try await database.addSource(Fixtures.candidate("second")),
          case let .added(empty) = try await database.addSource(Fixtures.candidate("empty")) else { return }
    let now = Fixtures.now
    let firstIDs = try await database.upsertItems((1...6).map { Fixtures.feedItem($0) }, sourceID: first.id, repoName: nil, now: now).newIDs
    let secondIDs = try await database.upsertItems((7...10).map { Fixtures.feedItem($0) }, sourceID: second.id, repoName: nil, now: now).newIDs

    report.expectEqual(try await database.unreadCounts(), UnreadCounts(total: 10, bySource: [first.id: 6, second.id: 4]), "everything starts unread")
    report.expectTrue(try await database.unreadCounts().bySource[empty.id] == nil, "a source with nothing unread has no count, as it has no badge")

    let openedAt = now.addingTimeInterval(90)
    try await database.markOpened(itemID: firstIDs[0], at: openedAt)
    let opened = try await database.item(id: firstIDs[0])
    report.expect(opened?.read == true && opened?.opened == openedAt, "opening marks read and records when")
    report.expectEqual(try await database.unreadCounts().bySource[first.id], 5, "the source's count drops by one")

    report.expectEqual(Set(try await database.setRead(true, itemIDs: [firstIDs[0], firstIDs[1], firstIDs[2]])), [firstIDs[1], firstIDs[2]],
                       "setRead returns only the items whose state changed")
    report.expectEqual(try await database.setRead(false, itemIDs: [firstIDs[0]]), [firstIDs[0]], "Mark as Unread")
    let unreadAgain = try await database.item(id: firstIDs[0])
    report.expect(unreadAgain?.read == false && unreadAgain?.opened == openedAt, "marking unread keeps the last-opened time")
    report.expectTrue(try await database.setRead(true, itemIDs: []).isEmpty, "no ids, no work")
    report.expectEqual(try await database.unreadCounts(), UnreadCounts(total: 8, bySource: [first.id: 4, second.id: 4]), "counts follow")

    let hidden = try await database.newestItems(in: .source(first.id), limit: 10, unreadOnly: true)
    report.expectEqual(Set(hidden.map(\.id)), Set(firstIDs).subtracting([firstIDs[1], firstIDs[2]]), "Hide Read Items lists only unread rows")

    // Mark All as Read, per scope, with Undo.
    let beforeSourceSweep = try await database.unreadCounts()
    let swept = try await database.markAllRead(in: .source(first.id))
    report.expectEqual(Set(swept), Set(firstIDs).subtracting([firstIDs[1], firstIDs[2]]), "Mark All as Read returns exactly the rows it changed")
    report.expectEqual(try await database.unreadCounts(), UnreadCounts(total: 4, bySource: [second.id: 4]), "only that source was swept")
    try await database.setRead(false, itemIDs: swept)
    report.expectEqual(try await database.unreadCounts(), beforeSourceSweep, "Undo Mark All as Read restores the exact previous state")
    report.expectTrue(try await database.item(id: firstIDs[1])?.read == true, "rows that were already read stay read after the undo")

    let sweptAll = try await database.markAllRead(in: .all)
    report.expectEqual(sweptAll.count, 8, "Mark All as Read in All Items covers every source")
    report.expectEqual(try await database.unreadCounts(), UnreadCounts(), "and leaves nothing unread")
    report.expectTrue(try await database.markAllRead(in: .all).isEmpty, "a second sweep has nothing to undo")
    try await database.setRead(false, itemIDs: sweptAll)
    report.expectEqual(try await database.unreadCounts().total, 8, "undone")

    _ = try await database.removeSource(id: second.id)
    report.expectEqual(try await database.unreadCounts(), UnreadCounts(total: 4, bySource: [first.id: 4]), "a removed source stops counting")
    report.expectTrue(try await database.markAllRead(in: .source(second.id)).isEmpty, "and cannot be swept")
    report.expectTrue(!(try await database.markAllRead(in: .all)).contains(where: secondIDs.contains), "nor touched by a sweep of All Items")

    let missing = await failure { try await database.markOpened(itemID: 424_242) }
    report.expectEqual(missing, .notFound("item 424242"), "opening an unknown item is an error")
}
