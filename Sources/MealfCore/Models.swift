import Foundation

public enum JSONValue: Codable, Equatable, Sendable {
  case string(String)
  case number(Double)
  case bool(Bool)
  case array([JSONValue])
  case object([String: JSONValue])
  case null
  public init(from decoder: any Decoder) throws {
    let c = try decoder.singleValueContainer()
    if c.decodeNil() {
      self = .null
    } else if let v = try? c.decode(Bool.self) {
      self = .bool(v)
    } else if let v = try? c.decode(String.self) {
      self = .string(v)
    } else if let v = try? c.decode(Double.self) {
      self = .number(v)
    } else if let v = try? c.decode([JSONValue].self) {
      self = .array(v)
    } else {
      self = .object(try c.decode([String: JSONValue].self))
    }
  }
  public func encode(to encoder: any Encoder) throws {
    var c = encoder.singleValueContainer()
    switch self {
    case .string(let v): try c.encode(v)
    case .number(let v): try c.encode(v)
    case .bool(let v): try c.encode(v)
    case .array(let v): try c.encode(v)
    case .object(let v): try c.encode(v)
    case .null: try c.encodeNil()
    }
  }
  public var string: String? { if case .string(let v) = self { v } else { nil } }
}

public enum EntityKind: String, Codable, Sendable, CaseIterable {
  case recipe, meal, pantry, leftover, template
}
public struct Ingredient: Codable, Identifiable, Equatable, Sendable {
  public var id: UUID = UUID()
  public var name: String = ""
  public var quantity: String? = nil
  public var quantityMax: String? = nil
  public var unit: String = ""
  public var preparation: String = ""
  public var originalText: String = ""
  public var quantityText: String? = nil
  public var notes: String? = nil
  public var optional: Bool? = nil
  public var group: String? = nil
  public init(name: String = "") { self.name = name }
  enum CodingKeys: String, CodingKey {
    case id, name, quantity, unit, preparation
    case quantityMax = "quantity_max"
    case originalText = "original_text"
    case quantityText = "quantity_text"
    case notes, optional, group
  }
  public func scaled(by ratio: Decimal) -> Ingredient {
    var result = self
    if let quantity,
      let value = Decimal(string: quantity, locale: Locale(identifier: "en_US_POSIX"))
    {
      result.quantity = NSDecimalNumber(decimal: value * ratio).stringValue
    }
    if let quantityMax,
      let value = Decimal(string: quantityMax, locale: Locale(identifier: "en_US_POSIX"))
    {
      result.quantityMax = NSDecimalNumber(decimal: value * ratio).stringValue
    }
    return result
  }
}
public struct Recipe: Codable, Equatable, Sendable {
  public var title = ""
  public var description = ""
  public var sourceURL: String? = nil
  public var sourcePlatform = "manual"
  public var imageID: UUID? = nil
  public var servings = "2"
  public var ingredients: [Ingredient] = []
  public var steps: [String] = []
  public var notes = ""
  public var rating: Int? = nil
  public var nutrition: [String: String]? = nil
  public var nutritionSource: String? = nil
  public var provenance: [String: String] = [:]
  // Preserve optional PWA/import metadata even before native editors expose it.
  public var schemaVersion: String? = nil
  public var instructionDetails: JSONValue? = nil
  public var times: JSONValue? = nil
  public var language: String? = nil
  public var yieldInfo: JSONValue? = nil
  public var category: String? = nil
  public var cuisine: String? = nil
  public var tags: [String]? = nil
  public init(title: String = "") { self.title = title }
  enum CodingKeys: String, CodingKey {
    case title, description, servings, ingredients, steps, notes, rating, nutrition, provenance
    case sourceURL = "source_url"
    case sourcePlatform = "source_platform"
    case imageID = "image_id"
    case nutritionSource = "nutrition_source"
    case schemaVersion = "schema_version"
    case instructionDetails = "instruction_details"
    case yieldInfo = "yield_info"
    case times, language, category, cuisine, tags
  }
}
public struct Meal: Codable, Sendable {
  public var recipeID: UUID
  public var date: String
  public var category: String
  public var servings: String
  public var order: Int = 0
  public var leftoverID: UUID? = nil
  public var recurrence: Recurrence? = nil
  public var cooked = false
  public init(recipeID: UUID, date: String, category: String, servings: String = "2") {
    self.recipeID = recipeID
    self.date = date
    self.category = category
    self.servings = servings
  }
  enum CodingKeys: String, CodingKey {
    case date, category, servings, order, recurrence, cooked
    case recipeID = "recipe_id"
    case leftoverID = "leftover_id"
  }
}
public struct PantryItem: Codable, Sendable {
  public var name: String
  public var available = true
  public var includeThisWeek = false
  public init(name: String) { self.name = name }
  enum CodingKeys: String, CodingKey {
    case name, available
    case includeThisWeek = "include_this_week"
  }
}
public struct Mutation: Codable, Identifiable, Sendable {
  public var mutationID: UUID
  public var entityID: UUID
  public var kind: EntityKind
  public var operation: String
  public var baseRevision: Int
  public var payload: JSONValue?
  public var deviceID: UUID
  public var clientTimestamp: String
  public var idempotencyKey: UUID
  public var id: UUID { mutationID }
  public init(
    entityID: UUID, kind: EntityKind, operation: String, baseRevision: Int, payload: JSONValue?,
    deviceID: UUID
  ) {
    let id = UUID()
    mutationID = id
    idempotencyKey = id
    self.entityID = entityID
    self.kind = kind
    self.operation = operation
    self.baseRevision = baseRevision
    self.payload = payload
    self.deviceID = deviceID
    clientTimestamp = ISO8601DateFormatter().string(from: Date())
  }
  enum CodingKeys: String, CodingKey {
    case mutationID = "mutation_id"
    case entityID = "entity_id"
    case kind, operation
    case baseRevision = "base_revision"
    case payload
    case deviceID = "device_id"
    case clientTimestamp = "client_timestamp"
    case idempotencyKey = "idempotency_key"
  }
}
public struct MutationResult: Codable, Sendable {
  public var mutationID: UUID
  public var status: String
  public var revision: Int
  public var conflict: Bool
  public var revisionToken: String?
  public init(
    mutationID: UUID, status: String, revision: Int, conflict: Bool, revisionToken: String? = nil
  ) {
    self.mutationID = mutationID
    self.status = status
    self.revision = revision
    self.conflict = conflict
    self.revisionToken = revisionToken
  }
  enum CodingKeys: String, CodingKey {
    case mutationID = "mutation_id"
    case status, revision, conflict
    case revisionToken = "revision_token"
  }
}
public struct Change: Codable, Sendable {
  public var revision: Int
  public var kind: EntityKind
  public var entityID: UUID
  public var deleted: Bool
  public var payload: JSONValue
  public var updatedAt: String
  enum CodingKeys: String, CodingKey {
    case revision, kind
    case entityID = "entity_id"
    case deleted, payload
    case updatedAt = "updated_at"
  }
}
public struct PullPage: Codable, Sendable {
  public var changes: [Change]
  public var cursor: Int
  public var hasMore: Bool
  public var cursorToken: String?
  public init(changes: [Change], cursor: Int, hasMore: Bool, cursorToken: String? = nil) {
    self.changes = changes
    self.cursor = cursor
    self.hasMore = hasMore
    self.cursorToken = cursorToken
  }
  enum CodingKeys: String, CodingKey {
    case changes, cursor
    case hasMore = "has_more"
    case cursorToken = "cursor_token"
  }
}
public struct LocalEntity: Identifiable, Sendable {
  public var id: UUID
  public var kind: EntityKind
  public var revision: Int
  public var deleted: Bool
  public var payload: JSONValue
  public func decode<T: Decodable>(_ type: T.Type) throws -> T {
    try JSONDecoder().decode(type, from: JSONEncoder().encode(payload))
  }
}
public enum Codec {
  public static func json<T: Encodable>(_ value: T) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
  }
}

public struct ImportDraft: Decodable, Identifiable, Sendable {
  public var id: UUID
  public var state: String
  public var recipe: Recipe?
  public var warnings: [String]
  public var errorCode: String?
  enum CodingKeys: String, CodingKey {
    case id, state, recipe, warnings
    case errorCode = "error_code"
  }
}

public struct PendingPhoto: Sendable {
  public let id: UUID
  public let data: Data
}
public struct MediaInfo: Codable, Sendable {
  public var id: UUID
  public var contentType: String
  public var sha256: String
  public var byteCount: Int
  public var width: Int
  public var height: Int
  public var createdAt: String
  enum CodingKeys: String, CodingKey {
    case id, sha256, width, height
    case contentType = "content_type"
    case byteCount = "byte_count"
    case createdAt = "created_at"
  }
}
