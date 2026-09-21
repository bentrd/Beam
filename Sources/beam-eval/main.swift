import BeamModels
import Foundation

// beam-eval: the acceptance suite for PRODUCT.md's "V1 MUST" list. One subcommand per MUST, `all` for every one
// of them, and `--offline` for the parts that need neither the network nor a key. Exit code 0 means green.
//
//   beam-eval all
//   beam-eval search reader --offline
//
// The live parts need a key: `source ~/.zshrc` first. It is never printed.

@MainActor
func runEval() async -> Int32 {
    let arguments = Array(CommandLine.arguments.dropFirst())
    let asked = arguments.filter { !$0.hasPrefix("-") }
    let offline = CheckEnvironment.isOffline
    let key = CheckEnvironment.key

    let checks: [(name: String, run: (inout CheckReport, Bool, String?) async -> Void)] = [
        (ColdStartCheck.name, ColdStartCheck.run),
        (SourcesCheck.name, SourcesCheck.run),
        (SearchCheck.name, SearchCheck.run),
        (PinsCheck.name, PinsCheck.run),
        (ReaderCheck.name, ReaderCheck.run),
        (HonestyCheck.name, HonestyCheck.run),
        (ExtractionCheck.name, ExtractionCheck.run),
        (FramingCheck.name, FramingCheck.run),
    ]

    let wanted = asked.isEmpty || asked == ["all"] ? checks : checks.filter { asked.contains($0.name) }
    guard !wanted.isEmpty else {
        FileHandle.standardError.write(Data("beam-eval: no such check. Try: \(checks.map(\.name).joined(separator: ", ")), all\n".utf8))
        return 2
    }

    var report = CheckReport("eval")
    if key == nil, !offline {
        report.note("no BEAM_KEY or TYPESAFE_API_KEY in the environment: the live checks will be skipped")
    }
    for check in wanted {
        await check.run(&report, offline, key)
    }
    return report.finish()
}

exit(await runEval())
