import BeamModels
import BeamUI
import Foundation

/// Chooses what the window talks to.
///
/// `-fake YES` selects `FakeBackend` (captured data; no network, key or database) and must keep doing so forever:
/// design reviews and screenshots depend on it. Its companions are `-fakeKey missing|valid|rejected|unreachable`
/// and `-fakeScenario normal|failures|stopped|offline|limit|coldStart|stall`.
///
/// `BeamEngine` does not conform to `BeamBackend` yet, so for now every launch gets the fake backend, flag or no flag.
/// The engine branch belongs here: `UserDefaults.standard.bool(forKey: "fake")` false means the engine.
@MainActor
enum BackendFactory {
    static func make() throws -> BeamBackend {
        try FakeBackend(options: FakeOptions(defaults: .standard))
    }
}
