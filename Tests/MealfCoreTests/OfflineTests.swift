import Foundation
import Testing

@testable import MealfCore

func temporaryURL() -> URL {
  FileManager.default.temporaryDirectory.appending(
    path: UUID().uuidString, directoryHint: .isDirectory)
}

@Test func editsAndOutboxSurviveRestart() async throws {
  let url = temporaryURL().appending(path: "local.sqlite3")
  let store = try LocalStore(url: url)
  let id = UUID()
  try await store.save(kind: .recipe, id: id, value: Recipe(title: "Soup"))
  let pending = try await store.pending()
  #expect(pending.count == 1)
  let restarted = try LocalStore(url: url)
  let records = try await restarted.entities(kind: .recipe)
  #expect(try records[0].decode(Recipe.self).title == "Soup")
  #expect(try await restarted.pending().first?.mutationID == pending[0].mutationID)
  #expect(try await restarted.deviceID() == store.deviceID())
}

@Test func remoteChangesCannotDiscardUnsentEdits() async throws {
  let store = try LocalStore(url: temporaryURL().appending(path: "local.sqlite3"))
  let id = UUID()
  try await store.save(kind: .recipe, id: id, value: Recipe(title: "Local draft"))
  let remote = Change(
    revision: 1, kind: .recipe, entityID: id, deleted: false,
    payload: try Codec.json(Recipe(title: "Remote")), updatedAt: "2026-10-20T10:00:00Z")
  try await store.apply(PullPage(changes: [remote], cursor: 1, hasMore: false))
  #expect(try await store.entities(kind: .recipe)[0].decode(Recipe.self).title == "Local draft")
  #expect(try await store.pendingCount() == 1)
  #expect(try await store.cursor() == 1)
}

@Test func rejectedTombstonePreservesRecoverableDraft() async throws {
  let store = try LocalStore(url: temporaryURL().appending(path: "local.sqlite3"))
  try await store.save(kind: .recipe, id: UUID(), value: Recipe(title: "Offline edit"))
  let mutation = try await store.pending()[0]
  do {
    try await store.acknowledge(
      MutationResult(
        mutationID: mutation.id, status: "rejected_tombstone", revision: 5, conflict: true),
      mutation: mutation)
    Issue.record("Expected tombstone rejection")
  } catch StoreError.rejectedDeletion {}
  #expect(try await store.pendingCount() == 1)
  #expect(try await store.entities(kind: .recipe).count == 1)
}

@Test func acceptedMutationAndDeltaConverge() async throws {
  let store = try LocalStore(url: temporaryURL().appending(path: "local.sqlite3"))
  let id = UUID()
  let recipe = Recipe(title: "Soup")
  try await store.save(kind: .recipe, id: id, value: recipe)
  let mutation = try await store.pending()[0]
  try await store.acknowledge(
    MutationResult(mutationID: mutation.id, status: "accepted", revision: 1, conflict: false),
    mutation: mutation)
  let change = Change(
    revision: 1, kind: .recipe, entityID: id, deleted: false, payload: try Codec.json(recipe),
    updatedAt: "now")
  try await store.apply(PullPage(changes: [change], cursor: 1, hasMore: false))
  #expect(try await store.pendingCount() == 0)
  #expect(try await store.entities(kind: .recipe)[0].revision == 1)
}

@Test func backendIdentityCannotMixHouseholds() async throws {
  let store = try LocalStore(url: temporaryURL().appending(path: "local.sqlite3"))
  try await store.bind(instanceID: "first")
  try await store.bind(instanceID: "first")
  do {
    try await store.bind(instanceID: "second")
    Issue.record("Expected server identity rejection")
  } catch StoreError.serverChanged {}
}

@Test func shareInboxSurvivesRestartAndAcknowledgesExplicitly() async throws {
  let directory = temporaryURL()
  let inbox = try ShareInbox(directory: directory)
  let request = SharedImport(url: "https://example.com/recipe", text: nil)
  try await inbox.enqueue(request)
  let restarted = try ShareInbox(directory: directory)
  #expect(try await restarted.pending().first?.id == request.id)
  try await restarted.acknowledge(request)
  #expect(try await restarted.pending().isEmpty == true)
}

@Test func scalingPreservesNonNumericQuantities() {
  var ingredient = Ingredient(name: "Flour")
  ingredient.quantity = "100"
  ingredient.quantityMax = "150"
  #expect(ingredient.scaled(by: 1.5).quantity == "150")
  #expect(ingredient.scaled(by: 1.5).quantityMax == "225")
  var salt = Ingredient(name: "Salt")
  salt.originalText = "to taste"
  #expect(salt.scaled(by: 4).quantity == nil)
  #expect(salt.scaled(by: 4).originalText == "to taste")
}

func syntheticToken(_ revision: Int) -> String {
  revision == 0 ? "root" : String(format: "%032x", revision)
}
