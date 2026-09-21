import BeamJev
import BeamModels
import Foundation

func checkKeyProvider(_ report: inout CheckReport) {
    report.section("Key provider")
    // A service name of its own: the real "dev.beam.app" item is never read, replaced or removed by this check.
    let service = "dev.beam.check-jev.\(ProcessInfo.processInfo.processIdentifier)"
    report.expectEqual(KeyProvider.keychainService, "dev.beam.app", "the app's Keychain service is dev.beam.app")

    report.expectEqual(KeyProvider(service: service, environment: ["BEAM_KEY": "beam", "TYPESAFE_API_KEY": "typesafe"]).key(), "beam", "BEAM_KEY comes before TYPESAFE_API_KEY")
    report.expectEqual(KeyProvider(service: service, environment: ["BEAM_KEY": "", "TYPESAFE_API_KEY": "typesafe"]).key(), "typesafe", "an empty BEAM_KEY falls through to TYPESAFE_API_KEY")
    report.expect(KeyProvider(service: service, environment: [:]).key() == nil, "no Keychain item and no environment: no key")

    let provider = KeyProvider(service: service, environment: ["BEAM_KEY": "beam"])
    do {
        try provider.set("  not-a-real-key \n")
    } catch {
        report.skip("Keychain set, read, remove", because: "the login Keychain is not available here: \(error.localizedDescription)")
        return
    }
    report.expectEqual(provider.key(), "not-a-real-key", "set trims and takes effect at once")
    report.expectEqual(KeyProvider(service: service, environment: ["BEAM_KEY": "beam"]).key(), "not-a-real-key", "the Keychain comes before the environment, and survives the provider")
    do {
        try provider.set("second")
        report.expectEqual(KeyProvider(service: service, environment: [:]).key(), "second", "set replaces the stored key")
        try provider.set("")
        report.expect(KeyProvider(service: service, environment: [:]).key() == nil, "setting an empty key removes it")
        report.expectEqual(provider.key(), "beam", "after removal a development build falls back to its environment")
        try provider.remove()
        report.expect(true, "removing twice is not an error")
    } catch {
        report.expect(false, "Keychain set and remove succeed", detail: error.localizedDescription)
        try? provider.remove()
    }
}
