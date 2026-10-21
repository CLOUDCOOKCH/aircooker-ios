import Foundation
import Testing

@testable import AirCookerCore

private func row<T: Encodable>(_ kind: EntityKind, _ value: T, id: UUID = UUID()) throws
  -> LocalEntity
{
  LocalEntity(id: id, kind: kind, revision: 1, deleted: false, payload: try Codec.json(value))
}
private func temporaryStore() throws -> (URL, LocalStore) {
  let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
  return try (root, LocalStore(url: root.appending(path: "local.sqlite3")))
}
@Test func portionsRejectPartialNumbersAndPreventOverbooking() throws {
  for invalid in ["2 cups", "1/2", "NaN", "-1", "0", "1e100", "1,5"] {
    #expect(throws: LeftoverError.self) { try PortionQuantity.parse(invalid) }
  }
  #expect(try PortionQuantity.parse("1.5") == Decimal(string: "1.5"))
  let id = UUID()
  let rid = UUID()
  let leftover = Leftover(recipeID: rid, portions: "3.5", producedOn: "2026-10-19")
  var first = Meal(recipeID: rid, date: "2026-10-20", category: "dinner", servings: "2")
  first.leftoverID = id
  let existing = try row(.meal, first)
  #expect(
    try LeftoverPlanning.available(id: id, leftover: leftover, meals: [existing])
      == Decimal(string: "1.5"))
  #expect(throws: LeftoverError.self) {
    try LeftoverPlanning.validateBooking(first, id: id, leftover: leftover, meals: [existing])
  }
  try LeftoverPlanning.validateBooking(
    first, id: id, leftover: leftover, meals: [existing], replacing: existing.id)
  first.date = "2026-10-18"
  #expect(throws: LeftoverError.self) {
    try LeftoverPlanning.validateBooking(first, id: id, leftover: leftover, meals: [])
  }
}
@Test func editingAndDiscardingLeftoversPreservesBookedPortions() async throws {
  let (root, store) = try temporaryStore()
  defer { try? FileManager.default.removeItem(at: root) }
  let id = UUID()
  let rid = UUID()
  let mealID = UUID()
  var leftover = Leftover(recipeID: rid, portions: "4", producedOn: "2026-10-19")
  try await store.save(kind: .leftover, id: id, value: leftover)
  var meal = Meal(recipeID: rid, date: "2026-10-20", category: "dinner", servings: "2")
  meal.leftoverID = id
  try await store.save(kind: .meal, id: mealID, value: meal)
  leftover.portions = "1"
  await #expect(throws: LeftoverError.self) {
    try await store.save(kind: .leftover, id: id, value: leftover)
  }
  #expect(try await store.pending().count == 2)
  leftover.portions = "4"
  leftover.discarded = true
  try await store.save(kind: .leftover, id: id, value: leftover)
  meal.cooked = true
  try await store.save(kind: .meal, id: mealID, value: meal)
  await #expect(throws: LeftoverError.self) {
    try await store.save(kind: .meal, id: UUID(), value: meal)
  }
  await #expect(throws: LeftoverError.self) {
    try await store.save(kind: .leftover, id: id, value: leftover, delete: true)
  }
}
@Test func recordRecurringMealLeftoversOnlyMarksOneOccurrenceCooked() async throws {
  let (root, store) = try temporaryStore()
  defer { try? FileManager.default.removeItem(at: root) }
  let id = UUID()
  var meal = Meal(recipeID: UUID(), date: "2026-10-19", category: "dinner")
  meal.recurrence = Recurrence(until: "2026-11-30")
  try await store.save(kind: .meal, id: id, value: meal)
  let item = try #require(
    MealPlanning.expand(
      try await store.entities(kind: .meal), from: "2026-10-26", through: "2026-10-26"
    ).first)
  try await store.recordLeftovers(from: item, portions: "3", today: "2026-10-27")
  let meals = try await store.entities(kind: .meal)
  let next = try #require(
    MealPlanning.expand(meals, from: "2026-11-02", through: "2026-11-02").first)
  #expect(!next.meal.cooked)
  let cooked = try #require(
    MealPlanning.expand(meals, from: "2026-10-26", through: "2026-10-26").first)
  #expect(cooked.meal.cooked && cooked.meal.recurrence == nil)
  #expect(try await store.entities(kind: .leftover).count == 1)
  // Reopening the old editor cannot create another group from its stale occurrence.
  await #expect(throws: SuggestionError.self) {
    try await store.recordLeftovers(from: item, portions: "2", today: "2026-10-27")
  }
}
@Test func recommendationsAreLocalPreviewsAndPreferVarietyOverRecentCooking() throws {
  let rid = UUID()
  let other = UUID()
  var first = Recipe()
  first.title = "Soup"
  first.rating = 5
  var second = Recipe()
  second.title = "Rice"
  second.rating = 4
  var meal = Meal(recipeID: rid, date: "2026-10-18", category: "dinner")
  meal.cooked = true
  let snapshot = try PlanningSnapshot(
    recipes: [row(.recipe, first, id: rid), row(.recipe, second, id: other)],
    meals: [row(.meal, meal)])
  let result = try WeeklyRecommendations.generate(snapshot: snapshot, week: "2026-10-19")
  #expect(result.suggestions.count == 2 && result.suggestions[0].meal.recipeID == other)
  let repeated = try WeeklyRecommendations.generate(
    snapshot: snapshot, week: "2026-10-19", options: SuggestionOptions(allowRepeats: true))
  #expect(repeated.suggestions.count == 7)
  #expect(
    repeated.suggestions.map(\.id)
      == (try WeeklyRecommendations.generate(
        snapshot: snapshot, week: "2026-10-19", options: SuggestionOptions(allowRepeats: true)))
      .suggestions.map(\.id))
}
@Test func leftoverSuggestionsRespectReservationsAndFutureProduction() throws {
  let rid = UUID()
  let lid = UUID()
  var recipe = Recipe()
  recipe.title = "Soup"
  var reservation = Meal(recipeID: rid, date: "2026-10-22", category: "lunch")
  reservation.leftoverID = lid
  let snapshot = try PlanningSnapshot(
    recipes: [row(.recipe, recipe, id: rid)], meals: [row(.meal, reservation)],
    leftovers: [
      row(.leftover, Leftover(recipeID: rid, portions: "4", producedOn: "2026-10-21"), id: lid)
    ])
  let preview = try WeeklyRecommendations.generate(snapshot: snapshot, week: "2026-10-19")
  #expect(preview.suggestions.count == 1)
  #expect(
    preview.suggestions[0].meal.date == "2026-10-21"
      && preview.suggestions[0].meal.leftoverID == lid)
  #expect(preview.suggestions[0].reasons == ["use_available_leftovers"])
}
@Test func acceptingStalePreviewPreservesCurrentPlansAndPendingChanges() async throws {
  let (root, store) = try temporaryStore()
  defer { try? FileManager.default.removeItem(at: root) }
  var recipe = Recipe()
  recipe.title = "Soup"
  let rid = UUID()
  try await store.save(kind: .recipe, id: rid, value: recipe)
  let preview = try WeeklyRecommendations.generate(
    snapshot: await store.planningSnapshot(), week: "2026-10-19")
  #expect(try await store.entities(kind: .meal).isEmpty)
  try await store.save(
    kind: .meal, id: UUID(), value: Meal(recipeID: rid, date: "2026-10-19", category: "dinner"))
  await #expect(throws: SuggestionError.self) {
    try await store.applySuggestions(preview, selectedIDs: Set(preview.suggestions.map(\.id)))
  }
  #expect(try await store.entities(kind: .meal).count == 1)
  #expect(try await store.pending().count == 2)
}
@Test func acceptedSuggestionSelectionAndOutboxSurviveRestart() async throws {
  let (root, store) = try temporaryStore()
  defer { try? FileManager.default.removeItem(at: root) }
  var recipe = Recipe()
  recipe.title = "Soup"
  try await store.save(kind: .recipe, id: UUID(), value: recipe)
  let preview = try WeeklyRecommendations.generate(
    snapshot: await store.planningSnapshot(), week: "2026-10-19",
    options: SuggestionOptions(allowRepeats: true))
  let chosen = Set(preview.suggestions.prefix(2).map(\.id))
  try await store.applySuggestions(preview, selectedIDs: chosen)
  let reopened = try LocalStore(url: root.appending(path: "local.sqlite3"))
  #expect(try await reopened.entities(kind: .meal).count == 2)
  #expect(try await reopened.pending().count == 3)
}

@Test func settingUnplannedPortionsKeepsReservationsAndAllowsZeroAvailable() async throws {
  let (root, store) = try temporaryStore()
  defer { try? FileManager.default.removeItem(at: root) }
  let id = UUID()
  let rid = UUID()
  let mid = UUID()
  try await store.save(
    kind: .leftover, id: id, value: Leftover(recipeID: rid, portions: "4", producedOn: "2026-10-19")
  )
  var meal = Meal(recipeID: rid, date: "2026-10-20", category: "dinner")
  meal.leftoverID = id
  try await store.save(kind: .meal, id: mid, value: meal)
  try await store.setUnplannedPortions(
    id: id, recipeID: rid, producedOn: "2026-10-19", unplanned: "0", discard: false)
  let value = try #require(try await store.entities(kind: .leftover).first).decode(Leftover.self)
  #expect(value.portions == "2")
  #expect(
    try LeftoverPlanning.available(
      id: id, leftover: value, meals: await store.entities(kind: .meal)) == 0)
  try await store.save(kind: .meal, id: mid, value: meal, delete: true)
  try await store.setUnplannedPortions(
    id: id, recipeID: rid, producedOn: "2026-10-19", unplanned: "1.5", discard: false)
  #expect(try await store.entities(kind: .leftover).first?.decode(Leftover.self).portions == "1.5")
}
@Test func failedSuggestionApprovalRollsBackAllMealsAndOutgoingMutations() async throws {
  let (root, store) = try temporaryStore()
  defer { try? FileManager.default.removeItem(at: root) }
  var recipe = Recipe()
  recipe.title = "Soup"
  try await store.save(kind: .recipe, id: UUID(), value: recipe)
  let preview = try WeeklyRecommendations.generate(
    snapshot: await store.planningSnapshot(), week: "2026-10-19",
    options: SuggestionOptions(allowRepeats: true))
  try executeTestSQL(
    url: root.appending(path: "local.sqlite3"),
    sql:
      "CREATE TRIGGER fail_second_meal BEFORE INSERT ON outbox WHEN NEW.kind='meal' AND (SELECT COUNT(*) FROM outbox WHERE kind='meal')=1 BEGIN SELECT RAISE(ABORT,'synthetic failure'); END;"
  )
  await #expect(throws: StoreError.self) {
    try await store.applySuggestions(
      preview, selectedIDs: Set(preview.suggestions.prefix(2).map(\.id)))
  }
  #expect(try await store.entities(kind: .meal).isEmpty)
  #expect(try await store.pending().count == 1)
}
private struct RecommendationFixture: Decodable {
  struct Row: Decodable {
    let kind: EntityKind
    let id: UUID
    let revision: Int
    let payload: JSONValue
  }
  struct Case: Decodable {
    let seed: Int
    let categories: Set<String>
    let allowRepeats: Bool
    let servings: String?
    let expected: [Expected]
    enum CodingKeys: String, CodingKey {
      case seed, categories, servings, expected
      case allowRepeats = "allow_repeats"
    }
  }
  struct Expected: Decodable, Equatable {
    let recipeID: UUID
    let date: String
    let category: String
    let servings: String
    let leftoverID: UUID?
    let reasons: [String]
    enum CodingKeys: String, CodingKey {
      case recipeID = "recipe_id"
      case leftoverID = "leftover_id"
      case date, category, servings, reasons
    }
  }
  let version: Int
  let week: String
  let rows: [Row]
  let cases: [Case]
}
@Test func offlineRecommendationsMatchServerCanonicalFixture() throws {
  let url = try #require(
    Bundle.module.url(
      forResource: "recommendations-v1", withExtension: "json", subdirectory: "Fixtures"))
  let fixture = try JSONDecoder().decode(RecommendationFixture.self, from: Data(contentsOf: url))
  #expect(fixture.version == 1)
  let rows = fixture.rows.map {
    LocalEntity(
      id: $0.id, kind: $0.kind, revision: $0.revision, deleted: false, payload: $0.payload)
  }
  let snapshot = PlanningSnapshot(
    recipes: rows.filter { $0.kind == .recipe }, meals: rows.filter { $0.kind == .meal },
    leftovers: rows.filter { $0.kind == .leftover })
  for test in fixture.cases {
    let preview = try WeeklyRecommendations.generate(
      snapshot: snapshot, week: fixture.week,
      options: SuggestionOptions(
        categories: test.categories, allowRepeats: test.allowRepeats,
        servings: test.servings, seed: test.seed))
    let actual = preview.suggestions.map {
      RecommendationFixture.Expected(
        recipeID: $0.meal.recipeID, date: $0.meal.date,
        category: $0.meal.category, servings: $0.meal.servings, leftoverID: $0.meal.leftoverID,
        reasons: $0.reasons)
    }
    #expect(actual == test.expected)
  }
}

@Test func repetitionWaitsForEveryAvailableRecipeEvenWithExtremeRatingAndHistory() throws {
  let ids = [UUID(), UUID(), UUID()]
  let recipes = try ids.enumerated().map { index, id in
    var recipe = Recipe(title: "Recipe \(index)")
    recipe.rating = index == 0 ? 1 : 5
    return try row(.recipe, recipe, id: id)
  }
  var cooked = Meal(recipeID: ids[0], date: "2026-10-18", category: "dinner")
  cooked.cooked = true
  let snapshot = try PlanningSnapshot(recipes: recipes, meals: [row(.meal, cooked)])
  for seed in 0..<10 {
    let preview = try WeeklyRecommendations.generate(
      snapshot: snapshot, week: "2026-10-19",
      options: SuggestionOptions(allowRepeats: true, seed: seed))
    #expect(preview.suggestions.count == 7)
    #expect(Set(preview.suggestions.prefix(3).map { $0.meal.recipeID }).count == 3)
    #expect(Set(preview.suggestions.dropFirst(3).prefix(3).map { $0.meal.recipeID }).count == 3)
  }
}
