import BeamJev
import BeamModels
import Foundation
import Security

func checkKeyProvider(_ report: inout CheckReport) {
    report.section("Key provider")
    // A service name of its own: the real "dev.beam.app" item is never read, replaced or removed by this check.
    let service = "dev.beam.check-jev.\(ProcessInfo.processInfo.processIdentifier)"
    report.expectEqual(KeyProvider.keychainService, "dev.beam.app", "the app's Keychain service is dev.beam.app")

    report.expectEqual(KeyProvider(service: service, environment: ["BEAM_KEY": "beam", "TYPESAFE_API_KEY": "typesafe"]).key(), "beam", "BEAM_KEY comes before TYPESAFE_API_KEY")
    report.expectEqual(KeyProvider(service: service, environment: ["BEAM_KEY": "", "TYPESAFE_API_KEY": "typesafe"]).key(), "typesafe", "an empty BEAM_KEY falls through to TYPESAFE_API_KEY")
    report.expect(KeyProvider(service: service, environment: [:]).key() == nil, "no Keychain item and no environment: no key")
    report.expectEqual(KeyProvider(service: service, environment: ["BEAM_KEY": " \n", "TYPESAFE_API_KEY": " typesafe \n"]).key(), "typesafe", "environment values are trimmed and blank keys fall through")
    checkKeyStorageFailures(&report)

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

private func checkKeyStorageFailures(_ report: inout CheckReport) {
    let blocked = MemoryKeyStorage()
    blocked.failRead = true
    let unreadable = KeyProvider(environment: ["BEAM_KEY": "fallback"], storage: blocked)
    report.expect(unreadable.key() == nil, "denied Keychain access never silently selects an environment account")
    do {
        _ = try unreadable.readKey()
        report.expect(false, "Keychain read errors are visible to the caller")
    } catch let error as KeychainError {
        report.expectEqual(error.status, errSecAuthFailed, "Keychain read errors are visible to the caller")
    } catch {
        report.expect(false, "Keychain read failures retain their system status")
    }
    report.expectEqual(blocked.reads, 1, "a denied Keychain lookup is cached rather than prompting for every item")

    let storage = MemoryKeyStorage(key: "working")
    let provider = KeyProvider(environment: [:], storage: storage)
    report.expectEqual(provider.key(), "working", "a stored credential is read")
    storage.failWrite = true
    do {
        try provider.set("replacement")
        report.expect(false, "failed replacement throws")
    } catch {
        report.expectEqual(provider.key(), "working", "failed replacement keeps the credential in memory")
        report.expectEqual(storage.key, "working", "failed replacement keeps the stored credential")
    }
    storage.failRemove = true
    do {
        try provider.remove()
        report.expect(false, "failed removal throws")
    } catch {
        report.expectEqual(provider.key(), "working", "failed removal keeps the active credential")
    }
    storage.failWrite = false
    do {
        try provider.set(" replacement \n")
        report.expectEqual(provider.key(), "replacement", "a later successful replacement updates the cache")
    } catch { report.expect(false, "a later successful replacement succeeds") }
}

/// Synchronous injectable storage; accessed on the check thread only.
private final class MemoryKeyStorage: KeyStoring, @unchecked Sendable {
    var key: String?
    var failRead = false
    var failWrite = false
    var failRemove = false
    private(set) var reads = 0
    init(key: String? = nil) { self.key = key }
    func read() throws -> String? {
        reads += 1
        if failRead { throw KeychainError(status: errSecAuthFailed) }
        return key
    }
    func write(_ key: String) throws {
        if failWrite { throw KeychainError(status: errSecAuthFailed) }
        self.key = key
    }
    func remove() throws {
        if failRemove { throw KeychainError(status: errSecAuthFailed) }
        key = nil
    }
}

func checkKeyValidation(_ report: inout CheckReport) async {
    report.section("Connection validation")
    let missing = FakeService()
    let judge = Judge(keyProvider: { nil }, spend: SpendMeter(), client: JevClient(transport: missing.transport))
    let noKey = await judge.validate(key: " \n")
    let badFormat = await judge.validate(key: "key with spaces")
    report.expect(noKey == .missing && badFormat == .rejected && missing.requests.isEmpty, "blank and malformed candidates send no requests")

    let service = FakeService(script: [.http(200, body: FakeService.answers(["0.9"]))])
    let client = JevClient(transport: service.transport)
    let valid = await Judge(keyProvider: { nil }, spend: SpendMeter(), client: client).validate(key: " candidate ")
    report.expectEqual(valid, .valid, "the candidate is checked before it is stored")
    if let body = service.requests.first?.httpBody,
       let payload = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] {
        report.expectEqual(payload["state"] as? [String: String], ["text": "Beam key check."], "connection validation sends only a constant, with no library data")
    } else { report.expect(false, "connection validation builds a request") }

    let rejected = await Judge(keyProvider: { nil }, spend: SpendMeter(),
                               client: JevClient(transport: FakeService(fallback: .http(401, body: "")).transport)).validate(key: "candidate")
    report.expectEqual(rejected, .rejected, "authentication refusal is reported as a rejected key")
    let malformed = await Judge(keyProvider: { nil }, spend: SpendMeter(),
                                client: JevClient(transport: FakeService(fallback: .http(200, body: FakeService.answers([]))).transport)).validate(key: "candidate")
    report.expectEqual(malformed, .unreachable, "an incomplete successful response does not claim the key was validated")
}
