import BeamModels
import BeamStore
import Foundation

func checkItems(_ report: inout CheckReport) async throws {
    let database = try Database.inMemory()
    guard case let .added(source) = try await database.addSource(Fixtures.candidate("blog")) else { return }
    let now = Fixtures.now

    let feed = [Fixtures.feedItem(1, content: "<p>Full text</p>"), Fixtures.feedItem(2, snippet: ""), Fixtures.feedItem(3, title: "NUL \u{0} inside")]
    let first = try await database.upsertItems(feed, sourceID: source.id, repoName: nil, now: now)
    report.expectEqual(first.newIDs.count, 3, "three new items")
    report.expect(first.editedIDs.isEmpty, "nothing edited on first sight")

    let listed = try await database.newestItems(in: .source(source.id), limit: 10)
    report.expectEqual(listed.map(\.id), first.newIDs, "new IDs come back in feed order, which is list order")
    report.expectEqual(listed.map(\.title), feed.map(\.title), "titles round-trip, an embedded NUL included")
    report.expectEqual(listed[1].snippet, "", "an empty snippet is stored as empty text, not NULL")
    report.expectEqual(listed.map(\.published), feed.map(\.published), "dates round-trip bit for bit")
    report.expect(listed.allSatisfy { $0.content == nil }, "list queries leave content out")
    report.expectEqual(try await database.item(id: first.newIDs[0])?.content, "<p>Full text</p>", "item(id:) carries the feed content")
    report.expect(listed.allSatisfy { !$0.read && $0.opened == nil && $0.fetched == now }, "new items are unread, unopened, fetched now")

    let again = try await database.upsertItems(feed, sourceID: source.id, repoName: nil, now: now.addingTimeInterval(1_800))
    report.expectEqual(again, UpsertResult(), "the same feed again: nothing new, nothing edited")

    // An edit keeps the row and its read state, and changes the text hash.
    let target = first.newIDs[0]
    try await database.markOpened(itemID: target, at: now)
    let before = try await database.item(id: target)
    var edited = feed
    edited[0].title = "Title 1, corrected"
    let afterEdit = try await database.upsertItems(edited, sourceID: source.id, repoName: nil, now: now.addingTimeInterval(3_600))
    report.expectEqual(afterEdit, UpsertResult(editedIDs: [target]), "an edited title reports exactly that item as edited")
    let after = try await database.item(id: target)
    report.expectEqual(after?.title, "Title 1, corrected", "the row carries the new title")
    report.expect(after?.read == true && after?.opened == before?.opened && after?.fetched == before?.fetched, "read, opened and fetched survive an edit")
    report.expect(before?.textHash != after?.textHash, "the text hash changed")
    report.expectEqual(try await database.itemCount(in: .source(source.id)), 3, "no row was added by the edit")

    edited[1].snippet = "A snippet arrives later."
    report.expectEqual(try await database.upsertItems(edited, sourceID: source.id, repoName: nil, now: now).editedIDs, [first.newIDs[1]], "an edited snippet counts as an edit too")

    // Dedupe by GUID, then by link.
    var regenerated = Fixtures.feedItem(2, snippet: "A snippet arrives later.", guid: "tag:blog,2026:regenerated")
    let byLink = try await database.upsertItems([regenerated], sourceID: source.id, repoName: nil, now: now)
    report.expectEqual(byLink, UpsertResult(), "a new GUID with a known link is the same item")
    report.expectEqual(try await database.item(id: first.newIDs[1])?.guid, "tag:blog,2026:regenerated", "and the row adopts the new GUID")
    regenerated.url = Fixtures.url("https://posts.example/moved")
    report.expectEqual(try await database.upsertItems([regenerated], sourceID: source.id, repoName: nil, now: now), UpsertResult(), "a known GUID with a new link is the same item")
    report.expectEqual(try await database.item(id: first.newIDs[1])?.url, regenerated.url, "and the row adopts the new link")

    let twins = [Fixtures.feedItem(10, title: "First wins"), Fixtures.feedItem(10, title: "Second loses"),
                 FeedItem(guid: "other-guid", url: Fixtures.url("https://posts.example/10"), title: "Same link", snippet: "")]
    let twinResult = try await database.upsertItems(twins, sourceID: source.id, repoName: nil, now: now)
    report.expectEqual(twinResult.newIDs.count, 1, "a GUID or a link repeated inside one feed is stored once")
    report.expectEqual(try await database.item(id: twinResult.newIDs[0])?.title, "First wins", "and the first occurrence wins")
    report.expectEqual(try await database.upsertItems(twins, sourceID: source.id, repoName: nil, now: now), UpsertResult(), "so repeating that feed reports no edit")

    let anonymous = [FeedItem(guid: "", url: nil, title: "No identity A", snippet: ""), FeedItem(guid: "", url: nil, title: "No identity B", snippet: "")]
    report.expectEqual(try await database.upsertItems(anonymous, sourceID: source.id, repoName: nil, now: now).newIDs.count, 2, "entries without GUID or link stay distinct")

    // A second source may carry the same GUIDs and links.
    guard case let .added(mirror) = try await database.addSource(Fixtures.candidate("mirror")) else { return }
    report.expectEqual(try await database.upsertItems(feed, sourceID: mirror.id, repoName: nil, now: now).newIDs.count, 3, "dedupe is per source")

    // Undated entries share one fetched time; they must still list in the feed's order.
    guard case let .added(undated) = try await database.addSource(Fixtures.candidate("undated")) else { return }
    let bare = (1...4).map { Fixtures.feedItem(100 + $0, published: nil) }
    let bareIDs = try await database.upsertItems(bare, sourceID: undated.id, repoName: nil, now: now).newIDs
    let bareListed = try await database.newestItems(in: .source(undated.id), limit: 10)
    report.expectEqual(bareListed.map(\.title), bare.map(\.title), "undated items list in feed order")
    report.expectEqual(bareListed.map(\.id), bareIDs, "and newIDs matches that order")
    var dated = bare
    dated[0].published = now.addingTimeInterval(-7 * Fixtures.day)
    _ = try await database.upsertItems(dated, sourceID: undated.id, repoName: nil, now: now)
    report.expectEqual(try await database.item(id: bareIDs[0])?.published, dated[0].published, "a date that arrives later is filled in")
    dated[0].published = now
    _ = try await database.upsertItems(dated, sourceID: undated.id, repoName: nil, now: now)
    report.expectEqual(try await database.item(id: bareIDs[0])?.published, now.addingTimeInterval(-7 * Fixtures.day), "but a feed re-dating an entry does not reshuffle the list")

    // Release feeds: the repo name is part of the judged text.
    guard case let .added(releases) = try await database.addSource(Fixtures.candidate("mlx", kind: .githubReleases)) else { return }
    let release = [FeedItem(guid: "v0.30.6", url: Fixtures.url("https://github.com/ml-explore/mlx/releases/tag/v0.30.6"), title: "v0.30.6", snippet: "Faster quantized matmul.")]
    let releaseID = try await database.upsertItems(release, sourceID: releases.id, repoName: "mlx", now: now).newIDs[0]
    let stored = try await database.item(id: releaseID)
    report.expectEqual(stored?.judgedText["title"], "mlx v0.30.6", "a release item is judged as '<repo> <tag>'")
    report.expectEqual(try await database.upsertItems(release, sourceID: releases.id, repoName: "mlx", now: now), UpsertResult(), "and is stable across refreshes")

    let reported = try await database.items(ids: [first.newIDs[2], 987_654, first.newIDs[0]])
    report.expectEqual(reported.map(\.id), [first.newIDs[0], first.newIDs[2]], "items(ids:) loads what a refresh reported, in list order, skipping unknown ids")

    let paged = try await database.newestItems(limit: 2, offset: 1)
    let all = try await database.newestItems(limit: 100)
    report.expectEqual(paged.map(\.id), Array(all.map(\.id)[1...2]), "offset pages further back through the same order")
    report.expect(zip(all, all.dropFirst()).allSatisfy { $0.sortDate >= $1.sortDate }, "All Items is ordered by sort date, newest first")
    report.expectEqual(try await database.itemCount(), all.count, "itemCount matches the list")
}
