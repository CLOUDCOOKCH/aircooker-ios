import Foundation
import Testing

@testable import MealfCore

private let historyInstance = "history-tests"
private enum InterruptedSnapshot: Error { case network }
private actor HistoryServer: SyncTransport {
  var log: [Change] = []
  var proofs: [Int: String] = [:]
  var pushed: [Mutation] = []
  var snapshotAfters: [String?] = []
  var failAfterPages: Int?
  var rejectNextPush = false
  var photos: [UUID: Data] = [:]
  func seed(_ count: Int, prefix: String = "Server") throws {
    log = []
    proofs = [:]
    for index in 0..<count {
      let revision = index + 1
      log.append(
        Change(
          revision: revision, kind: .recipe, entityID: UUID(), deleted: false,
          payload: try Codec.json(Recipe(title: "\(prefix) \(index)")), updatedAt: "now"))
      proofs[revision] = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }
  }
  func info() -> SystemInfo {
    SystemInfo(
      name: "Synthetic history", instanceID: historyInstance, version: "0.1.0", apiMajor: 1,
      syncProtocol: 1, configured: true)
  }
  func syncState(cursor: Int) -> SyncState {
    SyncState(
      instanceID: historyInstance, cursor: log.last?.revision ?? 0,
      token: log.last.flatMap { proofs[$0.revision] } ?? "root", requestedCursor: cursor,
      requestedToken: cursor == 0 ? "root" : proofs[cursor])
  }
  func setFailure(after pages: Int?) { failAfterPages = pages }
  func failNextPush() { rejectNextPush = true }
  func push(_ mutation: Mutation) throws -> MutationResult {
    if rejectNextPush {
      rejectNextPush = false
      throw APIError.http(409, "sync_history_changed")
    }
    pushed.append(mutation)
    let revision = (log.last?.revision ?? 0) + 1
    let token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    proofs[revision] = token
    log.append(
      Change(
        revision: revision, kind: mutation.kind, entityID: mutation.entityID,
        deleted: mutation.operation == "delete", payload: mutation.payload ?? .object([:]),
        updatedAt: "now"))
    return MutationResult(
      mutationID: mutation.id, status: "accepted", revision: revision, conflict: false,
      revisionToken: token)
  }
  func pull(cursor: Int, token: String) throws -> PullPage {
    guard syncState(cursor: cursor).requestedToken == token else {
      throw APIError.http(409, "sync_history_changed")
    }
    return PullPage(
      changes: log.filter { $0.revision > cursor }, cursor: log.last?.revision ?? cursor,
      hasMore: false, cursorToken: log.last.flatMap { proofs[$0.revision] } ?? "root")
  }
  func snapshot(checkpoint: SyncAnchor, after: String?) throws -> SyncSnapshot {
    guard syncState(cursor: checkpoint.cursor).requestedToken == checkpoint.token else {
      throw APIError.http(409, "sync_history_changed")
    }
    if let failAfterPages, snapshotAfters.count >= failAfterPages {
      throw InterruptedSnapshot.network
    }
    snapshotAfters.append(after)
    var latest: [String: Change] = [:]
    for change in log where change.revision <= checkpoint.cursor { latest[key(change)] = change }
    let remaining = latest.keys.sorted().filter { $0 > (after ?? "") }
    let page = remaining.prefix(2).compactMap { latest[$0] }
    return SyncSnapshot(
      instanceID: historyInstance, checkpoint: checkpoint, changes: page,
      nextAfter: remaining.count > 2 ? page.last.map(key) : nil)
  }
  private func key(_ change: Change) -> String {
    change.kind.rawValue + ":" + change.entityID.uuidString.lowercased()
  }
  func uploadPhoto(_ photo: PendingPhoto) -> MediaInfo {
    photos[photo.id] = photo.data
    return MediaInfo(
      id: photo.id, contentType: "image/jpeg", sha256: String(repeating: "0", count: 64),
      byteCount: photo.data.count, width: 2, height: 2, createdAt: "now")
  }
  func downloadPhoto(id: UUID) throws -> Data {
    guard let data = photos[id] else { throw APIError.invalidResponse }
    return data
  }
}

@Test func historyRollbackAndReusedRevisionStopWritesBeforeAnyPendingMutation() async throws {
  for restoredCount in [0, 2] {
    let url = temporaryURL().appending(path: "local.sqlite3")
    let store = try LocalStore(url: url)
    let server = HistoryServer()
    try await server.seed(2)
    try await SyncEngine(store: store, client: server).synchronise()
    let original = try #require(await store.entities(kind: .recipe).first)
    try await store.save(kind: .recipe, id: original.id, value: Recipe(title: "Offline work"))
    let mutation = try #require(await store.pending().first)
    try await server.seed(restoredCount, prefix: "Restored branch")
    do {
      try await SyncEngine(store: store, client: server).synchronise()
      Issue.record("Expected recovery requirement")
    } catch StoreError.fullResyncRequired {}
    #expect(await server.pushed.isEmpty)
    #expect(try await store.pending().first?.id == mutation.id)
    #expect(try await LocalStore(url: url).recoveryStatus().required)
    #expect(
      try await store.entities(kind: .recipe).first(where: { $0.id == original.id })?.decode(
        Recipe.self
      ).title == "Offline work")
  }
}

@Test func interruptedSnapshotResumesAfterRestartWithoutUploadingOldEdits() async throws {
  let url = temporaryURL().appending(path: "local.sqlite3")
  let store = try LocalStore(url: url)
  let server = HistoryServer()
  try await server.seed(5)
  try await store.save(
    kind: .recipe, id: UUID(), value: Recipe(title: "Keep offline until recovery"))
  let oldMutation = try #require(await store.pending().first)
  await server.setFailure(after: 1)
  do {
    try await SyncEngine(store: store, client: server).rebuildFromServer()
    Issue.record("Expected interruption")
  } catch InterruptedSnapshot.network {}
  #expect(try await store.entities(kind: .recipe).count == 1)
  #expect(try await store.pending().first?.id == oldMutation.id)
  #expect(try await store.recoveryStatus().stagedCount == 2)
  // New edits during a staged rebuild are also archived by the final transaction.
  try await store.save(
    kind: .recipe, id: oldMutation.entityID, value: Recipe(title: "Latest offline work"))
  await server.setFailure(after: nil)
  let restarted = try LocalStore(url: url)
  try await SyncEngine(store: restarted, client: server).synchronise()
  #expect(await server.pushed.isEmpty)
  #expect(await server.snapshotAfters.count == 3)
  #expect(await server.snapshotAfters.filter { $0 == nil }.count == 1)
  #expect(try await restarted.entities(kind: .recipe).count == 5)
  #expect(try await restarted.pendingCount() == 0)
  let archive = try #require(await restarted.archivedDrafts().first)
  #expect(archive.mutations.count == 2)
  #expect(try archive.payload == Codec.json(Recipe(title: "Latest offline work")))
  #expect(try await restarted.fullResyncState() == nil)
  #expect(try await restarted.recoveryStatus().required == false)
}

@Test func restoredHistoryChangingDuringStagingKeepsEveryLocalRecord() async throws {
  let store = try LocalStore(url: temporaryURL().appending(path: "local.sqlite3"))
  let server = HistoryServer()
  try await server.seed(5)
  try await store.save(kind: .recipe, id: UUID(), value: Recipe(title: "Preserved"))
  await server.setFailure(after: 1)
  do {
    try await SyncEngine(store: store, client: server).rebuildFromServer()
  } catch InterruptedSnapshot.network {}
  try await server.seed(5, prefix: "Another restore")
  await server.setFailure(after: nil)
  do {
    try await SyncEngine(store: store, client: server).synchronise()
    Issue.record("Expected changed history")
  } catch StoreError.fullResyncRequired {}
  #expect(try await store.recoveryStatus().stagedCount == 0)
  #expect(try await store.recoveryStatus().required)
  #expect(try await store.archivedDrafts().isEmpty)
  #expect(try await store.entities(kind: .recipe)[0].decode(Recipe.self).title == "Preserved")
  #expect(try await store.pendingCount() == 1)
}

@Test func fullRebuildArchivesAcceptedRecordsAndTombstonesWithoutResurrectingThem() async throws {
  let store = try LocalStore(url: temporaryURL().appending(path: "local.sqlite3"))
  let server = HistoryServer()
  try await server.seed(2)
  try await SyncEngine(store: store, client: server).synchronise()
  let oldIDs = try await store.entities(kind: .recipe).map(\.id)
  let deletedID = try #require(oldIDs.first)
  try await store.save(
    kind: .recipe, id: deletedID, value: Recipe(title: "Last deletion draft"), delete: true)
  try await server.seed(0)
  try await SyncEngine(store: store, client: server).rebuildFromServer()
  #expect(try await store.entities(kind: .recipe).isEmpty)
  #expect(try await store.pendingCount() == 0)
  let saved = try await store.archivedDrafts()
  #expect(Set(saved.map(\.entityID)) == Set(oldIDs))
  #expect(saved.first(where: { $0.entityID == deletedID })?.deleted == true)
  #expect(saved.first(where: { $0.entityID == deletedID })?.mutations.count == 1)
  #expect(try await store.syncAnchor() == SyncAnchor(cursor: 0, token: "root"))
}

@Test func failedFinalReplacementRollsBackArchivesCursorQueueAndPhotos() async throws {
  let url = temporaryURL().appending(path: "local.sqlite3")
  let store = try LocalStore(url: url)
  let id = UUID()
  try await store.saveRecipe(
    id: id, recipe: Recipe(title: "Atomic recovery"), photo: photoFixture())
  let photo = try #require(await store.pendingPhotos().first)
  try await store.beginFullResync(
    instanceID: historyInstance, checkpoint: SyncAnchor(cursor: 0, token: "root"))
  let state = try #require(await store.fullResyncState())
  try await store.stageSnapshot(
    SyncSnapshot(
      instanceID: historyInstance, checkpoint: state.checkpoint, changes: [], nextAfter: nil),
    expected: state)
  let final = try #require(await store.fullResyncState())
  let verified = SyncState(
    instanceID: historyInstance, cursor: 0, token: "root", requestedCursor: 0,
    requestedToken: "root")
  try executeTestSQL(
    url: url,
    sql:
      "CREATE TRIGGER fail_replacement BEFORE DELETE ON entity BEGIN SELECT RAISE(ABORT,'simulated storage failure'); END;"
  )
  do {
    try await store.finishFullResync(expected: final, verified: verified)
    Issue.record("Expected rollback")
  } catch StoreError.sqlite(_) {}
  #expect(try await store.archivedDrafts().isEmpty)
  #expect(try await store.pendingCount() == 2)
  #expect(try await store.entities(kind: .recipe).count == 1)
  #expect(try await store.fullResyncState() == final)
  #expect(try await store.photoData(id: photo.id) == photo.data)
  try executeTestSQL(url: url, sql: "DROP TRIGGER fail_replacement;")
  try await store.finishFullResync(expected: final, verified: verified)
  #expect(try await store.archivedDrafts().count == 1)
  #expect(try await store.pendingCount() == 0)
  #expect(try await store.photoData(id: photo.id) == photo.data)
}

@Test func restoredArchivedImportedPhotoRecipeQueuesMediaAndDetachesConfirmation() async throws {
  let store = try LocalStore(url: temporaryURL().appending(path: "local.sqlite3"))
  var recipe = Recipe(title: "Imported recipe copy")
  let job = UUID().uuidString.lowercased()
  recipe.provenance = ["import_job_id": job, "reviewed_by_user": "true"]
  recipe.sourceURL = "https://example.invalid/recipe"
  try await store.saveRecipe(id: UUID(), recipe: recipe, photo: photoFixture())
  let server = HistoryServer()
  try await SyncEngine(store: store, client: server).rebuildFromServer()
  let archive = try #require(await store.archivedDrafts().first)
  let copied = try await store.restoreRecipe(archive)
  let copy = try #require(await store.entities(kind: .recipe).first(where: { $0.id == copied }))
    .decode(Recipe.self)
  #expect(copy.provenance["import_job_id"] == nil)
  #expect(copy.provenance["original_import_job_id"] == job)
  #expect(copy.provenance["copied_from_recipe_id"] == archive.entityID.uuidString.lowercased())
  #expect(copy.sourceURL == recipe.sourceURL)
  #expect(try await store.pendingPhotos().count == 1)
  try await SyncEngine(store: store, client: server).synchronise()
  #expect(try await store.pendingCount() == 0)
  #expect(await server.photos.count == 1)
}

@Test func malformedSnapshotNeverChangesTheLibraryOrCommitsPartialStaging() async throws {
  let store = try LocalStore(url: temporaryURL().appending(path: "local.sqlite3"))
  try await store.save(kind: .recipe, id: UUID(), value: Recipe(title: "Keep current"))
  let anchor = SyncAnchor(cursor: 1, token: syntheticToken(1))
  try await store.beginFullResync(instanceID: historyInstance, checkpoint: anchor)
  let state = try #require(await store.fullResyncState())
  let change = Change(
    revision: 1, kind: .recipe, entityID: UUID(), deleted: false,
    payload: try Codec.json(Recipe(title: "Incomplete")), updatedAt: "now")
  do {
    try await store.stageSnapshot(
      SyncSnapshot(
        instanceID: historyInstance, checkpoint: anchor, changes: [change],
        nextAfter: "recipe:wrong"), expected: state)
    Issue.record("Expected malformed continuation")
  } catch APIError.invalidResponse {}
  #expect(try await store.recoveryStatus().stagedCount == 0)
  #expect(try await store.entities(kind: .recipe)[0].decode(Recipe.self).title == "Keep current")
  #expect(try await store.pendingCount() == 1)
}

@Test func historyChangeBetweenPreflightAndPushDoesNotQuarantineOrSendLaterEdits() async throws {
  let store = try LocalStore(url: temporaryURL().appending(path: "local.sqlite3"))
  let server = HistoryServer()
  try await store.save(kind: .recipe, id: UUID(), value: Recipe(title: "Unsent"))
  await server.failNextPush()
  do {
    try await SyncEngine(store: store, client: server).synchronise()
    Issue.record("Expected history guard")
  } catch StoreError.fullResyncRequired {}
  #expect(try await store.syncIssues().isEmpty)
  #expect(try await store.pendingCount() == 1)
  #expect(try await store.recoveryStatus().required)
}

@Test func acknowledgedButNotPulledWriteStillPinsItsCommitProof() async throws {
  let store = try LocalStore(url: temporaryURL().appending(path: "local.sqlite3"))
  try await store.bind(instanceID: historyInstance)
  try await store.save(
    kind: .recipe, id: UUID(), value: Recipe(title: "Acknowledged before interruption"))
  let mutation = try #require(await store.pending().first)
  try await store.acknowledge(
    MutationResult(
      mutationID: mutation.id, status: "accepted", revision: 1, conflict: false,
      revisionToken: syntheticToken(1)), mutation: mutation)
  #expect(try await store.cursor() == 0)
  let server = HistoryServer()
  try await server.seed(1, prefix: "Reused revision")
  do {
    try await SyncEngine(store: store, client: server).synchronise()
    Issue.record("Expected receipt-proof divergence")
  } catch StoreError.fullResyncRequired {}
  #expect(
    try await store.entities(kind: .recipe)[0].decode(Recipe.self).title
      == "Acknowledged before interruption")
}

@Test func historyWireModelsDecodeTheCanonicalServerFixture() throws {
  struct Fixture: Decodable {
    let state: SyncState
    let snapshot: SyncSnapshot
    let delta: PullPage
    let receipt: MutationResult
  }
  let url = try #require(
    Bundle.module.url(
      forResource: "sync-history-v1", withExtension: "json", subdirectory: "Fixtures"))
  let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
  #expect(fixture.state.requestedCursor == fixture.snapshot.checkpoint.cursor)
  #expect(fixture.state.requestedToken == fixture.snapshot.checkpoint.token)
  #expect(fixture.delta.cursorToken == fixture.receipt.revisionToken)
  #expect(fixture.snapshot.changes.count == 2)
  #expect(fixture.delta.changes.first?.deleted == true)
}

@Test func versionThreeWithoutACursorProofRequiresReviewAndPreservesPhotoQueue() async throws {
  let url = temporaryURL().appending(path: "local.sqlite3")
  let store = try LocalStore(url: url)
  let server = HistoryServer()
  try await server.seed(1)
  try await SyncEngine(store: store, client: server).synchronise()
  try await store.saveRecipe(
    id: UUID(), recipe: Recipe(title: "Old app pending work"), photo: photoFixture())
  let mutation = try #require(await store.pending().first)
  try executeTestSQL(
    url: url,
    sql:
      "DELETE FROM metadata WHERE key IN ('cursor_token','observed_checkpoint'); DROP TABLE resync_entity; PRAGMA user_version=3;"
  )
  let upgraded = try LocalStore(url: url)
  do {
    try await SyncEngine(store: upgraded, client: server).synchronise()
    Issue.record("Expected missing-proof review")
  } catch StoreError.fullResyncRequired {}
  #expect(try await upgraded.pending().first?.id == mutation.id)
  #expect(try await upgraded.pendingPhotos().count == 1)
  #expect(try await upgraded.entities(kind: .recipe).count == 2)
  #expect(await server.pushed.isEmpty)
}

@Test func snapshotWithMalformedEntityPayloadCannotReplaceTheWorkingLibrary() async throws {
  let store = try LocalStore(url: temporaryURL().appending(path: "local.sqlite3"))
  try await store.save(kind: .recipe, id: UUID(), value: Recipe(title: "Valid local content"))
  let anchor = SyncAnchor(cursor: 1, token: syntheticToken(1))
  try await store.beginFullResync(instanceID: historyInstance, checkpoint: anchor)
  let state = try #require(await store.fullResyncState())
  let corrupt = Change(
    revision: 1, kind: .recipe, entityID: UUID(), deleted: false,
    payload: .object(["title": .number(10)]), updatedAt: "now")
  do {
    try await store.stageSnapshot(
      SyncSnapshot(
        instanceID: historyInstance, checkpoint: anchor, changes: [corrupt], nextAfter: nil),
      expected: state)
    Issue.record("Expected invalid entity rejection")
  } catch APIError.invalidResponse {}
  #expect(try await store.recoveryStatus().stagedCount == 0)
  #expect(
    try await store.entities(kind: .recipe)[0].decode(Recipe.self).title == "Valid local content")
  #expect(try await store.pendingCount() == 1)
  #expect(try await store.archivedDrafts().isEmpty)
}

@Test func recipeCopiesPreserveFullCapacityAttributionWithinTheServerLimit() async throws {
  for imported in [false, true] {
    let store = try LocalStore(url: temporaryURL().appending(path: "local.sqlite3"))
    var recipe = Recipe(title: "Full attribution")
    for index in 0..<(imported ? 49 : 50) {
      recipe.provenance["fixture_\(index)"] = "Synthetic attribution"
    }
    if imported { recipe.provenance["import_job_id"] = "synthetic-import-job" }
    try await store.save(kind: .recipe, id: UUID(), value: recipe)
    let mutation = try #require(await store.pending().first)
    try await store.markFailure(mutation, code: "rejected_tombstone")
    let issue = try #require(await store.syncIssues().first)
    let copyID = try #require(await store.resolve(issue, keepRecipeCopy: true))
    let copy = try #require(await store.entities(kind: .recipe).first(where: { $0.id == copyID }))
      .decode(Recipe.self)
    #expect(copy.provenance.count == 50)
    #expect(copy.provenance["fixture_0"] == "Synthetic attribution")
    if imported { #expect(copy.provenance["original_import_job_id"] == "synthetic-import-job") }
  }
}
