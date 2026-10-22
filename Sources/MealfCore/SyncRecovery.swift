import Foundation

public struct SyncIssue: Identifiable, Sendable {
  public var id: String { kind.rawValue + ":" + entityID.uuidString }
  public let kind: EntityKind
  public let entityID: UUID
  public let code: String
  public let mutationCount: Int
  public let local: LocalEntity
  public let server: LocalEntity?
  let basis: Data
}

public struct ArchivedDraft: Codable, Identifiable, Sendable {
  public let formatVersion: Int
  public let id: UUID
  public let entityID: UUID
  public let kind: EntityKind
  public let revision: Int
  public let deleted: Bool
  public let payload: JSONValue
  public let mutations: [Mutation]
  public let errorCode: String
  public let archivedAt: String
  public func exportJSON() throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return String(decoding: try encoder.encode(self), as: UTF8.self)
  }
}
