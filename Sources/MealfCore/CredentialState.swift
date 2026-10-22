import Foundation

public struct PendingRevocation: Codable, Sendable, Identifiable {
  public let id: UUID
  public let sessionID: UUID
  public let refreshToken: String
}

/// Stored as one Keychain value. Never place this envelope in SQLite or App Groups.
public struct CredentialState: Codable, Sendable {
  private var formatVersion = 1
  public private(set) var generation = UUID()
  public private(set) var active: Tokens?
  public private(set) var pending: [PendingRevocation] = []
  public init() {}
  public init(legacy tokens: Tokens) { active = tokens }

  public static func decodeStored(_ data: Data) throws -> (state: Self, needsRewrite: Bool) {
    if let state = try? JSONDecoder().decode(Self.self, from: data) {
      guard state.formatVersion == 1 else { throw APIError.invalidResponse }
      return (state, false)
    }
    return (Self(legacy: try JSONDecoder().decode(Tokens.self, from: data)), true)
  }

  public enum Update: Sendable {
    case install(Tokens, generation: UUID)
    case rotate(Tokens, generation: UUID, previousRefreshToken: String)
    case signOut
    case acknowledge(UUID)
  }

  public mutating func apply(_ update: Update) {
    switch update {
    case .install(let tokens, let expected):
      guard generation == expected else {
        enqueue(tokens)
        return
      }
      if let active { enqueue(active) }
      generation = UUID()
      active = tokens
    case .rotate(let tokens, let expected, let previous):
      guard generation == expected, active?.refreshToken == previous,
        active?.sessionID == tokens.sessionID
      else {
        // A late response cannot resurrect authentication. The old refresh secret
        // also revokes rotated sessions; keep one durable capability per session.
        if active?.sessionID != tokens.sessionID { enqueue(tokens) }
        return
      }
      active = tokens
    case .signOut:
      if let active { enqueue(active) }
      active = nil
      generation = UUID()
    case .acknowledge(let id):
      pending.removeAll { $0.id == id }
    }
  }
  private mutating func enqueue(_ tokens: Tokens) {
    guard !pending.contains(where: { $0.sessionID == tokens.sessionID }) else { return }
    pending.append(
      PendingRevocation(id: UUID(), sessionID: tokens.sessionID, refreshToken: tokens.refreshToken))
  }
}

public protocol TokenVault: Sendable {
  func read() async throws -> CredentialState
  /// Read, apply and persist atomically within the vault; errors must preserve the old value.
  func update(_ command: CredentialState.Update) async throws -> CredentialState
}
