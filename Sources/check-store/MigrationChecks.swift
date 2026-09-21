import BeamModels
import BeamStore
import Foundation

func checkMigrations(_ report: inout CheckReport, in folder: TemporaryFolder) async throws {
    // A path whose folder does not exist yet: Application Support/Beam on a first launch.
    let file = folder.url.appendingPathComponent("nested/deeper/beam.sqlite")
    let database = try Database(fileURL: file)

    let fresh = try await database.diagnostics()
    report.expectEqual(fresh.schemaVersion, 1, "an empty file migrates to schema 1")
    report.expectEqual(fresh.journalMode, "wal", "journal mode is WAL")
    report.expect(fresh.foreignKeysEnabled, "foreign keys are on")
    report.expectEqual(fresh.busyTimeoutMilliseconds, 5_000, "busy timeout is 5 s")

    let tables = Set(try RawSQLite.strings("SELECT name FROM sqlite_master WHERE type = 'table'", at: file))
    report.expectEqual(tables, ["source", "item", "pin", "judgment", "article", "spend", "meta"], "schema 1 has exactly the seven tables")
    for (table, column) in [("item", "read"), ("item", "repo_name"), ("source", "failing_since"), ("source", "position"), ("pin", "position")] {
        let columns = try RawSQLite.strings("PRAGMA table_info(\(table))", column: 1, at: file)
        report.expect(columns.contains(column), "\(table).\(column) exists")
    }

    guard case let .added(source) = try await database.addSource(Fixtures.candidate("reopen")) else {
        report.expect(false, "a source can be added to a fresh database")
        return
    }
    let ids = try await database.upsertItems((1...3).map { Fixtures.feedItem($0) }, sourceID: source.id, repoName: nil, now: Fixtures.now).newIDs
    try await database.markOpened(itemID: ids[0], at: Fixtures.now)
    try await database.setMeta("model", to: "jev-1.13.0")

    let closeError = await failure { try await database.close() }
    report.expect(closeError == nil, "close() succeeds: every prepared statement was finalized", detail: "\(closeError.map(String.init(describing:)) ?? "")")
    let afterClose = await failure { _ = try await database.sources() }
    report.expectEqual(afterClose, .closed, "a closed database refuses work instead of crashing")

    let reopened = try Database(fileURL: file)
    report.expectEqual(try await reopened.diagnostics().schemaVersion, 1, "reopening keeps schema 1 (no migration runs twice)")
    report.expectEqual(try await reopened.sources().map(\.title), ["reopen"], "the source survived the reopen")
    let items = try await reopened.newestItems(limit: 10)
    report.expectEqual(items.count, 3, "the items survived the reopen")
    report.expectEqual(items.filter(\.read).map(\.id), [ids[0]], "read state survived the reopen")
    report.expectEqual(try await reopened.meta("model"), "jev-1.13.0", "meta survived the reopen")
    try await reopened.close()

    let garbage = folder.file("garbage.sqlite")
    try Data("this is not a database, it only has the right name".utf8).write(to: garbage)
    var rejection: StoreError?
    do { _ = try Database(fileURL: garbage) } catch let error as StoreError { rejection = error }
    report.expect(rejection != nil, "a file that is not a database is an error, not a crash", detail: "\(rejection.map(String.init(describing:)) ?? "opened")")
    report.expectEqual(try Data(contentsOf: garbage).count, 50, "and it is left as it was")

    let future = folder.file("future.sqlite")
    try RawSQLite.execute("PRAGMA user_version = 99; CREATE TABLE from_the_future(x);", at: future)
    var refusal: StoreError?
    do { _ = try Database(fileURL: future) } catch let error as StoreError { refusal = error }
    report.expectEqual(refusal, .newerSchema(found: 99, supported: 1), "a file from a newer Beam is refused")
    report.expectEqual(try RawSQLite.strings("PRAGMA user_version", at: future), ["99"], "and left untouched")
}
