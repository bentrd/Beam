import BeamEngine
import BeamModels
import BeamUI
import Foundation

/// Chooses what the window talks to.
///
/// `-fake YES` selects `FakeBackend` (captured data; no network, key or database) and must keep doing so forever:
/// design reviews and screenshots depend on it. Its companions are `-fakeKey missing|valid|rejected|unreachable`
/// and `-fakeScenario normal|failures|stopped|offline|limit|coldStart|stall`.
///
/// Anything else is the real engine, reading and writing the one database in Application Support.
@MainActor
enum BackendFactory {
    static func make() throws -> BeamBackend {
        guard !UserDefaults.standard.bool(forKey: "fake") else {
            return try FakeBackend(options: FakeOptions(defaults: .standard))
        }
        return try Engine()
    }
}
