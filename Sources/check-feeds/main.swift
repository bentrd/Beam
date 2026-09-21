import BeamFeeds
import BeamModels
import Foundation

// check-feeds: lane C's checks (there is no XCTest here). Exit code 0 means green.
//   check-feeds             every offline check on inline fixtures and a canned internet, then the live checks
//   check-feeds --offline   skips the live checks
//   check-feeds --catalog   instead fetches every catalog entry for real (slow: paced hosts)

var report = CheckReport("check-feeds")
if CommandLine.arguments.contains("--catalog") {
    await checkCatalogLive(&report)
} else {
    checkDates(&report)
    checkText(&report)
    checkRSS(&report)
    checkAtomAndRDF(&report)
    checkEncodingsAndDamage(&report)
    checkAdapters(&report)
    await checkResolver(&report)
    await checkPacing(&report)
    await checkRefresher(&report)
    checkCatalog(&report)
    await checkLive(&report)
}
exit(report.finish())
