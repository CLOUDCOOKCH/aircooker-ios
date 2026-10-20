import CSQLite
import Foundation

public enum StoreError: Error, Sendable {
  case sqlite(String)
  case invalidRecord, serverChanged, rejectedDeletion, invalidPhoto, mediaStorageLimit,
    unsupportedSchema
}
// The handle is confined to LocalStore's actor after construction.
private final class Connection: @unchecked Sendable {
  let handle: OpaquePointer
  init(path: String) throws {
    var pointer: OpaquePointer?
    guard
      sqlite3_open_v2(
        path, &pointer, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
        == SQLITE_OK, let pointer
    else {
      if let pointer { sqlite3_close(pointer) }
      throw StoreError.sqlite("database_open_failed")
    }
    handle = pointer
    sqlite3_busy_timeout(handle, 5000)
  }
  deinit { sqlite3_close(handle) }
}
public actor LocalStore {
  private let connection: Connection
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()
  public init(url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    connection = try Connection(path: url.path)
    var versionStatement: OpaquePointer?
    guard
      sqlite3_prepare_v2(connection.handle, "PRAGMA user_version", -1, &versionStatement, nil)
        == SQLITE_OK
    else { throw StoreError.sqlite("migration_failed") }
    let version =
      sqlite3_step(versionStatement) == SQLITE_ROW ? sqlite3_column_int(versionStatement, 0) : -1
    sqlite3_finalize(versionStatement)
    guard (0...2).contains(version) else { throw StoreError.unsupportedSchema }
    let sql = """
      PRAGMA journal_mode=WAL;
      PRAGMA synchronous=FULL;
      PRAGMA foreign_keys=ON;
      BEGIN IMMEDIATE;
      CREATE TABLE IF NOT EXISTS entity(kind TEXT NOT NULL,id TEXT NOT NULL,revision INTEGER NOT NULL,deleted INTEGER NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(kind,id));
      CREATE TABLE IF NOT EXISTS outbox(sequence INTEGER PRIMARY KEY AUTOINCREMENT,id TEXT NOT NULL UNIQUE,entity_id TEXT NOT NULL,kind TEXT NOT NULL,body TEXT NOT NULL,error TEXT);
      CREATE TABLE IF NOT EXISTS metadata(key TEXT PRIMARY KEY,value TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS local_media(id TEXT PRIMARY KEY,data BLOB NOT NULL CHECK(length(data)>0 AND length(data)<=1048576),pending_upload INTEGER NOT NULL CHECK(pending_upload IN (0,1)));
      PRAGMA user_version=2;
      COMMIT;
      """
    guard sqlite3_exec(connection.handle, sql, nil, nil, nil) == SQLITE_OK else {
      throw StoreError.sqlite("migration_failed")
    }
  }
  private func run(_ sql: String, _ values: [String] = []) throws -> [[String: String]] {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(connection.handle, sql, -1, &statement, nil) == SQLITE_OK,
      let statement
    else { throw StoreError.sqlite("prepare_failed") }
    defer { sqlite3_finalize(statement) }
    for (index, value) in values.enumerated() {
      let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
      guard sqlite3_bind_text(statement, Int32(index + 1), value, -1, transient) == SQLITE_OK else {
        throw StoreError.sqlite("bind_failed")
      }
    }
    var result: [[String: String]] = []
    while true {
      let status = sqlite3_step(statement)
      if status == SQLITE_DONE { return result }
      guard status == SQLITE_ROW else { throw StoreError.sqlite("statement_failed") }
      var row: [String: String] = [:]
      for index in 0..<sqlite3_column_count(statement) {
        let name = String(cString: sqlite3_column_name(statement, index))
        if let text = sqlite3_column_text(statement, index) { row[name] = String(cString: text) }
      }
      result.append(row)
    }
  }
  private func transaction<T>(_ work: () throws -> T) throws -> T {
    _ = try run("BEGIN IMMEDIATE")
    do {
      let result = try work()
      _ = try run("COMMIT")
      return result
    } catch {
      _ = try? run("ROLLBACK")
      throw error
    }
  }
  public func deviceID() throws -> UUID {
    if let value = try run("SELECT value FROM metadata WHERE key='device'").first?["value"],
      let id = UUID(uuidString: value)
    {
      return id
    }
    let id = UUID()
    _ = try run("INSERT INTO metadata VALUES ('device',?)", [id.uuidString])
    return id
  }
  public func bind(instanceID: String) throws {
    if let old = try run("SELECT value FROM metadata WHERE key='instance'").first?["value"],
      old != instanceID
    {
      throw StoreError.serverChanged
    }
    _ = try run("INSERT OR IGNORE INTO metadata VALUES ('instance',?)", [instanceID])
  }
  public func cursor() throws -> Int {
    Int(try run("SELECT value FROM metadata WHERE key='cursor'").first?["value"] ?? "0") ?? 0
  }
  private func persist(kind: EntityKind, id: UUID, payload: JSONValue, delete: Bool, device: UUID)
    throws
  {
    let revision =
      Int(
        try run(
          "SELECT revision FROM entity WHERE kind=? AND id=?", [kind.rawValue, id.uuidString]
        ).first?["revision"] ?? "0") ?? 0
    let mutation = Mutation(
      entityID: id, kind: kind, operation: delete ? "delete" : "upsert", baseRevision: revision,
      payload: delete ? nil : payload, deviceID: device)
    let raw = String(decoding: try encoder.encode(payload), as: UTF8.self)
    _ = try run(
      "INSERT INTO entity VALUES (?,?,?,?,?) ON CONFLICT(kind,id) DO UPDATE SET deleted=excluded.deleted,payload=excluded.payload",
      [kind.rawValue, id.uuidString, String(revision), delete ? "1" : "0", raw])
    _ = try run(
      "INSERT INTO outbox(id,entity_id,kind,body) VALUES (?,?,?,?)",
      [
        mutation.id.uuidString, id.uuidString, kind.rawValue,
        String(decoding: try encoder.encode(mutation), as: UTF8.self),
      ])
  }
  public func save<T: Encodable & Sendable>(
    kind: EntityKind, id: UUID, value: T, delete: Bool = false
  ) throws {
    let payload = try Codec.json(value)
    let device = try deviceID()
    try transaction {
      try persist(kind: kind, id: id, payload: payload, delete: delete, device: device)
    }
  }
  public func saveBatch(_ edits: [LocalEdit]) throws {
    guard edits.count <= 100 else { throw PlanningError.tooManyChanges }
    guard !edits.isEmpty else { return }
    let device = try deviceID()
    try transaction {
      for edit in edits {
        try persist(
          kind: edit.kind, id: edit.id, payload: edit.payload,
          delete: edit.deleted, device: device)
      }
    }
  }
  public func saveRecipe(id: UUID, recipe: Recipe, photo: Data?) throws {
    let device = try deviceID()
    var saved = recipe
    try transaction {
      if let photo {
        let imageID = UUID()
        try insertPhoto(id: imageID, data: photo, pending: true)
        saved.imageID = imageID
      }
      try persist(kind: .recipe, id: id, payload: Codec.json(saved), delete: false, device: device)
    }
  }
  private func insertPhoto(id: UUID, data: Data, pending: Bool) throws {
    guard !data.isEmpty, data.count <= 1_048_576, data.starts(with: [0xff, 0xd8]),
      data.suffix(2) == Data([0xff, 0xd9])
    else { throw StoreError.invalidPhoto }
    let used =
      Int(
        try run("SELECT COALESCE(SUM(length(data)),0) AS size FROM local_media").first?["size"]
          ?? "0") ?? 0
    guard used + data.count <= 268_435_456 else { throw StoreError.mediaStorageLimit }
    var statement: OpaquePointer?
    guard
      sqlite3_prepare_v2(
        connection.handle, "INSERT INTO local_media VALUES (?,?,?)", -1, &statement, nil)
        == SQLITE_OK, let statement
    else { throw StoreError.sqlite("media_prepare_failed") }
    defer { sqlite3_finalize(statement) }
    let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    guard sqlite3_bind_text(statement, 1, id.uuidString, -1, transient) == SQLITE_OK,
      sqlite3_bind_int(statement, 3, pending ? 1 : 0) == SQLITE_OK
    else { throw StoreError.sqlite("media_bind_failed") }
    let bound = data.withUnsafeBytes { bytes in
      sqlite3_bind_blob(statement, 2, bytes.baseAddress, Int32(bytes.count), transient)
    }
    guard bound == SQLITE_OK, sqlite3_step(statement) == SQLITE_DONE else {
      throw StoreError.sqlite("media_write_failed")
    }
  }
  public func photoData(id: UUID) throws -> Data? {
    var statement: OpaquePointer?
    guard
      sqlite3_prepare_v2(
        connection.handle, "SELECT data FROM local_media WHERE id=?", -1, &statement, nil)
        == SQLITE_OK, let statement
    else { throw StoreError.sqlite("media_prepare_failed") }
    defer { sqlite3_finalize(statement) }
    let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    guard sqlite3_bind_text(statement, 1, id.uuidString, -1, transient) == SQLITE_OK else {
      throw StoreError.sqlite("media_bind_failed")
    }
    let status = sqlite3_step(statement)
    if status == SQLITE_DONE { return nil }
    guard status == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else {
      throw StoreError.invalidPhoto
    }
    return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
  }
  public func pendingPhoto(id: UUID) throws -> PendingPhoto? {
    guard
      !(try run("SELECT id FROM local_media WHERE id=? AND pending_upload=1", [id.uuidString]))
        .isEmpty
    else { return nil }
    guard let data = try photoData(id: id) else { throw StoreError.invalidPhoto }
    return PendingPhoto(id: id, data: data)
  }
  public func pendingPhotos() throws -> [PendingPhoto] {
    try run("SELECT id FROM local_media WHERE pending_upload=1 ORDER BY id LIMIT 8").map { row in
      guard let id = UUID(uuidString: row["id"] ?? ""), let data = try photoData(id: id) else {
        throw StoreError.invalidPhoto
      }
      return PendingPhoto(id: id, data: data)
    }
  }
  public func acknowledgePhoto(id: UUID) throws {
    _ = try run("UPDATE local_media SET pending_upload=0 WHERE id=?", [id.uuidString])
  }
  public func cachePhoto(id: UUID, data: Data) throws {
    try transaction {
      if try photoData(id: id) != nil { return }
      try insertPhoto(id: id, data: data, pending: false)
    }
  }
  public func missingPhotos() throws -> [UUID] {
    let references = try entities(kind: .recipe).compactMap { try $0.decode(Recipe.self).imageID }
    return try Array(Set(references)).filter { try photoData(id: $0) == nil }.sorted {
      $0.uuidString < $1.uuidString
    }
  }
  public func entities(kind: EntityKind) throws -> [LocalEntity] {
    try run("SELECT * FROM entity WHERE kind=? AND deleted=0 ORDER BY id", [kind.rawValue]).map {
      row in
      guard let id = UUID(uuidString: row["id"] ?? ""), let raw = row["payload"] else {
        throw StoreError.invalidRecord
      }
      return LocalEntity(
        id: id, kind: kind, revision: Int(row["revision"] ?? "0") ?? 0, deleted: false,
        payload: try decoder.decode(JSONValue.self, from: Data(raw.utf8)))
    }
  }
  public func pending() throws -> [Mutation] {
    try run("SELECT body FROM outbox ORDER BY sequence LIMIT 100").map {
      try decoder.decode(Mutation.self, from: Data(($0["body"] ?? "").utf8))
    }
  }
  public func pendingCount() throws -> Int {
    Int(
      try run(
        "SELECT (SELECT COUNT(*) FROM outbox)+(SELECT COUNT(*) FROM local_media WHERE pending_upload=1) AS count"
      ).first?["count"] ?? "0") ?? 0
  }
  public func acknowledge(_ result: MutationResult, mutation: Mutation) throws {
    if result.status == "rejected_tombstone" {
      _ = try run(
        "UPDATE outbox SET error='rejected_tombstone' WHERE id=?", [mutation.id.uuidString])
      throw StoreError.rejectedDeletion
    }
    try transaction {
      _ = try run("DELETE FROM outbox WHERE id=?", [result.mutationID.uuidString])
      _ = try run(
        "UPDATE entity SET revision=? WHERE kind=? AND id=?",
        [String(result.revision), mutation.kind.rawValue, mutation.entityID.uuidString])
    }
  }
  public func apply(_ page: PullPage) throws {
    try transaction {
      for change in page.changes {
        let pending = try run(
          "SELECT 1 FROM outbox WHERE kind=? AND entity_id=? LIMIT 1",
          [change.kind.rawValue, change.entityID.uuidString])
        if !pending.isEmpty { continue }  // Unsynced local content always remains recoverable.
        let payload = String(decoding: try encoder.encode(change.payload), as: UTF8.self)
        _ = try run(
          "INSERT INTO entity VALUES (?,?,?,?,?) ON CONFLICT(kind,id) DO UPDATE SET revision=excluded.revision,deleted=excluded.deleted,payload=excluded.payload",
          [
            change.kind.rawValue, change.entityID.uuidString, String(change.revision),
            change.deleted ? "1" : "0", payload,
          ])
      }
      _ = try run(
        "INSERT INTO metadata VALUES ('cursor',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
        [String(page.cursor)])
    }
  }
}
