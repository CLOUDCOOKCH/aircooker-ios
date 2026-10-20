import CSQLite
import Foundation
import Testing

@testable import AirCookerCore

func photoFixture() throws -> Data {
  let url = try #require(
    Bundle.module.url(forResource: "photo", withExtension: "jpg", subdirectory: "Fixtures"))
  return try Data(contentsOf: url)
}

func executeTestSQL(url: URL, sql: String) throws {
  var db: OpaquePointer?
  guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw StoreError.sqlite("test_open") }
  defer { sqlite3_close(db) }
  guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
    throw StoreError.sqlite("test_sql")
  }
}

@Test func photoAndRecipeQueueSurviveRestartTogether() async throws {
  let url = temporaryURL().appending(path: "local.sqlite3")
  let store = try LocalStore(url: url)
  let id = UUID()
  let photo = try photoFixture()
  try await store.saveRecipe(id: id, recipe: Recipe(title: "Offline photograph"), photo: photo)
  let restart = try LocalStore(url: url)
  let recipe = try await restart.entities(kind: .recipe)[0].decode(Recipe.self)
  let imageID = try #require(recipe.imageID)
  #expect(try await restart.photoData(id: imageID) == photo)
  #expect(try await restart.pendingPhotos()[0].id == imageID)
  #expect(try await restart.pendingCount() == 2)
  #expect(try await restart.pending()[0].entityID == id)
}

@Test func failedRecipeWriteRollsBackPhotoAndOutbox() async throws {
  let url = temporaryURL().appending(path: "local.sqlite3")
  let store = try LocalStore(url: url)
  try executeTestSQL(
    url: url,
    sql:
      "CREATE TRIGGER simulate_disk_failure BEFORE INSERT ON outbox BEGIN SELECT RAISE(ABORT,'synthetic write failure'); END;"
  )
  do {
    try await store.saveRecipe(
      id: UUID(), recipe: Recipe(title: "Must not partially save"), photo: photoFixture())
    Issue.record("Expected write failure")
  } catch StoreError.sqlite(_) {}
  #expect(try await store.entities(kind: .recipe).isEmpty)
  #expect(try await store.pendingPhotos().isEmpty)
  #expect(try await store.pendingCount() == 0)
}

@Test func downloadedPhotosAreAvailableOfflineWithoutOutgoingMutation() async throws {
  let url = temporaryURL().appending(path: "local.sqlite3")
  let store = try LocalStore(url: url)
  let imageID = UUID()
  var recipe = Recipe(title: "Cached recipe")
  recipe.imageID = imageID
  try await store.apply(
    PullPage(
      changes: [
        Change(
          revision: 1, kind: .recipe, entityID: UUID(), deleted: false, payload: Codec.json(recipe),
          updatedAt: "now")
      ], cursor: 1, hasMore: false))
  #expect(try await store.missingPhotos() == [imageID])
  try await store.cachePhoto(id: imageID, data: photoFixture())
  let restarted = try LocalStore(url: url)
  #expect(try await restarted.photoData(id: imageID) == photoFixture())
  #expect(try await restarted.pendingCount() == 0)
  #expect(try await restarted.missingPhotos().isEmpty)
}

@Test func versionOneDatabaseUpgradesWithoutLosingPendingChanges() async throws {
  let url = temporaryURL().appending(path: "local.sqlite3")
  let old = try LocalStore(url: url)
  try await old.save(kind: .recipe, id: UUID(), value: Recipe(title: "Keep me"))
  let mutationID = try await old.pending()[0].mutationID
  try executeTestSQL(url: url, sql: "DROP TABLE local_media; PRAGMA user_version=1;")
  let upgraded = try LocalStore(url: url)
  #expect(try await upgraded.pending()[0].mutationID == mutationID)
  #expect(try await upgraded.entities(kind: .recipe)[0].decode(Recipe.self).title == "Keep me")
  #expect(try await upgraded.pendingPhotos().isEmpty)
}

@Test func newerLocalSchemaIsNotSilentlyDowngraded() async throws {
  let url = temporaryURL().appending(path: "local.sqlite3")
  _ = try LocalStore(url: url)
  try executeTestSQL(url: url, sql: "PRAGMA user_version=999;")
  do {
    _ = try LocalStore(url: url)
    Issue.record("Expected unsupported schema")
  } catch StoreError.unsupportedSchema {}
}

private enum TransferFailure: Error { case interrupted, missingPhoto }
private actor MediaServer: SyncTransport {
  var uploaded: [UUID: Data] = [:]
  var uploadAttempts: [UUID] = []
  var mutations: [UUID] = []
  var events: [String] = []
  var loseFirstUploadResponse = false
  var loseFirstMutationResponse = false
  var committed: [UUID: MutationResult] = [:]
  var changes: [Change] = []
  func setFailure(upload: Bool = false, mutation: Bool = false) {
    loseFirstUploadResponse = upload
    loseFirstMutationResponse = mutation
  }
  func info() -> SystemInfo {
    SystemInfo(
      name: "Synthetic", instanceID: "synthetic-household", version: "0.1.0", apiMajor: 1,
      syncProtocol: 1, configured: true)
  }
  func uploadPhoto(_ photo: PendingPhoto) throws -> MediaInfo {
    events.append("photo")
    uploadAttempts.append(photo.id)
    if let existing = uploaded[photo.id] { #expect(existing == photo.data) }
    uploaded[photo.id] = photo.data
    if loseFirstUploadResponse {
      loseFirstUploadResponse = false
      throw TransferFailure.interrupted
    }
    return MediaInfo(
      id: photo.id, contentType: "image/jpeg", sha256: String(repeating: "0", count: 64),
      byteCount: photo.data.count, width: 2, height: 2, createdAt: "now")
  }
  func push(_ mutation: Mutation) throws -> MutationResult {
    events.append("recipe")
    mutations.append(mutation.mutationID)
    if let payload = mutation.payload {
      let recipe = try JSONDecoder().decode(Recipe.self, from: JSONEncoder().encode(payload))
      if let id = recipe.imageID, uploaded[id] == nil { throw TransferFailure.missingPhoto }
    }
    if let replay = committed[mutation.mutationID] { return replay }
    let revision = committed.count + 1
    let result = MutationResult(
      mutationID: mutation.mutationID, status: "accepted", revision: revision, conflict: false)
    committed[mutation.mutationID] = result
    changes.append(
      Change(
        revision: revision, kind: mutation.kind, entityID: mutation.entityID, deleted: false,
        payload: mutation.payload ?? .object([:]), updatedAt: "now"))
    if loseFirstMutationResponse {
      loseFirstMutationResponse = false
      throw TransferFailure.interrupted
    }
    return result
  }
  func pull(cursor: Int) -> PullPage {
    PullPage(
      changes: changes.filter { $0.revision > cursor }, cursor: changes.last?.revision ?? cursor,
      hasMore: false)
  }
  func downloadPhoto(id: UUID) throws -> Data {
    guard let data = uploaded[id] else { throw TransferFailure.missingPhoto }
    return data
  }
}

@Test func syncUploadsPhotoBeforeRecipe() async throws {
  let store = try LocalStore(url: temporaryURL().appending(path: "local.sqlite3"))
  let server = MediaServer()
  try await store.saveRecipe(
    id: UUID(), recipe: Recipe(title: "Photo first"), photo: photoFixture())
  try await SyncEngine(store: store, client: server).synchronise()
  #expect(await server.events == ["photo", "recipe"])
  #expect(try await store.pendingCount() == 0)
}

@Test func lostUploadResponseReplaysSamePhotoAfterAppRestart() async throws {
  let url = temporaryURL().appending(path: "local.sqlite3")
  let store = try LocalStore(url: url)
  let server = MediaServer()
  try await store.saveRecipe(
    id: UUID(), recipe: Recipe(title: "Retry photo"), photo: photoFixture())
  await server.setFailure(upload: true)
  do {
    try await SyncEngine(store: store, client: server).synchronise()
    Issue.record("Expected interrupted upload")
  } catch TransferFailure.interrupted {}
  #expect(try await store.pendingCount() == 2)
  let restarted = try LocalStore(url: url)
  try await SyncEngine(store: restarted, client: server).synchronise()
  #expect(await server.uploadAttempts.count == 2)
  #expect(await Set(server.uploadAttempts).count == 1)
  #expect(await server.events == ["photo", "photo", "recipe"])
  #expect(try await restarted.pendingCount() == 0)
}

@Test func lostRecipeResponseKeepsMutationIdentityAndAcknowledgedPhoto() async throws {
  let url = temporaryURL().appending(path: "local.sqlite3")
  let store = try LocalStore(url: url)
  let server = MediaServer()
  try await store.saveRecipe(
    id: UUID(), recipe: Recipe(title: "Retry recipe"), photo: photoFixture())
  await server.setFailure(mutation: true)
  do {
    try await SyncEngine(store: store, client: server).synchronise()
    Issue.record("Expected interrupted recipe response")
  } catch TransferFailure.interrupted {}
  #expect(try await store.pendingCount() == 1)
  try await SyncEngine(store: LocalStore(url: url), client: server).synchronise()
  #expect(await server.uploadAttempts.count == 1)
  #expect(await server.mutations.count == 2)
  #expect(await Set(server.mutations).count == 1)
}
