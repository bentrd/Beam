import BeamModels
import Foundation

// check-extract: lane D's gate. `check-extract` runs everything (fixtures offline, then Hacker News live);
// `check-extract --offline` skips the network; `check-extract probe <url-or-file>… [--dump]` prints what the
// reader would get for a page. Exit code 0 means green.

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.first == "probe" { exit(await Probe.run(Array(arguments.dropFirst()))) }

var report = CheckReport("extract")
DecoderChecks.run(&report)
PassageChecks.run(&report)
FixtureChecks.run(&report)
await LoaderChecks.run(&report)
await LiveCheck.run(&report)
exit(report.finish())
