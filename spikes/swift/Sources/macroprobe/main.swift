import Foundation
import Observation
import SwiftUI
import Security
import CryptoKit

@Observable final class Model { var count = 0; var title = "beam" }

let m = Model()
withObservationTracking { _ = m.count } onChange: { print("observed change") }
m.count += 1

// Keychain round trip from an ad-hoc signed / unsigned binary
let service = "dev.beam.probe", account = "typesafe"
let secret = Data("sk-test-123".utf8)
SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account] as CFDictionary)
let add = SecItemAdd([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account, kSecValueData: secret] as CFDictionary, nil)
var out: CFTypeRef?
let get = SecItemCopyMatching([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account, kSecReturnData: true] as CFDictionary, &out)
print("keychain add \(add) get \(get) roundtrip \((out as? Data).map { String(decoding: $0, as: UTF8.self) } ?? "nil")")
SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account] as CFDictionary)

print("sha256", SHA256.hash(data: Data("x".utf8)).prefix(4).map { String(format: "%02x", $0) }.joined())
print("@Observable macro: OK")
