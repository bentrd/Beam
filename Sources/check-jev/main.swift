import BeamJev
import BeamModels
import Foundation

// Lane A's check: exit code 0 means green. Offline sections always run; the live section needs
// BEAM_KEY or TYPESAFE_API_KEY and is skipped with `--offline`. The key is never printed.

var report = CheckReport("check-jev")

checkFrames(&report)
checkCleaning(&report)
checkUnjudgeable(&report)
await checkValidation(&report)
await checkClient(&report)
await checkLimiter(&report)
await checkJudgeLimit(&report)
await checkBreaker(&report)
await checkMidnight(&report)
checkKeyProvider(&report)

if CheckEnvironment.isOffline {
    report.skip("live checks", because: "--offline")
} else if let key = CheckEnvironment.key {
    await checkLive(&report, key: key)
} else {
    report.skip("live checks", because: "no BEAM_KEY or TYPESAFE_API_KEY in the environment")
}

exit(report.finish())
