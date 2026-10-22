import Foundation
import MealfCore
import Security

actor KeychainVault: TokenVault {
  private let service: String
  init(server: String) { service = "ch.cloudcook.mealf.session." + server }
  func read() throws -> CredentialState {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecAttrAccount as String: "household", kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var output: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &output)
    if status == errSecItemNotFound {
      let state = CredentialState()
      try persist(state)
      return state
    }
    guard status == errSecSuccess, let data = output as? Data else {
      throw VaultError.keychain(status)
    }
    let decoded = try CredentialState.decodeStored(data)
    // Persist legacy upgrades before returning a stable generation to any request.
    if decoded.needsRewrite { try persist(decoded.state) }
    return decoded.state
  }

  func update(_ command: CredentialState.Update) throws -> CredentialState {
    var state = try read()
    state.apply(command)
    try persist(state)
    return state
  }
  private func persist(_ state: CredentialState) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecAttrAccount as String: "household",
    ]
    let values: [String: Any] = [
      kSecValueData as String: try JSONEncoder().encode(state),
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
  enum VaultError: Error { case keychain(OSStatus) }
}
