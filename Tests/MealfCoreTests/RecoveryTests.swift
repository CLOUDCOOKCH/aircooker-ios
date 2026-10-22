import Foundation
import Testing

@testable import MealfCore

private func delta(id: UUID, title: String, revision: Int, deleted: Bool = false) throws -> Change {
  Change(
    revision: revision, kind: .recipe, entityID: id, deleted: deleted,
    payload: try Codec.json(Recipe(title: title)), updatedAt: "2026-10-20T12:00:00Z")
}
private actor RecoveryServer: SyncTransport {
  let rejectedID: UUID
  var code: String? = "rejected_tombstone"
  var attempts: [Mutation] = []
  var changes: [Change]
  init(id: UUID) throws {
    rejectedID = id
    changes = [try delta(id: id, title: "Deleted on another device", revision: 1, deleted: true)]
  }
  func setCode(_ value: String?) { code = value }
  func info() -> SystemInfo {
    SystemInfo(
      name: "Synthetic", instanceID: "recovery-tests", version: "0.1.0", apiMajor: 1,
      syncProtocol: 1, configured: true)
  }
  func push(_ mutation: Mutation) throws -> MutationResult {
    attempts.append(mutation)
    if mutation.entityID == rejectedID, let code {
      if code == "rejected_tombstone" {
        return MutationResult(mutationID: mutation.id, status: code, revision: 1, conflict: true)
      }
      throw APIError.http(code == "authentication_required" ? 401 : 409, code)
    }
    let revision = (changes.last?.revision ?? 0) + 1
    changes.append(
      Change(
        revision: revision, kind: mutation.kind, entityID: mutation.entityID,
        deleted: mutation.operation == "delete", payload: mutation.payload ?? .object([:]),
        updatedAt: "now"))
    return MutationResult(
      mutationID: mutation.id, status: "accepted", revision: revision, conflict: false)
  }
  func syncState(cursor: Int) -> SyncState {
    SyncState(
      instanceID: info().instanceID!, cursor: changes.last?.revision ?? 0,
      token: syntheticToken(changes.last?.revision ?? 0), requestedCursor: cursor,
      requestedToken: cursor == 0 || changes.contains(where: { $0.revision == cursor })
        ? syntheticToken(cursor) : nil)
  }
  func snapshot(checkpoint: SyncAnchor, after: String?) throws -> SyncSnapshot {
    throw APIError.invalidResponse
  }
  func pull(cursor: Int, token: String) -> PullPage {
    PullPage(
      changes: changes.filter { $0.revision > cursor }, cursor: changes.last?.revision ?? cursor,
      hasMore: false, cursorToken: syntheticToken(changes.last?.revision ?? cursor))
  }
  func uploadPhoto(_ photo: PendingPhoto) throws -> MediaInfo { throw APIError.invalidResponse }
  func downloadPhoto(id: UUID) throws -> Data { throw APIError.invalidResponse }
}

@Test func blockedEntityDoesNotPreventOtherChangesOrPullAndRecoverySurvivesRestart() async throws {
  let url = temporaryURL().appending(path: "local.sqlite3")
  let store = try LocalStore(url: url)
  let id = UUID()
  let other = UUID()
  try await store.save(kind: .recipe, id: id, value: Recipe(title: "First offline edit"))
  try await store.save(kind: .recipe, id: id, value: Recipe(title: "Latest offline edit"))
  try await store.save(kind: .recipe, id: other, value: Recipe(title: "Independent recipe"))
  let server = try RecoveryServer(id: id)
  do {
    try await SyncEngine(store: store, client: server).synchronise()
    Issue.record("Expected review")
  } catch StoreError.syncNeedsAttention {}
  #expect(await server.attempts.count == 2)  // Failed UUID is not retried by its later edit.
  #expect(try await store.pending().isEmpty)
  #expect(try await store.pendingCount() == 2)
  #expect(try await store.cursor() == 2)
  let restarted = try LocalStore(url: url)
  let issue = try #require(await restarted.syncIssues().first)
  #expect(issue.server?.deleted == true)
  #expect(try issue.local.decode(Recipe.self).title == "Latest offline edit")
  let copyID = try #require(await restarted.resolve(issue, keepRecipeCopy: true))
  #expect(copyID != id)
  #expect(try await restarted.pending().map(\.entityID) == [copyID])
  let archive = try #require(await restarted.archivedDrafts().first)
  #expect(archive.mutations.count == 2)
  #expect(try archive.exportJSON().contains("First offline edit"))
  #expect(try await restarted.entities(kind: .recipe).map(\.id).contains(id) == false)
  try await SyncEngine(store: restarted, client: server).synchronise()
  #expect(try await restarted.pendingCount() == 0)
  #expect(try await LocalStore(url: url).archivedDrafts().first?.id == archive.id)
}

@Test func acceptingServerArchivesLocalAndCanRestoreAsSeparateRecipeLater() async throws {
  let store = try LocalStore(url: temporaryURL().appending(path: "local.sqlite3"))
  let id = UUID()
  try await store.apply(
    PullPage(
      changes: [delta(id: id, title: "Server version", revision: 8)], cursor: 8, hasMore: false))
  try await store.save(kind: .recipe, id: id, value: Recipe(title: "Unsent version"))
  let mutation = try #require(await store.pending().first)
  try await store.markFailure(mutation, code: "invalid_recipe")
  let issue = try #require(await store.syncIssues().first)
  try await store.resolve(issue, keepRecipeCopy: false)
  #expect(try await store.entities(kind: .recipe)[0].decode(Recipe.self).title == "Server version")
  #expect(try await store.pendingCount() == 0)
  let draft = try #require(await store.archivedDrafts().first)
  let restored = try await store.restoreRecipe(draft)
  #expect(restored != id)
  #expect(
    try await store.entities(kind: .recipe).first(where: { $0.id == restored })?.decode(Recipe.self)
      .title == "Unsent version")
  #expect(try await store.archivedDrafts().count == 1)
}

@Test func recoveryCannotDiscardAnEditMadeAfterReview() async throws {
  let store = try LocalStore(url: temporaryURL().appending(path: "local.sqlite3"))
  let id = UUID()
  try await store.save(kind: .recipe, id: id, value: Recipe(title: "Review this"))
  try await store.markFailure(try #require(await store.pending().first), code: "invalid_recipe")
  let issue = try #require(await store.syncIssues().first)
  try await store.save(kind: .recipe, id: id, value: Recipe(title: "Newer unsent edit"))
  do {
    try await store.resolve(issue, keepRecipeCopy: false)
    Issue.record("Expected stale review")
  } catch StoreError.recoveryChanged {}
  #expect(try await store.pendingCount() == 2)
  #expect(try await store.archivedDrafts().isEmpty)
  #expect(
    try await store.entities(kind: .recipe)[0].decode(Recipe.self).title == "Newer unsent edit")
}

@Test func recoveryCannotAcceptAnUnknownServerVersion() async throws {
  let url = temporaryURL().appending(path: "local.sqlite3")
  let store = try LocalStore(url: url)
  let id = UUID()
  try await store.save(kind: .recipe, id: id, value: Recipe(title: "Do not guess"))
  try executeTestSQL(url: url, sql: "UPDATE entity SET revision=5;")
  try await store.markFailure(try #require(await store.pending().first), code: "invalid_recipe")
  let issue = try #require(await store.syncIssues().first)
  do {
    try await store.resolve(issue, keepRecipeCopy: false)
    Issue.record("Expected missing snapshot")
  } catch StoreError.serverSnapshotUnavailable {}
  #expect(try await store.pendingCount() == 1)
  #expect(try await store.archivedDrafts().isEmpty)
}

@Test func recoveryWriteFailureRollsBackArchiveQueueAndRecipe() async throws {
  let url = temporaryURL().appending(path: "local.sqlite3")
  let store = try LocalStore(url: url)
  let id = UUID()
  try await store.save(kind: .recipe, id: id, value: Recipe(title: "Do not lose me"))
  try await store.markFailure(try #require(await store.pending().first), code: "invalid_recipe")
  let issue = try #require(await store.syncIssues().first)
  try executeTestSQL(
    url: url,
    sql:
      "CREATE TRIGGER synthetic_failure BEFORE INSERT ON outbox BEGIN SELECT RAISE(ABORT,'simulated failure'); END;"
  )
  do {
    try await store.resolve(issue, keepRecipeCopy: true)
    Issue.record("Expected rollback")
  } catch StoreError.sqlite(_) {}
  #expect(try await store.archivedDrafts().isEmpty)
  #expect(try await store.pendingCount() == 1)
  #expect(try await store.syncIssues().first?.basis == issue.basis)
  #expect(try await store.entities(kind: .recipe).count == 1)
}

@Test func retryUsesTheIdenticalMutationAfterARecoverableValidationIssue() async throws {
  let store = try LocalStore(url: temporaryURL().appending(path: "local.sqlite3"))
  let id = UUID()
  try await store.save(kind: .recipe, id: id, value: Recipe(title: "Retry safely"))
  let original = try #require(await store.pending().first)
  let server = try RecoveryServer(id: id)
  await server.setCode("recipe_image_not_found")
  let engine = SyncEngine(store: store, client: server)
  do {
    try await engine.synchronise()
    Issue.record("Expected failure")
  } catch StoreError.syncNeedsAttention {}
  let issue = try #require(await store.syncIssues().first)
  await server.setCode(nil)
  try await engine.retry(issue)
  #expect(try await store.pending().first?.id == original.id)
  #expect(try await store.pending().first?.payload == original.payload)
  try await engine.synchronise()
  #expect(await server.attempts.map(\.id) == [original.id, original.id])
  #expect(try await store.syncIssues().isEmpty)
}

@Test func authenticationFailureIsNotQuarantinedAsARejectedDraft() async throws {
  let store = try LocalStore(url: temporaryURL().appending(path: "local.sqlite3"))
  let id = UUID()
  try await store.save(kind: .recipe, id: id, value: Recipe(title: "Authenticate again"))
  let server = try RecoveryServer(id: id)
  await server.setCode("authentication_required")
  do {
    try await SyncEngine(store: store, client: server).synchronise()
    Issue.record("Expected auth failure")
  } catch APIError.http(401, _) {}
  #expect(try await store.syncIssues().isEmpty)
  #expect(try await store.pending().count == 1)
}

@Test func wrongAcknowledgementCannotDeleteOutgoingChanges() async throws {
  let store = try LocalStore(url: temporaryURL().appending(path: "local.sqlite3"))
  try await store.save(kind: .recipe, id: UUID(), value: Recipe(title: "Keep envelope"))
  let mutation = try #require(await store.pending().first)
  for (id, status) in [(UUID(), "accepted"), (mutation.id, "unknown_status")] {
    do {
      try await store.acknowledge(
        MutationResult(mutationID: id, status: status, revision: 2, conflict: false),
        mutation: mutation)
      Issue.record("Expected invalid receipt")
    } catch APIError.invalidResponse {}
  }
  #expect(try await store.pendingCount() == 1)
}

@Test func versionTwoUpgradeRebuildsServerSnapshotsWithoutReplacingPendingEdits() async throws {
  let url = temporaryURL().appending(path: "local.sqlite3")
  let store = try LocalStore(url: url)
  let id = UUID()
  try await store.apply(
    PullPage(
      changes: [delta(id: id, title: "Before offline edit", revision: 4)], cursor: 4, hasMore: false
    ))
  try await store.save(kind: .recipe, id: id, value: Recipe(title: "Pending during upgrade"))
  let mutation = try #require(await store.pending().first)
  try executeTestSQL(
    url: url, sql: "DROP TABLE server_entity; DROP TABLE recovered_draft; PRAGMA user_version=2;")
  let upgraded = try LocalStore(url: url)
  #expect(try await upgraded.cursor() == 0)
  #expect(try await upgraded.pending().first?.id == mutation.id)
  try await upgraded.markFailure(mutation, code: "invalid_recipe")
  try await upgraded.apply(
    PullPage(
      changes: [delta(id: id, title: "Current server", revision: 5)], cursor: 5, hasMore: false))
  let issue = try #require(await upgraded.syncIssues().first)
  #expect(try issue.local.decode(Recipe.self).title == "Pending during upgrade")
  #expect(try issue.server?.decode(Recipe.self).title == "Current server")
}

@Test func changedServerSnapshotInvalidatesAnOpenRecoveryDecision() async throws {
  let store = try LocalStore(url: temporaryURL().appending(path: "local.sqlite3"))
  let id = UUID()
  try await store.apply(
    PullPage(
      changes: [delta(id: id, title: "Original server", revision: 1)], cursor: 1, hasMore: false))
  try await store.save(kind: .recipe, id: id, value: Recipe(title: "Keep this draft"))
  try await store.markFailure(try #require(await store.pending().first), code: "invalid_recipe")
  let review = try #require(await store.syncIssues().first)
  try await store.apply(
    PullPage(
      changes: [delta(id: id, title: "Newer server save", revision: 2)], cursor: 2, hasMore: false))
  do {
    try await store.resolve(review, keepRecipeCopy: false)
    Issue.record("Expected stale server review")
  } catch StoreError.recoveryChanged {}
  #expect(try await store.archivedDrafts().isEmpty)
  let refreshed = try #require(await store.syncIssues().first)
  try await store.resolve(refreshed, keepRecipeCopy: false)
  #expect(
    try await store.entities(kind: .recipe)[0].decode(Recipe.self).title == "Newer server save")
  #expect(try await store.archivedDrafts().first?.formatVersion == 1)
}

@Test func invalidDeltaOrderingRollsBackSnapshotsAndCursor() async throws {
  let store = try LocalStore(url: temporaryURL().appending(path: "local.sqlite3"))
  let id = UUID()
  try await store.apply(
    PullPage(
      changes: [delta(id: id, title: "Keep accepted", revision: 1)], cursor: 1, hasMore: false))
  do {
    try await store.apply(
      PullPage(
        changes: [
          delta(id: id, title: "Out of order", revision: 3),
          delta(id: id, title: "Older", revision: 2),
        ], cursor: 3, hasMore: false))
    Issue.record("Expected malformed page")
  } catch APIError.invalidResponse {}
  #expect(try await store.cursor() == 1)
  #expect(try await store.entities(kind: .recipe)[0].decode(Recipe.self).title == "Keep accepted")
}

private actor PausedRecoveryServer: SyncTransport {
  var gate: CheckedContinuation<SystemInfo, Never>?
  var observers: [CheckedContinuation<Void, Never>] = []
  func waitUntilEntered() async {
    if gate != nil { return }
    await withCheckedContinuation { observers.append($0) }
  }
  func release() {
    gate?.resume(
      returning: SystemInfo(
        name: "Paused", instanceID: "paused-tests", version: "0.1.0", apiMajor: 1, syncProtocol: 1,
        configured: true))
    gate = nil
  }
  func info() async -> SystemInfo {
    await withCheckedContinuation { continuation in
      gate = continuation
      for observer in observers { observer.resume() }
      observers = []
    }
  }
  func syncState(cursor: Int) -> SyncState {
    SyncState(
      instanceID: "paused-tests", cursor: 0, token: "root", requestedCursor: cursor,
      requestedToken: cursor == 0 ? "root" : nil)
  }
  func snapshot(checkpoint: SyncAnchor, after: String?) throws -> SyncSnapshot {
    throw APIError.invalidResponse
  }
  func push(_ mutation: Mutation) throws -> MutationResult { throw APIError.invalidResponse }
  func pull(cursor: Int, token: String) -> PullPage {
    PullPage(changes: [], cursor: cursor, hasMore: false)
  }
  func uploadPhoto(_ photo: PendingPhoto) throws -> MediaInfo { throw APIError.invalidResponse }
  func downloadPhoto(id: UUID) throws -> Data { throw APIError.invalidResponse }
}

@Test func recoveryCoordinatorRejectsDecisionsWhileASyncRequestIsInFlight() async throws {
  let store = try LocalStore(url: temporaryURL().appending(path: "local.sqlite3"))
  try await store.save(kind: .recipe, id: UUID(), value: Recipe(title: "Preserve while syncing"))
  try await store.markFailure(try #require(await store.pending().first), code: "invalid_recipe")
  let issue = try #require(await store.syncIssues().first)
  let server = PausedRecoveryServer()
  let engine = SyncEngine(store: store, client: server)
  let task = Task { try await engine.synchronise() }
  await server.waitUntilEntered()
  do {
    try await engine.resolve(issue, keepRecipeCopy: true)
    Issue.record("Expected active-sync guard")
  } catch StoreError.syncInProgress {}
  do {
    try await engine.retry(issue)
    Issue.record("Expected active-sync guard")
  } catch StoreError.syncInProgress {}
  #expect(try await store.pendingCount() == 1)
  #expect(try await store.archivedDrafts().isEmpty)
  await server.release()
  do {
    try await task.value
    Issue.record("Expected existing review")
  } catch StoreError.syncNeedsAttention {}
}

@Test func migrationReplayCannotRegressACachedAcceptedEntityMidway() async throws {
  let url = temporaryURL().appending(path: "local.sqlite3")
  let store = try LocalStore(url: url)
  let id = UUID()
  try await store.apply(
    PullPage(
      changes: [delta(id: id, title: "Latest cached version", revision: 500)], cursor: 500,
      hasMore: false))
  try executeTestSQL(url: url, sql: "PRAGMA user_version=2;")
  let upgraded = try LocalStore(url: url)
  try await upgraded.apply(
    PullPage(
      changes: [delta(id: id, title: "Old historical version", revision: 1)], cursor: 1,
      hasMore: true))
  #expect(
    try await upgraded.entities(kind: .recipe)[0].decode(Recipe.self).title
      == "Latest cached version")
  #expect(try await upgraded.cursor() == 1)
}
