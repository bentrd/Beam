import BeamModels
import BeamStore
import Foundation

func checkSources(_ report: inout CheckReport) async throws {
    let database = try Database.inMemory()
    var added: [Source] = []
    for name in ["alpha", "bravo", "charlie", "delta"] {
        if case let .added(source) = try await database.addSource(Fixtures.candidate(name, kind: name == "bravo" ? .githubReleases : .feed)) {
            added.append(source)
        }
    }
    report.expectEqual(added.map(\.position), [0, 1, 2, 3], "new sources append in order")
    report.expectEqual(added[1].kind, .githubReleases, "the kind round-trips")
    report.expectEqual(added[0].siteURL, Fixtures.url("https://alpha.example/"), "the site URL round-trips")

    var isDuplicate = false
    if case .alreadyAdded = try await database.addSource(Fixtures.candidate("alpha")) { isDuplicate = true }
    report.expect(isDuplicate, "the same feed URL twice is 'already added'")
    report.expectEqual(try await database.source(feedURL: added[2].feedURL)?.id, added[2].id, "a source is found by feed URL")

    try await database.moveSource(id: added[3].id, by: -2)
    report.expectEqual(try await database.sources().map(\.title), ["alpha", "delta", "bravo", "charlie"], "move up by two")
    try await database.moveSource(id: added[0].id, by: 99)
    report.expectEqual(try await database.sources().map(\.title), ["delta", "bravo", "charlie", "alpha"], "a move stops at the end")
    report.expectEqual(try await database.sources().map(\.position), [0, 1, 2, 3], "positions stay 0..<n")

    let id = added[0].id
    let firstFailure = Fixtures.now
    try await database.recordFetchFailure(sourceID: id, error: "HTTP 503", at: firstFailure)
    try await database.recordFetchFailure(sourceID: id, error: "timed out", at: firstFailure.addingTimeInterval(1_800))
    let failing = try await database.source(id: id)
    report.expectEqual(failing?.failingSince, firstFailure, "failing_since is the first failure of the run")
    report.expectEqual(failing?.lastError, "timed out", "last_error is the latest failure")
    report.expect(failing?.lastFetch == nil, "a failure does not count as a fetch")

    let recovered = firstFailure.addingTimeInterval(3_600)
    try await database.recordFetchSuccess(sourceID: id, at: recovered)
    let healthy = try await database.source(id: id)
    report.expect(healthy?.failingSince == nil && healthy?.lastError == nil, "a success clears the failure")
    report.expectEqual(healthy?.lastFetch, recovered, "last_fetch is the success time, bit for bit")

    try await database.recordFetchFailure(sourceID: id, error: "HTTP 500", at: recovered.addingTimeInterval(60))
    report.expectEqual(try await database.source(id: id)?.failingSince, recovered.addingTimeInterval(60), "a new run of failures restarts failing_since")

    let unknown = await failure { try await database.recordFetchSuccess(sourceID: 9_999) }
    report.expectEqual(unknown, .notFound("source 9999"), "recording a fetch for an unknown source is an error, not a silent no-op")
}
