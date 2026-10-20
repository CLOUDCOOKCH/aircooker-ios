import AirCookerCore
import Foundation
import Security

actor KeychainVault: TokenVault {
  private let service: String
  init(server: String) { service = "ch.cloudcook.aircooker.session." + server }
  func load() throws -> Tokens? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecAttrAccount as String: "household", kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var output: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &output)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = output as? Data else {
      throw VaultError.keychain(status)
    }
    return try JSONDecoder().decode(Tokens.self, from: data)
  }
  func save(_ tokens: Tokens) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecAttrAccount as String: "household",
    ]
    let values: [String: Any] = [
      kSecValueData as String: try JSONEncoder().encode(tokens),
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
    if status == errSecItemNotFound {
      let inserted = SecItemAdd(query.merging(values) { _, new in new } as CFDictionary, nil)
      guard inserted == errSecSuccess else { throw VaultError.keychain(inserted) }
    } else if status != errSecSuccess {
      throw VaultError.keychain(status)
    }
  }
  func clear() throws {
    let status = SecItemDelete(
      [
        kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
        kSecAttrAccount as String: "household",
      ] as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw VaultError.keychain(status)
    }
  }
  enum VaultError: Error { case keychain(OSStatus) }
}
