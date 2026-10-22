import Foundation
import Testing

@testable import MealfCore

private let demoInstant = ISO8601DateFormatter().date(from: "2026-10-21T12:00:00Z")!
private func demoRoot() -> URL {
  FileManager.default.temporaryDirectory.appending(path: "mealf-demo-\(UUID())")
}

@Test func demoSeedsActualPlanningDataWithSeparateIdentity() async throws {
  let root = demoRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = try LocalStore(url: DemoWorkspace.databaseURL(in: root))
  let seed = try DemoWorkspace.seed(now: demoInstant, timeZone: "UTC", language: "en")
  try await store.initialiseDemo(seed)
  let snapshot = try await store.planningSnapshot()
  #expect(snapshot.recipes.count == 7 && snapshot.meals.count == 9)
  #expect(snapshot.leftovers.count == 1)
  let overview = try PlannerOverview.build(meals: snapshot.meals, now: demoInstant, timeZone: "UTC")
  #expect(overview.plannedSlots == 8)
  let suggestions = try WeeklyRecommendations.generate(snapshot: snapshot, week: overview.monday)
  #expect(suggestions.suggestions.count == 2)
  #expect(suggestions.suggestions.contains { $0.meal.leftoverID != nil })
  let today = try #require(overview.selectedMeals.first)
  let recipe = try #require(snapshot.recipes.first { $0.id == today.meal.recipeID })
  #expect(try recipe.decode(Recipe.self).title == "Lemon chicken & potatoes")
  #expect(try recipe.decode(Recipe.self).provenance["origin"] == "offline-demo")
  #expect(try await store.pendingCount() == seed.count)
  await #expect(throws: StoreError.self) { try await store.bind(instanceID: UUID().uuidString) }
}

@Test func demoRestartPreservesEditsDeletionsAndOutboxIdentities() async throws {
  let root = demoRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let url = DemoWorkspace.databaseURL(in: root)
  let store = try LocalStore(url: url)
  let seed = try DemoWorkspace.seed(now: demoInstant, timeZone: "UTC", language: "en")
  try await store.initialiseDemo(seed)
  let rows = try await store.entities(kind: .recipe)
  let first = try #require(rows.first)
  var recipe = try first.decode(Recipe.self)
  recipe.title = "My edited sample"
  try await store.save(kind: .recipe, id: first.id, value: recipe)
  let second = rows[1]
  try await store.save(kind: .recipe, id: second.id, value: second.payload, delete: true)
  let mutations = try await store.pending().map(\.id)
  let reopened = try LocalStore(url: url)
  try await reopened.initialiseDemo(
    DemoWorkspace.seed(
      now: demoInstant.addingTimeInterval(86400 * 14), timeZone: "UTC", language: "de"))
  #expect(try await reopened.pending().map(\.id) == mutations)
  let after = try await reopened.entities(kind: .recipe)
  #expect(after.count == 6)
  #expect(try after.first { $0.id == first.id }?.decode(Recipe.self).title == "My edited sample")
  #expect(!after.contains { $0.id == second.id })
}

@Test func demoCannotOverwriteRealHouseholdOrItsPendingChanges() async throws {
  let root = demoRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let realURL = root.appending(path: "mealf.sqlite3")
  let store = try LocalStore(url: realURL)
  let instance = UUID().uuidString
  try await store.bind(instanceID: instance)
  let id = UUID()
  try await store.save(kind: .recipe, id: id, value: Recipe(title: "Household recipe"))
  let pending = try await store.pending().map(\.id)
  let seed = try DemoWorkspace.seed(now: demoInstant, timeZone: "UTC", language: "en")
  await #expect(throws: StoreError.self) { try await store.initialiseDemo(seed) }
  #expect(try await store.entities(kind: .recipe).count == 1)
  #expect(try await store.pending().map(\.id) == pending)
  try await store.bind(instanceID: instance)
  let demo = try LocalStore(url: DemoWorkspace.databaseURL(in: root))
  try await demo.initialiseDemo(seed)
  #expect(try await store.entities(kind: .recipe).count == 1)
  #expect(try await demo.entities(kind: .recipe).count == 7)
}

@Test func demoFailedSeedRollsBackEntitiesMediaAndIdentity() async throws {
  let root = demoRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = try LocalStore(url: DemoWorkspace.databaseURL(in: root))
  var seed = try DemoWorkspace.seed(now: demoInstant, timeZone: "UTC", language: "en")
  var invalid = Meal(recipeID: UUID(), date: "2026-10-21", category: "lunch")
  invalid.leftoverID = UUID()
  seed.append(try LocalEdit(kind: .meal, value: invalid))
  await #expect(throws: (any Error).self) {
    try await store.initialiseDemo(
      seed, photos: [DemoWorkspace.photoID: Data([0xff, 0xd8, 0xff, 0xd9])])
  }
  #expect(try await store.entities(kind: .recipe).isEmpty)
  #expect(try await store.pendingCount() == 0)
  #expect(try await store.photoData(id: DemoWorkspace.photoID) == nil)
  try await store.bind(instanceID: UUID().uuidString)
}

@Test func demoUsesHouseholdDatesAndGermanSampleContent() async throws {
  let root = demoRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = try LocalStore(url: DemoWorkspace.databaseURL(in: root))
  let nearMidnight = ISO8601DateFormatter().date(from: "2026-10-19T00:30:00Z")!
  try await store.initialiseDemo(
    DemoWorkspace.seed(now: nearMidnight, timeZone: "America/Los_Angeles", language: "de"))
  let snapshot = try await store.planningSnapshot()
  let overview = try PlannerOverview.build(
    meals: snapshot.meals, now: nearMidnight, timeZone: "America/Los_Angeles")
  #expect(overview.today == "2026-10-18" && overview.monday == "2026-10-12")
  #expect(
    try snapshot.recipes.map { try $0.decode(Recipe.self).title }.contains(
      "Zitronenhähnchen mit Kartoffeln"))
  #expect(
    try await store.entities(kind: .pantry).contains {
      try $0.decode(PantryItem.self).name == "Salz"
    })
}
