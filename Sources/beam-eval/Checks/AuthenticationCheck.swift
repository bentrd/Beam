import BeamEngine
import BeamFeeds
import BeamJev
import BeamModels
import Foundation
import Security

/// Connection state reflects the credential that was saved, while failed attempts preserve a working account.
@MainActor
enum AuthenticationCheck {
    static let name = "auth"

    static func run(_ report: inout CheckReport, offline: Bool, key: String?) async {
        report.section("TypeSafe connection — validation and Keychain failures")
        await connection(&report)
        await unreadable(&report)
        await staleValidation(&report)
        await disconnectDuringSearch(&report)
    }

    private static func connection(_ report: inout CheckReport) async {
        let storage = CredentialStorage(key: "working")
        let provider = KeyProvider(environment: [:], storage: storage)
        let service = CredentialService()
        guard let engine = try? Engine(environment: .check(jevClient: service.client, keyProvider: provider)) else {
            return report.expect(false, "an engine with injectable credentials opens")
        }
        await engine.launched()
        report.expectEqual(await engine.keyStatus(), .valid, "a saved credential is connected without a launch request")
        report.expectEqual(service.count, 0, "launch sends no credential check")

        report.expectEqual(await engine.setKey("rejected"), .rejected, "a rejected replacement reports the failed attempt")
        report.expectEqual(await engine.keyStatus(), .valid, "a rejected replacement preserves the working connection")
        report.expect(provider.key() == "working" && storage.writes == 0, "a rejected replacement never touches the saved key")

        report.expectEqual(await engine.setKey("offline"), .unreachable, "an unreachable replacement reports a connection failure")
        report.expectEqual(await engine.keyStatus(), .valid, "an unreachable replacement preserves the working connection")
        report.expect(provider.key() == "working" && storage.writes == 0, "an unreachable replacement never touches the saved key")

        storage.failWrite = true
        let failedSave = await engine.setKey("replacement")
        report.expect(isStorageFailure(failedSave), "a validated key that could not be saved reports a Keychain error")
        report.expectEqual(await engine.keyStatus(), .valid, "failed saving preserves the working connection")
        report.expect(provider.key() == "working" && storage.key == "working", "failed saving preserves both stored and cached credentials")
        storage.failWrite = false

        report.expectEqual(await engine.setKey(" replacement \n"), .valid, "a valid candidate connects only after successful storage")
        report.expect(provider.key() == "replacement" && storage.key == "replacement", "successful connection stores the trimmed candidate")
        report.expect(service.allStates.allSatisfy { $0 == ["text": "Beam key check."] }, "connection attempts send only the constant key check, with no user content")

        storage.failRemove = true
        let failedRemoval = await engine.setKey(nil)
        report.expect(isStorageFailure(failedRemoval), "failed Disconnect reports a Keychain error")
        report.expectEqual(await engine.keyStatus(), .valid, "failed Disconnect keeps the active connection")
        report.expectEqual(provider.key(), "replacement", "failed Disconnect keeps the credential")
        storage.failRemove = false
        report.expectEqual(await engine.setKey(nil), .missing, "successful Disconnect reports a missing key")
        report.expectEqual(await engine.keyStatus(), .missing, "successful Disconnect updates the active state")
        report.expect(provider.key() == nil && storage.key == nil, "successful Disconnect removes the credential")
    }

    private static func unreadable(_ report: inout CheckReport) async {
        let storage = CredentialStorage(key: "working")
        storage.failRead = true
        let provider = KeyProvider(environment: ["BEAM_KEY": "fallback"], storage: storage)
        let service = CredentialService()
        guard let engine = try? Engine(environment: .check(jevClient: service.client, keyProvider: provider)) else {
            return report.expect(false, "an engine with denied Keychain access opens")
        }
        await engine.launched()
        let status = await engine.keyStatus()
        report.expect(isStorageFailure(status), "denied Keychain access appears as a storage error")
        report.expect(provider.key() == nil, "denied Keychain access never silently switches accounts")
        report.expectEqual(service.count, 0, "denied Keychain access sends no request")
    }

    private static func staleValidation(_ report: inout CheckReport) async {
        let storage = CredentialStorage(key: "working")
        let provider = KeyProvider(environment: [:], storage: storage)
        let service = CredentialService()
        guard let engine = try? Engine(environment: .check(jevClient: service.client, keyProvider: provider)) else {
            return report.expect(false, "an engine for overlapping connection attempts opens")
        }
        await engine.launched()
        let connecting = Task { await engine.setKey("slow") }
        let began = await Wait.until({ service.count > 0 }, within: .seconds(2))
        report.expect(began, "a delayed connection attempt is in flight")
        report.expectEqual(await engine.setKey(nil), .missing, "Disconnect completes while validation is pending")
        _ = await connecting.value
        report.expectEqual(await engine.keyStatus(), .missing, "a stale validation cannot reconnect after Disconnect")
        report.expect(provider.key() == nil && storage.writes == 0, "a stale validation cannot rewrite the deleted credential")
    }

    private static func disconnectDuringSearch(_ report: inout CheckReport) async {
        let storage = CredentialStorage(key: "working")
        let provider = KeyProvider(environment: [:], storage: storage)
        let service = CredentialService(delaysLibrary: true)
        let web = StubWeb()
        let address = "https://auth.example/feed.xml"
        web.serve(address, Fixtures.rss(title: "Auth", site: "https://auth.example", count: 12, found: 6))
        var environment = EngineEnvironment.check(jevClient: service.client, feedFetch: web.fetch, keyProvider: provider)
        environment.starters = [CatalogEntry(candidate: Lab.candidate("Auth", address), blurb: "A fixture", isStarter: true)]
        environment.refreshesOnLaunch = true
        environment.maxInFlight = 2
        guard let engine = try? Engine(environment: environment) else {
            return report.expect(false, "an engine for disconnecting an active search opens")
        }
        await engine.launched()
        let searching = Task {
            await Wait.collect(engine.list(ListRequest(scope: .all, sentence: Fixtures.sentence)),
                               until: { !$0.isRunning && $0.foot.text == "Add a key to search." }, within: .seconds(3))
        }
        let began = await Wait.until({ service.count > 0 }, within: .seconds(2))
        report.expect(began, "a search has active judgments and queued requests")
        let before = service.count
        report.expectEqual(await engine.setKey(nil), .missing, "Disconnect succeeds while a search is active")
        let stopped = await searching.value
        report.expectEqual(stopped.last?.foot.text, "Add a key to search.", "an active search settles with the disconnected state")
        try? await Task.sleep(for: .milliseconds(300))
        report.expect(service.count <= max(before, 2), "Disconnect cancels queued requests instead of sending them with the old account")
        report.expectEqual(await engine.keyStatus(), .missing, "late work cannot change the disconnected credential status")
    }

    private static func isStorageFailure(_ status: KeyStatus) -> Bool {
        if case .storageError = status { return true }
        return false
    }
}

/// Accessed on the main actor by KeyProvider during these checks.
private final class CredentialStorage: KeyStoring, @unchecked Sendable {
    var key: String?
    var failRead = false
    var failWrite = false
    var failRemove = false
    private(set) var writes = 0
    init(key: String?) { self.key = key }
    func read() throws -> String? {
        if failRead { throw KeychainError(status: errSecAuthFailed) }
        return key
    }
    func write(_ key: String) throws {
        if failWrite { throw KeychainError(status: errSecAuthFailed) }
        self.key = key
        writes += 1
    }
    func remove() throws {
        if failRemove { throw KeychainError(status: errSecAuthFailed) }
        key = nil
    }
}

private final class CredentialService: @unchecked Sendable {
    private let lock = NSLock()
    private var states: [[String: String]] = []
    private let delaysLibrary: Bool
    init(delaysLibrary: Bool = false) { self.delaysLibrary = delaysLibrary }
    var count: Int { lock.withLock { states.count } }
    var allStates: [[String: String]] { lock.withLock { states } }
    var client: JevClient {
        JevClient(transport: { [self] request in
            let payload = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
            let state = payload?["state"] as? [String: String] ?? [:]
            lock.withLock { states.append(state) }
            let credential = request.value(forHTTPHeaderField: "Authorization")
            if credential == "Bearer offline" { throw URLError(.notConnectedToInternet) }
            if credential == "Bearer slow" { try await Task.sleep(for: .milliseconds(200)) }
            if delaysLibrary, state["text"] == nil { try await Task.sleep(for: .seconds(1)) }
            let status = credential == "Bearer rejected" ? 401 : 200
            let body = Data("{\"model\":\"jev-auth-check\",\"answers\":{\"q0\":{\"type\":\"noul\",\"noul\":0.9}},\"usage\":{\"input_tokens\":50}}".utf8)
            let response = HTTPURLResponse(url: JevClient.endpoint, statusCode: status, httpVersion: "HTTP/2", headerFields: nil)!
            return (body, response)
        }, pause: { _ in })
    }
}
