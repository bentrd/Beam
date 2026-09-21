import Foundation
import Security

/// A Keychain call that failed, with the system's own words for it.
public struct KeychainError: Error, LocalizedError, Equatable, Sendable {
    public let status: OSStatus
    public var errorDescription: String? {
        (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error \(status)"
    }
}

/// Where the TypeSafe key lives: the login Keychain, under the service "dev.beam.app".
/// Development builds may instead export `BEAM_KEY` or `TYPESAFE_API_KEY`; the Keychain always wins, so what
/// the user typed in Settings is what is used. The key is never logged, printed or written anywhere else.
public final class KeyProvider: @unchecked Sendable {
    public static let keychainService = "dev.beam.app"
    private static let account = "typesafe-api-key"
    private static let environmentNames = ["BEAM_KEY", "TYPESAFE_API_KEY"]

    private let service: String
    private let environment: [String: String]

    private enum Lookup {
        case unknown
        case known(String?)
    }
    private let lock = NSLock()
    private var lookup = Lookup.unknown

    /// `service` and `environment` are injectable so the checks never touch the real item.
    public init(service: String = KeyProvider.keychainService, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.service = service
        self.environment = environment
    }

    /// The key to use now, or nil. Read once and remembered: the judge asks before every request, and a Keychain
    /// round trip for each of 300 of them is time taken from the first result. A Keychain that refuses
    /// (the user declined the system prompt) reads as "no key" for the same reason: asking again would prompt 300 times.
    public func key() -> String? {
        lock.lock()
        defer { lock.unlock() }
        if case let .known(key) = lookup { return key }
        let key = (try? readKeychain()) ?? environmentKey()
        lookup = .known(key)
        return key
    }

    /// Stores the key, replacing any other. An empty key removes it, as clearing the Settings field does.
    public func set(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return try remove() }
        lock.lock()
        defer { lock.unlock() }
        // Delete then add, not update: the new item belongs to this build, so a rebuilt app is not asked for permission to change it.
        try deleteItem()
        var item = query
        item[kSecValueData] = Data(trimmed.utf8)
        item[kSecAttrLabel] = "Beam TypeSafe key"
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        lookup = .known(trimmed)
    }

    /// Removes the stored key. A development build then falls back to its environment key, if it has one.
    public func remove() throws {
        lock.lock()
        defer { lock.unlock() }
        try deleteItem()
        lookup = .known(environmentKey())
    }

    // MARK: Keychain

    private var query: [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: Self.account]
    }

    private func readKeychain() throws -> String? {
        var item = query
        item[kSecReturnData] = true
        item[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(item as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        guard let data = result as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }

    private func deleteItem() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }

    private func environmentKey() -> String? {
        Self.environmentNames.compactMap { environment[$0] }.first { !$0.isEmpty }
    }
}
