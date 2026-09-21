import BeamModels
import BeamStore
import Foundation

func checkJudgments(_ report: inout CheckReport) async throws {
    let database = try Database.inMemory()
    let sentence = Hashing.sha256("This item is about: \"on-device ML\"")
    let otherSentence = Hashing.sha256("This item is about: \"rust\"")
    let model = "jev-1.13.0"

    let hashes = (0..<300).map { Hashing.sha256("text \($0)") }
    let batch = hashes.enumerated().map { CachedJudgment(textHash: $1, sentenceHash: sentence, model: model, probability: Double($0) / 299, at: Fixtures.now) }
    try await database.putJudgments(batch)
    try await database.putJudgments([CachedJudgment(textHash: hashes[0], sentenceHash: otherSentence, model: model, probability: 0.8)])

    let fetched = try await database.judgments(sentenceHash: sentence, model: model, textHashes: hashes + [Hashing.sha256("never judged")])
    report.expectEqual(fetched.count, 300, "300 judgments round-trip through one query")
    report.expect(batch.allSatisfy { fetched[$0.textHash] == $0.probability }, "every probability comes back exactly")
    report.expect(fetched[Hashing.sha256("never judged")] == nil, "a text never judged is absent, not zero")
    report.expectTrue(try await database.judgments(sentenceHash: sentence, model: "jev-2", textHashes: hashes).isEmpty, "another model's cache is separate")
    report.expectEqual(try await database.judgments(sentenceHash: otherSentence, model: model, textHashes: hashes), [hashes[0]: 0.8], "sentences do not leak into each other")
    report.expectTrue(try await database.judgments(sentenceHash: sentence, model: model, textHashes: []).isEmpty, "no hashes, no query")

    try await database.putJudgments([CachedJudgment(textHash: hashes[5], sentenceHash: sentence, model: model, probability: 0.61)])
    report.expectEqual(try await database.judgments(sentenceHash: sentence, model: model, textHashes: [hashes[5]]), [hashes[5]: 0.61], "the same key again overwrites")

    for bad in [1.5, -0.1, Double.nan, Double.infinity] {
        let refused = await failure {
            try await database.putJudgments([CachedJudgment(textHash: "fine", sentenceHash: sentence, model: model, probability: 0.5),
                                             CachedJudgment(textHash: "bad", sentenceHash: sentence, model: model, probability: bad)])
        }
        report.expect(refused != nil, "a probability of \(bad) is refused")
    }
    report.expectTrue(try await database.judgments(sentenceHash: sentence, model: model, textHashes: ["fine", "bad"]).isEmpty, "and its whole batch with it")

    // Stale after edit: the item's new hash reaches nothing until it is judged again.
    guard case let .added(source) = try await database.addSource(Fixtures.candidate("edited")) else { return }
    let id = try await database.upsertItems([Fixtures.feedItem(1, title: "MLX gets faster")], sourceID: source.id, repoName: nil, now: Fixtures.now).newIDs[0]
    guard let original = try await database.item(id: id) else { return }
    try await database.putJudgments([CachedJudgment(textHash: original.textHash, sentenceHash: sentence, model: model, probability: 0.92)])
    report.expectEqual(try await database.judgments(sentenceHash: sentence, model: model, textHashes: [original.textHash]), [original.textHash: 0.92], "a judged item is found by its text hash")

    let edit = try await database.upsertItems([Fixtures.feedItem(1, title: "MLX gets faster on M5")], sourceID: source.id, repoName: nil, now: Fixtures.now)
    guard let edited = try await database.item(id: id) else { return }
    report.expectEqual(edit.editedIDs, [id], "the edit is reported, so the engine knows to judge it again")
    report.expectTrue(try await database.judgments(sentenceHash: sentence, model: model, textHashes: [edited.textHash]).isEmpty, "after the edit the item is 'not checked': its new hash reaches no judgment")
    try await database.putJudgments([CachedJudgment(textHash: edited.textHash, sentenceHash: sentence, model: model, probability: 0.95)])
    report.expectEqual(try await database.judgments(sentenceHash: sentence, model: model, textHashes: [edited.textHash]), [edited.textHash: 0.95], "judged again, it is found again")
}
