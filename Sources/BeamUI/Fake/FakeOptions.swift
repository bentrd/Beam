import BeamModels
import Foundation

/// A situation the fake backend can stage, so every foot and empty sentence of DESIGN.md section 6 can be reviewed
/// without a network, a key or bad luck. Chosen at launch with `-fakeScenario <name>`.
public enum FakeScenario: String, Sendable, CaseIterable {
    /// Everything works.
    case normal
    /// About one judgment in seven fails: "31 not checked. Retry" in the list, "61 of 84 checked. Retry" in the reader.
    case failures
    /// Ten failures in a row stop the run: "Stopped after repeated errors. Retry".
    case stopped
    /// Only sentences already checked repaint: "Offline. Showing what was already checked."
    case offline
    /// The spend breaker trips a third of the way through a run: "Daily limit reached. Resets at midnight."
    case limit
    /// No items for the first seconds of the session: "Getting your sources".
    case coldStart
    /// A run pauses for four seconds half way, which is the only time a running count may show: "75 of 150 checked".
    case stall
}

/// How the fake backend starts. The defaults are what `-fake YES` alone gives: a working key and no staged trouble.
public struct FakeOptions: Sendable {
    public var keyStatus: KeyStatus
    public var scenario: FakeScenario

    public init(keyStatus: KeyStatus = .valid, scenario: FakeScenario = .normal) {
        self.keyStatus = keyStatus; self.scenario = scenario
    }

    /// Reads `-fakeKey missing|valid|rejected|unreachable` and `-fakeScenario <name>` from the argument domain.
    /// Unknown values fall back to the defaults rather than failing the launch: these flags only serve reviews.
    public init(defaults: UserDefaults) {
        self.init()
        switch defaults.string(forKey: "fakeKey") {
        case "missing": keyStatus = .missing
        case "rejected": keyStatus = .rejected
        case "unreachable": keyStatus = .unreachable
        default: keyStatus = .valid
        }
        if let name = defaults.string(forKey: "fakeScenario"), let staged = FakeScenario(rawValue: name) { scenario = staged }
    }
}
