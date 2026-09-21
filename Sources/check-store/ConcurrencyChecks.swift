import BeamModels
import BeamStore
import Foundation

/// The engine calls the store from many tasks at once (64 judgments in flight, a refresh, the sidebar).
func checkConcurrency(_ report: inout CheckReport, in folder: TemporaryFolder) async throws {
    let file = folder.file("concurrent.sqlite")
    let database = try Database(fileURL: file)
    guard case let .added(source) = try await database.addSource(Fixtures.candidate("busy")) else { return }
    let sourceID = source.id
    let sentence = "sentence"
    let model = "model"

    // 200 tasks, each a judgment batch, a spend increment, a refresh and two reads.
    let errors = await withTaskGroup(of: String?.self, returning: [String].self) { group in
        for task in 0..<200 {
            group.addTask {
                do {
                    let batch = (0..<10).map { CachedJudgment(textHash: "text-\(task)-\($0)", sentenceHash: sentence, model: model, probability: 0.5) }
                    try await database.putJudgments(batch)
                    try await database.addTokensSpent(100, onDay: "2026-09-21")
                    _ = try await database.upsertItems([Fixtures.feedItem(task)], sourceID: sourceID, repoName: nil, now: Fixtures.now)
                    _ = try await database.newestItems(limit: 50)
                    _ = try await database.unreadCounts()
                    return nil
                } catch {
                    return "\(error)"
                }
            }
        }
        var failures: [String] = []
        for await failure in group { if let failure { failures.append(failure) } }
        return failures
    }
    report.expect(errors.isEmpty, "200 concurrent tasks complete without an error", detail: errors.first ?? "")
    report.expectEqual(try await database.tokensSpent(onDay: "2026-09-21"), 20_000, "no spend increment was lost")
    report.expectEqual(try await database.itemCount(), 200, "every refresh landed exactly once")
    let hashes = (0..<200).flatMap { task in (0..<10).map { "text-\(task)-\($0)" } }
    report.expectEqual(try await database.judgments(sentenceHash: sentence, model: model, textHashes: hashes).count, 2_000, "all 2,000 judgments are stored")

    // A second connection to the same file (the sqlite3 shell, a second Beam): WAL and the busy timeout keep both working.
    let other = try Database(fileURL: file)
    guard case let .added(elsewhere) = try await other.addSource(Fixtures.candidate("elsewhere")) else { return }
    let otherID = elsewhere.id
    let contention = await withTaskGroup(of: String?.self, returning: [String].self) { group in
        for round in 0..<40 {
            group.addTask {
                do {
                    let target = round.isMultiple(of: 2) ? (database, sourceID) : (other, otherID)
                    let feed = (0..<25).map { Fixtures.feedItem(10_000 + round * 25 + $0) }
                    _ = try await target.0.upsertItems(feed, sourceID: target.1, repoName: nil, now: Fixtures.now)
                    _ = try await target.0.newestItems(limit: 100)
                    return nil
                } catch {
                    return "\(error)"
                }
            }
        }
        var failures: [String] = []
        for await failure in group { if let failure { failures.append(failure) } }
        return failures
    }
    report.expect(contention.isEmpty, "two connections write the same file without SQLITE_BUSY surfacing", detail: contention.first ?? "")
    report.expectEqual(try await other.itemCount(), 200 + 40 * 25, "and each sees the other's commits")

    let statements = try await database.diagnostics().cachedStatements
    report.expect(statements < 40, "the statement cache is bounded by the set of operations, not by the traffic", detail: "\(statements) statements")
    try await database.close()
    try await other.close()
}
