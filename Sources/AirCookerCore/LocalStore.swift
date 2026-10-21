import CSQLite
import Foundation

public enum StoreError: Error, Sendable {
  case sqlite(String)
  case invalidRecord, serverChanged, rejectedDeletion, invalidPhoto, mediaStorageLimit,
    unsupportedSchema, recoveryChanged, serverSnapshotUnavailable, syncNeedsAttention,
    syncInProgress, fullResyncRequired
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
    guard (0...4).contains(version) else { throw StoreError.unsupportedSchema }
    let sql = """
      PRAGMA journal_mode=WAL;
      PRAGMA synchronous=FULL;
      PRAGMA foreign_keys=ON;
      BEGIN IMMEDIATE;
      CREATE TABLE IF NOT EXISTS entity(kind TEXT NOT NULL,id TEXT NOT NULL,revision INTEGER NOT NULL,deleted INTEGER NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(kind,id));
      CREATE TABLE IF NOT EXISTS outbox(sequence INTEGER PRIMARY KEY AUTOINCREMENT,id TEXT NOT NULL UNIQUE,entity_id TEXT NOT NULL,kind TEXT NOT NULL,body TEXT NOT NULL,error TEXT);
      CREATE INDEX IF NOT EXISTS outbox_entity_sequence ON outbox(kind,entity_id,sequence);
      CREATE INDEX IF NOT EXISTS outbox_failed_entity ON outbox(kind,entity_id) WHERE error IS NOT NULL;
      CREATE TABLE IF NOT EXISTS metadata(key TEXT PRIMARY KEY,value TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS local_media(id TEXT PRIMARY KEY,data BLOB NOT NULL CHECK(length(data)>0 AND length(data)<=1048576),pending_upload INTEGER NOT NULL CHECK(pending_upload IN (0,1)));
      CREATE TABLE IF NOT EXISTS server_entity(kind TEXT NOT NULL,id TEXT NOT NULL,revision INTEGER NOT NULL,deleted INTEGER NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(kind,id));
      CREATE TABLE IF NOT EXISTS recovered_draft(sequence INTEGER PRIMARY KEY AUTOINCREMENT,id TEXT NOT NULL UNIQUE,body TEXT NOT NULL);
      \(version < 3 ? "INSERT OR IGNORE INTO server_entity SELECT * FROM entity WHERE revision>0 AND NOT EXISTS (SELECT 1 FROM outbox WHERE outbox.kind=entity.kind AND outbox.entity_id=entity.id); DELETE FROM metadata WHERE key='cursor';" : "")
      CREATE TABLE IF NOT EXISTS resync_entity(kind TEXT NOT NULL,id TEXT NOT NULL,revision INTEGER NOT NULL,deleted INTEGER NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(kind,id));
      PRAGMA user_version=4;
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
    if kind == .leftover {
      let meals = try entities(kind: .meal)
      if delete {
        guard try LeftoverPlanning.allocated(id: id, meals: meals) == 0 else {
          throw LeftoverError.inUse
        }
      } else {
        let leftover = try decoder.decode(Leftover.self, from: encoder.encode(payload))
        try LeftoverPlanning.validate(id: id, leftover: leftover, meals: meals)
      }
    }
    if kind == .meal && !delete {
      let meal = try decoder.decode(Meal.self, from: encoder.encode(payload))
      if let leftoverID = meal.leftoverID {
        guard let row = try entities(kind: .leftover).first(where: { $0.id == leftoverID }) else {
          throw LeftoverError.unavailable
        }
        try LeftoverPlanning.validateBooking(
          meal, id: leftoverID, leftover: row.decode(Leftover.self),
          meals: entities(kind: .meal), replacing: id)
      }
    }
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
  public func planningSnapshot() throws -> PlanningSnapshot {
    try PlanningSnapshot(
      recipes: entities(kind: .recipe), meals: entities(kind: .meal),
      leftovers: entities(kind: .leftover))
  }
  public func applySuggestions(_ preview: WeeklyPreview, selectedIDs: Set<String>) throws {
    let device = try deviceID()
    try transaction {
      guard try planningSnapshot().basis() == preview.basis,
        selectedIDs.isSubset(of: Set(preview.suggestions.map(\.id)))
      else { throw SuggestionError.stalePreview }
      for suggestion in preview.suggestions where selectedIDs.contains(suggestion.id) {
        try persist(
          kind: .meal, id: UUID(), payload: Codec.json(suggestion.meal), delete: false,
          device: device)
      }
    }
  }
  public func setUnplannedPortions(
    id: UUID, recipeID: UUID, producedOn: String,
    unplanned: String, discard: Bool
  ) throws {
    let device = try deviceID()
    try transaction {
      let existing = try entities(kind: .leftover).first(where: { $0.id == id })?.decode(
        Leftover.self)
      guard existing == nil || existing?.recipeID == recipeID else {
        throw SuggestionError.stalePreview
      }
      let total: Decimal
      if discard {
        guard let existing else { throw LeftoverError.unavailable }
        total = try PortionQuantity.parse(existing.portions)
      } else {
        total =
          try LeftoverPlanning.allocated(id: id, meals: entities(kind: .meal))
          + PortionQuantity.parse(unplanned, allowZero: existing != nil)
      }
      let value = Leftover(
        recipeID: recipeID, portions: NSDecimalNumber(decimal: total).stringValue,
        producedOn: existing?.producedOn ?? producedOn, discarded: discard)
      try persist(
        kind: .leftover, id: id, payload: Codec.json(value), delete: false, device: device)
    }
  }
  public func recordLeftovers(from item: MealOccurrence, portions: String, today: String) throws {
    let device = try deviceID()
    try transaction {
      _ = try PlanningDate.parse(today)
      guard item.date <= today, item.meal.leftoverID == nil,
        let row = try entities(kind: .meal).first(where: { $0.id == item.entityID }),
        try Codec.json(row.decode(Meal.self)) == Codec.json(item.meal),
        try MealPlanning.occurrences(item.meal, from: item.date, through: item.date) == [item.date]
      else { throw SuggestionError.stalePreview }
      let value = Leftover(recipeID: item.meal.recipeID, portions: portions, producedOn: item.date)
      var edits = try MealPlanning.setCooked(item, cooked: true)
      edits.append(try LocalEdit(kind: .leftover, value: value))
      for edit in edits {
        try persist(
          kind: edit.kind, id: edit.id, payload: edit.payload, delete: false, device: device)
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
    try run(
      "SELECT body FROM outbox AS candidate WHERE error IS NULL AND NOT EXISTS (SELECT 1 FROM outbox AS failed WHERE failed.kind=candidate.kind AND failed.entity_id=candidate.entity_id AND failed.error IS NOT NULL) ORDER BY sequence LIMIT 100"
    ).map {
      try decoder.decode(Mutation.self, from: Data(($0["body"] ?? "").utf8))
    }
  }
  public func isReady(_ mutation: Mutation) throws -> Bool {
    try !run(
      "SELECT 1 FROM outbox AS candidate WHERE id=? AND error IS NULL AND NOT EXISTS (SELECT 1 FROM outbox AS failed WHERE failed.kind=candidate.kind AND failed.entity_id=candidate.entity_id AND failed.error IS NOT NULL)",
      [mutation.id.uuidString]
    ).isEmpty
  }
  public func pendingCount() throws -> Int {
    Int(
      try run(
        "SELECT (SELECT COUNT(*) FROM outbox)+(SELECT COUNT(*) FROM local_media WHERE pending_upload=1) AS count"
      ).first?["count"] ?? "0") ?? 0
  }
  public func acknowledge(_ result: MutationResult, mutation: Mutation) throws {
    guard result.mutationID == mutation.id,
      ["accepted", "deleted", "rejected_tombstone"].contains(result.status), result.revision >= 0
    else { throw APIError.invalidResponse }
    if let token = result.revisionToken {
      guard SyncAnchor(cursor: result.revision, token: token).valid else {
        throw APIError.invalidResponse
      }
    }
    if result.status == "rejected_tombstone" {
      _ = try run(
        "UPDATE outbox SET error='rejected_tombstone' WHERE id=?", [mutation.id.uuidString])
      throw StoreError.rejectedDeletion
    }
    try transaction {
      if let token = result.revisionToken {
        try observe(SyncAnchor(cursor: result.revision, token: token))
      }
      _ = try run("DELETE FROM outbox WHERE id=?", [result.mutationID.uuidString])
      _ = try run(
        "UPDATE entity SET revision=? WHERE kind=? AND id=?",
        [String(result.revision), mutation.kind.rawValue, mutation.entityID.uuidString])
    }
  }
  public func apply(_ page: PullPage) throws {
    try transaction {
      let previousCursor = try cursor()
      if let token = page.cursorToken, !SyncAnchor(cursor: page.cursor, token: token).valid {
        throw APIError.invalidResponse
      }
      var previousRevision = previousCursor
      guard page.cursor >= previousCursor else { throw APIError.invalidResponse }
      for change in page.changes {
        guard change.revision > previousRevision, change.revision <= page.cursor else {
          throw APIError.invalidResponse
        }
        previousRevision = change.revision
      }
      for change in page.changes {
        let payload = String(decoding: try encoder.encode(change.payload), as: UTF8.self)
        _ = try run(
          "INSERT INTO server_entity VALUES (?,?,?,?,?) ON CONFLICT(kind,id) DO UPDATE SET revision=excluded.revision,deleted=excluded.deleted,payload=excluded.payload WHERE excluded.revision>=server_entity.revision",
          [
            change.kind.rawValue, change.entityID.uuidString, String(change.revision),
            change.deleted ? "1" : "0", payload,
          ])
        let pending = try run(
          "SELECT 1 FROM outbox WHERE kind=? AND entity_id=? LIMIT 1",
          [change.kind.rawValue, change.entityID.uuidString])
        if !pending.isEmpty { continue }  // Unsynced local content always remains recoverable.
        _ = try run(
          "INSERT INTO entity VALUES (?,?,?,?,?) ON CONFLICT(kind,id) DO UPDATE SET revision=excluded.revision,deleted=excluded.deleted,payload=excluded.payload WHERE excluded.revision>=entity.revision",
          [
            change.kind.rawValue, change.entityID.uuidString, String(change.revision),
            change.deleted ? "1" : "0", payload,
          ])
      }
      _ = try run(
        "INSERT INTO metadata VALUES ('cursor',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
        [String(page.cursor)])
      if let token = page.cursorToken {
        try observe(SyncAnchor(cursor: page.cursor, token: token))
        _ = try run("INSERT OR REPLACE INTO metadata VALUES ('cursor_token',?)", [token])
      } else {
        _ = try run("DELETE FROM metadata WHERE key='cursor_token'")
      }
    }
  }
  public func markFailure(_ mutation: Mutation, code: String) throws {
    // Codes are diagnostics, never arbitrary server response bodies or household content.
    let safe = String(code.prefix(120)).filter {
      $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_")
    }
    _ = try run(
      "UPDATE outbox SET error=? WHERE id=?",
      [safe.isEmpty ? "mutation_rejected" : safe, mutation.id.uuidString])
  }
  private func recoveryRows(kind: EntityKind, id: UUID) throws -> [[[String: String]]] {
    try [
      run("SELECT * FROM entity WHERE kind=? AND id=?", [kind.rawValue, id.uuidString]),
      run(
        "SELECT * FROM outbox WHERE kind=? AND entity_id=? ORDER BY sequence",
        [kind.rawValue, id.uuidString]),
      run("SELECT * FROM server_entity WHERE kind=? AND id=?", [kind.rawValue, id.uuidString]),
    ]
  }
  private func recoveryEntity(_ row: [String: String]?) throws -> LocalEntity? {
    guard let row else { return nil }
    guard let kind = EntityKind(rawValue: row["kind"] ?? ""),
      let id = UUID(uuidString: row["id"] ?? ""), let raw = row["payload"]
    else { throw StoreError.invalidRecord }
    return LocalEntity(
      id: id, kind: kind, revision: Int(row["revision"] ?? "0") ?? 0,
      deleted: row["deleted"] == "1",
      payload: try decoder.decode(JSONValue.self, from: Data(raw.utf8)))
  }
  public func syncIssues() throws -> [SyncIssue] {
    try run(
      "SELECT kind,entity_id,MIN(sequence) AS first FROM outbox WHERE error IS NOT NULL GROUP BY kind,entity_id ORDER BY first"
    ).map { row in
      guard let kind = EntityKind(rawValue: row["kind"] ?? ""),
        let id = UUID(uuidString: row["entity_id"] ?? "")
      else { throw StoreError.invalidRecord }
      let rows = try recoveryRows(kind: kind, id: id)
      guard let local = try recoveryEntity(rows[0].first),
        let code = rows[1].compactMap({ $0["error"] }).first
      else { throw StoreError.invalidRecord }
      return SyncIssue(
        kind: kind, entityID: id, code: code, mutationCount: rows[1].count, local: local,
        server: try recoveryEntity(rows[2].first),
        basis: try JSONSerialization.data(withJSONObject: rows, options: .sortedKeys))
    }
  }
  private func validateRecovery(_ issue: SyncIssue) throws -> [[[String: String]]] {
    let rows = try recoveryRows(kind: issue.kind, id: issue.entityID)
    guard try JSONSerialization.data(withJSONObject: rows, options: .sortedKeys) == issue.basis,
      rows[1].contains(where: { $0["error"] != nil })
    else { throw StoreError.recoveryChanged }
    return rows
  }
  public func retry(_ issue: SyncIssue) throws {
    guard issue.code != "rejected_tombstone" else { throw StoreError.rejectedDeletion }
    try transaction {
      try requireNoResync()
      _ = try validateRecovery(issue)
      _ = try run(
        "UPDATE outbox SET error=NULL WHERE kind=? AND entity_id=?",
        [issue.kind.rawValue, issue.entityID.uuidString])
    }
  }
  @discardableResult public func resolve(_ issue: SyncIssue, keepRecipeCopy: Bool) throws -> UUID? {
    let device = try deviceID()
    return try transaction {
      try requireNoResync()
      let rows = try validateRecovery(issue)
      guard let local = try recoveryEntity(rows[0].first) else { throw StoreError.invalidRecord }
      if keepRecipeCopy {
        guard local.kind == .recipe, !local.deleted else { throw StoreError.invalidRecord }
      }
      // An unknown accepted server state must not be guessed. New unsaved entities may
      // be removed locally; previously accepted entities require a pulled snapshot.
      guard !rows[2].isEmpty || local.revision == 0 else {
        throw StoreError.serverSnapshotUnavailable
      }
      let mutations = try rows[1].map {
        try decoder.decode(Mutation.self, from: Data(($0["body"] ?? "").utf8))
      }
      let archive = ArchivedDraft(
        formatVersion: 1, id: UUID(), entityID: local.id, kind: local.kind,
        revision: local.revision,
        deleted: local.deleted, payload: local.payload, mutations: mutations, errorCode: issue.code,
        archivedAt: ISO8601DateFormatter().string(from: Date()))
      _ = try run(
        "INSERT INTO recovered_draft(id,body) VALUES (?,?)",
        [archive.id.uuidString, String(decoding: encoder.encode(archive), as: UTF8.self)])
      _ = try run(
        "DELETE FROM outbox WHERE kind=? AND entity_id=?",
        [issue.kind.rawValue, issue.entityID.uuidString])
      if let remote = try recoveryEntity(rows[2].first) {
        _ = try run(
          "UPDATE entity SET revision=?,deleted=?,payload=? WHERE kind=? AND id=?",
          [
            String(remote.revision), remote.deleted ? "1" : "0",
            String(decoding: encoder.encode(remote.payload), as: UTF8.self), issue.kind.rawValue,
            issue.entityID.uuidString,
          ])
      } else {
        _ = try run(
          "UPDATE entity SET deleted=1 WHERE kind=? AND id=?",
          [issue.kind.rawValue, issue.entityID.uuidString])
      }
      if keepRecipeCopy {
        return try queueRecipeCopy(payload: local.payload, from: local.id, device: device)
      }
      return nil
    }
  }
  public func archivedDrafts(offset: Int = 0, limit: Int = 50) throws -> [ArchivedDraft] {
    guard offset >= 0, (1...100).contains(limit) else { throw StoreError.invalidRecord }
    return try run(
      "SELECT body FROM recovered_draft ORDER BY sequence DESC LIMIT ? OFFSET ?",
      [String(limit), String(offset)]
    ).map {
      try decoder.decode(ArchivedDraft.self, from: Data(($0["body"] ?? "").utf8))
    }
  }
  @discardableResult public func restoreRecipe(_ draft: ArchivedDraft) throws -> UUID {
    let device = try deviceID()
    return try transaction {
      guard
        let raw = try run("SELECT body FROM recovered_draft WHERE id=?", [draft.id.uuidString])
          .first?["body"]
      else { throw StoreError.invalidRecord }
      let saved = try decoder.decode(ArchivedDraft.self, from: Data(raw.utf8))
      guard saved.kind == .recipe, !saved.deleted else { throw StoreError.invalidRecord }
      return try queueRecipeCopy(payload: saved.payload, from: saved.entityID, device: device)
    }
  }

  public func syncAnchor() throws -> SyncAnchor? {
    let value = try cursor()
    if value == 0 { return SyncAnchor(cursor: 0, token: "root") }
    guard let token = try run("SELECT value FROM metadata WHERE key='cursor_token'").first?["value"]
    else { return nil }
    let anchor = SyncAnchor(cursor: value, token: token)
    return anchor.valid ? anchor : nil
  }
  public func fullResyncState() throws -> FullResyncState? {
    guard let raw = try run("SELECT value FROM metadata WHERE key='full_resync'").first?["value"]
    else { return nil }
    return try decoder.decode(FullResyncState.self, from: Data(raw.utf8))
  }
  public func recoveryStatus() throws -> SyncRecoveryStatus {
    SyncRecoveryStatus(
      required: try !run("SELECT 1 FROM metadata WHERE key='resync_required'").isEmpty,
      rebuilding: try fullResyncState() != nil,
      stagedCount: Int(
        try run("SELECT COUNT(*) AS count FROM resync_entity").first?["count"] ?? "0") ?? 0,
      localCount: Int(
        try run("SELECT COUNT(*) AS count FROM entity WHERE deleted=0").first?["count"] ?? "0") ?? 0
    )
  }
  public func requireFullResync(discardStaging: Bool = false) throws {
    try transaction {
      _ = try run("INSERT OR REPLACE INTO metadata VALUES ('resync_required','1')")
      if discardStaging {
        _ = try run("DELETE FROM resync_entity")
        _ = try run("DELETE FROM metadata WHERE key='full_resync'")
      }
    }
  }
  private func requireNoResync() throws {
    guard try !recoveryStatus().required else { throw StoreError.fullResyncRequired }
  }
  public func beginFullResync(instanceID: String, checkpoint: SyncAnchor) throws {
    guard checkpoint.valid else { throw APIError.invalidResponse }
    try bind(instanceID: instanceID)
    try transaction {
      _ = try run("DELETE FROM resync_entity")
      _ = try run("INSERT OR REPLACE INTO metadata VALUES ('resync_required','1')")
      let state = FullResyncState(
        instanceID: instanceID, checkpoint: checkpoint, after: nil, complete: false)
      _ = try run(
        "INSERT OR REPLACE INTO metadata VALUES ('full_resync',?)",
        [String(decoding: encoder.encode(state), as: UTF8.self)])
    }
  }
  public func stageSnapshot(_ page: SyncSnapshot, expected: FullResyncState) throws {
    try transaction {
      guard try fullResyncState() == expected, !expected.complete,
        page.instanceID == expected.instanceID, page.checkpoint == expected.checkpoint,
        page.changes.count <= 100
      else { throw APIError.invalidResponse }
      var last = expected.after ?? ""
      for change in page.changes {
        try validateSnapshotPayload(change)
        let key = change.kind.rawValue + ":" + change.entityID.uuidString.lowercased()
        guard key > last, change.revision > 0, change.revision <= page.checkpoint.cursor else {
          throw APIError.invalidResponse
        }
        _ = try run(
          "INSERT INTO resync_entity VALUES (?,?,?,?,?)",
          [
            change.kind.rawValue, change.entityID.uuidString, String(change.revision),
            change.deleted ? "1" : "0",
            String(decoding: encoder.encode(change.payload), as: UTF8.self),
          ])
        last = key
      }
      if let after = page.nextAfter {
        guard !page.changes.isEmpty, after == last else { throw APIError.invalidResponse }
      }
      var next = expected
      next.after = last.isEmpty ? nil : last
      next.complete = page.nextAfter == nil
      _ = try run(
        "UPDATE metadata SET value=? WHERE key='full_resync'",
        [String(decoding: encoder.encode(next), as: UTF8.self)])
    }
  }
  public func finishFullResync(expected: FullResyncState, verified: SyncState) throws {
    guard verified.anchor.valid, verified.instanceID == expected.instanceID,
      verified.requestedCursor == expected.checkpoint.cursor,
      verified.requestedToken == expected.checkpoint.token,
      verified.cursor >= expected.checkpoint.cursor
    else { throw StoreError.fullResyncRequired }
    try transaction {
      guard try fullResyncState() == expected, expected.complete else {
        throw APIError.invalidResponse
      }
      // Archive every active cached record, including acknowledged records lost from a
      // restored backup, as well as every record with a queued deletion/update.
      for row in try run(
        "SELECT * FROM entity WHERE deleted=0 OR EXISTS (SELECT 1 FROM outbox WHERE outbox.kind=entity.kind AND outbox.entity_id=entity.id) ORDER BY kind,id"
      ) {
        guard let local = try recoveryEntity(row) else { throw StoreError.invalidRecord }
        let queued = try run(
          "SELECT body FROM outbox WHERE kind=? AND entity_id=? ORDER BY sequence",
          [local.kind.rawValue, local.id.uuidString])
        let mutations = try queued.map {
          try decoder.decode(Mutation.self, from: Data(($0["body"] ?? "").utf8))
        }
        let archive = ArchivedDraft(
          formatVersion: 1, id: UUID(), entityID: local.id, kind: local.kind,
          revision: local.revision, deleted: local.deleted, payload: local.payload,
          mutations: mutations, errorCode: "server_history_rebuilt",
          archivedAt: ISO8601DateFormatter().string(from: Date()))
        _ = try run(
          "INSERT INTO recovered_draft(id,body) VALUES (?,?)",
          [archive.id.uuidString, String(decoding: encoder.encode(archive), as: UTF8.self)])
      }
      _ = try run("DELETE FROM outbox")
      _ = try run("DELETE FROM entity")
      _ = try run("INSERT INTO entity SELECT * FROM resync_entity")
      _ = try run("DELETE FROM server_entity")
      _ = try run("INSERT INTO server_entity SELECT * FROM resync_entity")
      _ = try run("UPDATE local_media SET pending_upload=0")
      _ = try run(
        "INSERT OR REPLACE INTO metadata VALUES ('cursor',?)", [String(expected.checkpoint.cursor)])
      _ = try run(
        "INSERT OR REPLACE INTO metadata VALUES ('cursor_token',?)", [expected.checkpoint.token])
      _ = try run(
        "INSERT OR REPLACE INTO metadata VALUES ('observed_checkpoint',?)",
        [String(decoding: encoder.encode(verified.anchor), as: UTF8.self)])
      _ = try run("DELETE FROM resync_entity")
      _ = try run("DELETE FROM metadata WHERE key IN ('full_resync','resync_required')")
    }
  }
  private func queueRecipeCopy(payload: JSONValue, from originalID: UUID, device: UUID) throws
    -> UUID
  {
    var recipe = try decoder.decode(Recipe.self, from: encoder.encode(payload))
    // Import confirmation belongs to its original recipe UUID. Preserve attribution
    // without replaying a job's one-time confirmation against a new identity.
    if let job = recipe.provenance.removeValue(forKey: "import_job_id") {
      recipe.provenance["original_import_job_id"] = job
    }
    // Server provenance is bounded to 50 entries. Preserve the user's attribution
    // rather than making an otherwise valid full-capacity recipe impossible to copy.
    if recipe.provenance.count < 50 || recipe.provenance["copied_from_recipe_id"] != nil {
      recipe.provenance["copied_from_recipe_id"] = originalID.uuidString.lowercased()
    }
    if let imageID = recipe.imageID {
      _ = try run("UPDATE local_media SET pending_upload=1 WHERE id=?", [imageID.uuidString])
    }
    let id = UUID()
    try persist(kind: .recipe, id: id, payload: Codec.json(recipe), delete: false, device: device)
    return id
  }

  public func observedAnchor() throws -> SyncAnchor? {
    guard
      let raw = try run("SELECT value FROM metadata WHERE key='observed_checkpoint'").first?[
        "value"]
    else { return try syncAnchor() }
    let anchor = try decoder.decode(SyncAnchor.self, from: Data(raw.utf8))
    guard anchor.valid else { throw StoreError.invalidRecord }
    return anchor
  }
  public func observe(_ anchor: SyncAnchor) throws {
    guard anchor.valid else { throw APIError.invalidResponse }
    if let old = try observedAnchor(), old.cursor > anchor.cursor { return }
    _ = try run(
      "INSERT OR REPLACE INTO metadata VALUES ('observed_checkpoint',?)",
      [String(decoding: encoder.encode(anchor), as: UTF8.self)])
  }

  private func validateSnapshotPayload(_ change: Change) throws {
    if change.deleted { return }
    let data = try encoder.encode(change.payload)
    do {
      switch change.kind {
      case .recipe: _ = try decoder.decode(Recipe.self, from: data)
      case .meal: _ = try decoder.decode(Meal.self, from: data)
      case .pantry: _ = try decoder.decode(PantryItem.self, from: data)
      case .leftover: _ = try decoder.decode(Leftover.self, from: data)
      case .template: _ = try decoder.decode(MealTemplate.self, from: data)
      }
    } catch { throw APIError.invalidResponse }
  }

}
