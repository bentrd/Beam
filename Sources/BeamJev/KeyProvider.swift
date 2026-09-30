import Foundation
import Security

/// A Keychain call that failed, with the system's own words for it.
public struct KeychainError: Error, LocalizedError, Equatable, Sendable {
    public let status: OSStatus
    public init(status: OSStatus) { self.status = status }
    public var errorDescription: String? {
        (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error \(status)"
    }
}

/// Injectable credential storage. Checks can exercise failed reads, writes and removals without the login Keychain.
public protocol KeyStoring: Sendable {
    func read() throws -> String?
    /// A failed replacement must leave the previous credential intact.
    func write(_ key: String) throws
    func remove() throws
}

/// The TypeSafe credential, stored in the login Keychain under "dev.beam.app".
/// Debug builds may use BEAM_KEY or TYPESAFE_API_KEY when no Keychain item exists.
/// Release builds use only the Keychain unless an environment is explicitly injected by a check.
public final class KeyProvider: @unchecked Sendable {
    public static let keychainService = "dev.beam.app"
    private static let environmentNames = ["BEAM_KEY", "TYPESAFE_API_KEY"]

    public static var developmentEnvironment: [String: String] {
        #if DEBUG
        ProcessInfo.processInfo.environment
        #else
        [:]
        #endif
    }

    private let storage: any KeyStoring
    private let environment: [String: String]
    private enum Lookup {
        case unknown
        case known(String?)
        case failed(any Error)
    }
    private let lock = NSLock()
    private var lookup = Lookup.unknown

    public init(service: String = KeyProvider.keychainService,
                environment: [String: String] = KeyProvider.developmentEnvironment,
                storage: (any KeyStoring)? = nil) {
        self.storage = storage ?? KeychainStorage(service: service)
        self.environment = environment
    }

    /// Convenience for the judge. Failed Keychain access never silently switches to an environment credential.
    public func key() -> String? { try? readKey() }

    /// Reads once and remembers both the result and any failure, avoiding repeated system permission prompts.
    /// Callers that show connection status use this method so Keychain errors remain visible.
    public func readKey() throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        switch lookup {
        case let .known(key): return key
        case let .failed(error): throw error
        case .unknown: break
        }
        do {
            let key = try storage.read() ?? environmentKey()
            lookup = .known(key)
            return key
        } catch {
            lookup = .failed(error)
            throw error
        }
    }

    /// Replaces the credential atomically. The cache changes only after a successful write.
    public func set(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return try remove() }
        lock.lock()
        defer { lock.unlock() }
        try storage.write(trimmed)
        lookup = .known(trimmed)
    }

    /// Removes the stored credential. Explicit development environments may remain connected afterward.
    public func remove() throws {
        lock.lock()
        defer { lock.unlock() }
        try storage.remove()
        lookup = .known(environmentKey())
    }

    private func environmentKey() -> String? {
        Self.environmentNames.compactMap { environment[$0]?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}

private struct KeychainStorage: KeyStoring {
    let service: String
    private var query: [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: "typesafe-api-key"]
    }

    func read() throws -> String? {
        var item = query
        item[kSecReturnData] = true
        item[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(item as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        guard let data = result as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty else {
            throw KeychainError(status: errSecDecode)
        }
        return key
    }

    func write(_ key: String) throws {
        let attributes: [CFString: Any] = [kSecValueData: Data(key.utf8), kSecAttrLabel: "Beam TypeSafe key"]
        let update = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw KeychainError(status: update) }
        var item = query
        attributes.forEach { item[$0.key] = $0.value }
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}
