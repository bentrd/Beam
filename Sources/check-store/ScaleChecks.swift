import BeamModels
import BeamStore
import Foundation

/// PRODUCT.md MUST 9 at the store's level: 50,000 items, list queries under 50 ms, under 250 MB resident.
func checkScale(_ report: inout CheckReport, in folder: TemporaryFolder) async throws {
    let file = folder.file("scale.sqlite")
    let sourceCount = 50
    let itemsPerSource = 1_000
    let limitMilliseconds = 50.0

    var database = try Database(fileURL: file)
    var sourceIDs: [Int64] = []
    for number in 0..<sourceCount {
        if case let .added(source) = try await database.addSource(Fixtures.candidate("source\(number)")) { sourceIDs.append(source.id) }
    }

    let ids = sourceIDs
    var inserted = 0
    let insertTime = try await milliseconds {
        inserted = try await database.transaction { database in
            var count = 0
            for (index, sourceID) in ids.enumerated() {
                // The fixtures' own garbage (50,000 URLs) must not be billed to the store.
                count += try autoreleasepool {
                    let feed = (0..<itemsPerSource).map { Fixtures.syntheticItem(source: index, number: $0, sourceCount: sourceCount) }
                    return try database.upsertItems(feed, sourceID: sourceID, repoName: nil, now: Fixtures.now).newIDs.count
                }
            }
            return count
        }
    }
    report.expectEqual(inserted, sourceCount * itemsPerSource, "50,000 items inserted in one transaction")
    report.note(String(format: "insert: %.0f ms (%.0f items/s), peak resident so far %@", insertTime, Double(inserted) / insertTime * 1_000,
                       Memory.megabytes(Memory.peakResidentBytes)))

    // A fresh connection: cold statement cache, cold page cache, as after a launch.
    try await database.close()
    database = try Database(fileURL: file)
    let reopened = database

    var newest: [Item] = []
    let newestTime = try await slowest(of: 5) { newest = try await reopened.newestItems(limit: 300) }
    report.expectEqual(newest.count, 300, "the newest-300 query returns 300 rows")
    report.expectTrue(zip(newest, newest.dropFirst()).allSatisfy { $0.sortDate >= $1.sortDate }, "in list order")
    report.expect(newestTime < limitMilliseconds, "newest 300 of 50,000 under 50 ms", detail: String(format: "%.1f ms", newestTime))
    report.note(String(format: "newest 300, All Items: %.2f ms (slowest of 5, first run cold)", newestTime))

    let olderTime = try await slowest(of: 5) { _ = try await reopened.newestItems(limit: 1_200, offset: 300) }
    report.note(String(format: "next 1,200 (\"Check 1,200 older\"): %.2f ms", olderTime))

    let scopedTime = try await slowest(of: 5) { _ = try await reopened.newestItems(in: .source(ids[7]), limit: 300) }
    report.expect(scopedTime < limitMilliseconds, "newest 300 of one source under 50 ms", detail: String(format: "%.1f ms", scopedTime))
    report.note(String(format: "newest 300, one source: %.2f ms", scopedTime))

    var counts = UnreadCounts()
    let countTime = try await slowest(of: 5) { counts = try await reopened.unreadCounts() }
    report.expectEqual(counts.total, inserted, "unread counts see all 50,000")
    report.expectEqual(counts.bySource.count, sourceCount, "across all 50 sources")
    report.expect(countTime < limitMilliseconds, "unread counts under 50 ms with everything unread (the worst case)", detail: String(format: "%.1f ms", countTime))
    report.note(String(format: "unread counts, 50,000 unread: %.2f ms", countTime))

    var swept = 0
    let sweepTime = try await milliseconds { swept = try await reopened.markAllRead(in: .source(ids[0])).count }
    report.expectEqual(swept, itemsPerSource, "Mark All as Read returns the 1,000 ids of one source")
    report.note(String(format: "Mark All as Read, one source of 1,000: %.2f ms", sweepTime))

    // The worst case for Hide Read Items: the newest 40,000 are read, so the list has to look past all of them.
    var marked = 0
    let markTime = try await milliseconds {
        for page in 0..<8 {
            let pageIDs = try await reopened.newestItems(limit: 5_000, offset: page * 5_000).map(\.id)
            marked += try await reopened.setRead(true, itemIDs: pageIDs).count
        }
    }
    report.note(String(format: "setRead over the newest 40,000, in pages of 5,000: %.0f ms", markTime))
    var unreadRows: [Item] = []
    let unreadOnlyTime = try await slowest(of: 5) { unreadRows = try await reopened.newestItems(limit: 300, unreadOnly: true) }
    report.expect(unreadRows.count == 300 && unreadRows.allSatisfy { !$0.read }, "Hide Read Items finds 300 unread rows behind 40,000 read ones")
    report.expect(unreadOnlyTime < limitMilliseconds, "and does so under 50 ms", detail: String(format: "%.1f ms", unreadOnlyTime))
    report.note(String(format: "newest 300 unread (Hide Read Items, worst case): %.2f ms", unreadOnlyTime))
    let countAfterTime = try await slowest(of: 5) { counts = try await reopened.unreadCounts() }
    report.expectEqual(counts.total, inserted - swept - marked, "unread counts follow every change")
    report.expect(countAfterTime < limitMilliseconds, "unread counts under 50 ms afterwards", detail: String(format: "%.1f ms", countAfterTime))

    let totalTime = try await slowest(of: 3) { _ = try await reopened.itemCount() }
    report.note(String(format: "item count: %.2f ms", totalTime))

    let refreshTime = try await milliseconds {
        let feed = (0..<30).map { Fixtures.syntheticItem(source: 3, number: $0, sourceCount: sourceCount) }
        _ = try await reopened.upsertItems(feed, sourceID: ids[3], repoName: nil, now: Fixtures.now)
    }
    report.note(String(format: "an unchanged 30-item refresh against 50,000 rows: %.2f ms", refreshTime))

    var purged = PurgeResult()
    let purgeTime = try await milliseconds { purged = try await reopened.purge(olderThan: Fixtures.now.addingTimeInterval(-180 * Fixtures.day)) }
    report.expectEqual(purged.items, 0, "a purge deletes nothing every feed still lists, however old")
    report.note(String(format: "purge pass over 50,000 items, half of them past the cutoff: %.1f ms", purgeTime))

    _ = try await reopened.removeSource(id: ids[49])
    let cascadeTime = try await milliseconds { try await reopened.purgeRemoved() }
    report.expectEqual(try await reopened.itemCount(), inserted - itemsPerSource, "deleting one source for good takes its 1,000 items with it")
    report.note(String(format: "permanent removal of a 1,000-item source (the cascade): %.1f ms", cascadeTime))

    let peak = Memory.peakResidentBytes
    report.expect(peak < 250 * 1_048_576, "peak resident memory under 250 MB", detail: Memory.megabytes(peak))
    report.note("resident now: \(Memory.megabytes(Memory.residentBytes)), peak: \(Memory.megabytes(peak))")

    try await database.close()
    let size = (try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.uint64Value ?? 0
    report.note("database file: \(Memory.megabytes(size))")
}
