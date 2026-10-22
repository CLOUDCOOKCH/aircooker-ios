import Foundation

public struct SyncAnchor: Codable, Equatable, Sendable {
  public let cursor: Int
  public let token: String
  public init(cursor: Int, token: String) {
    self.cursor = cursor
    self.token = token
  }
  public var valid: Bool {
    if cursor == 0 { return token == "root" }
    return cursor > 0 && token.count == 32 && token.allSatisfy { "0123456789abcdef".contains($0) }
  }
}
public struct SyncState: Codable, Sendable {
  public let instanceID: String
  public let cursor: Int
  public let token: String
  public let requestedCursor: Int
  public let requestedToken: String?
  public var anchor: SyncAnchor { SyncAnchor(cursor: cursor, token: token) }
  enum CodingKeys: String, CodingKey {
    case cursor, token
    case instanceID = "instance_id"
    case requestedCursor = "requested_cursor"
    case requestedToken = "requested_token"
  }
}
public struct SyncSnapshot: Codable, Sendable {
  public let instanceID: String
  public let checkpoint: SyncAnchor
  public let changes: [Change]
  public let nextAfter: String?
  enum CodingKeys: String, CodingKey {
    case checkpoint, changes
    case instanceID = "instance_id"
    case nextAfter = "next_after"
  }
}
public struct FullResyncState: Codable, Equatable, Sendable {
  public let instanceID: String
  public let checkpoint: SyncAnchor
  public var after: String?
  public var complete: Bool
}
public struct SyncRecoveryStatus: Sendable {
  public let required: Bool
  public let rebuilding: Bool
  public let stagedCount: Int
  public let localCount: Int
}
