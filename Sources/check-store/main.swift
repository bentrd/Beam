import BeamModels
import Foundation

// check-store: exit code 0 means lane B is green. Offline, no key, a few seconds.
// Each area runs against its own database so one failure cannot cascade into the next.

var report = CheckReport("store")
let folder = try TemporaryFolder()

await run("Migrations, configuration, reopening", &report) { try await checkMigrations(&$0, in: folder) }
await run("Sources", &report) { try await checkSources(&$0) }
await run("Items: upsert, edit, dedupe", &report) { try await checkItems(&$0) }
await run("Items: transactions and purge", &report) { try await checkItemLifecycle(&$0) }
await run("Read state and unread counts", &report) { try await checkReadState(&$0) }
await run("Pins", &report) { try await checkPins(&$0) }
await run("Judgment cache", &report) { try await checkJudgments(&$0) }
await run("Undo: remove and restore", &report) { try await checkUndo(&$0, in: folder) }
await run("Cascade", &report) { try await checkCascade(&$0) }
await run("Articles, spend, meta", &report) { try await checkSmallStores(&$0) }
await run("Concurrency", &report) { try await checkConcurrency(&$0, in: folder) }
await run("Scale: 50,000 items", &report) { try await checkScale(&$0, in: folder) }

folder.remove()
exit(report.finish())
