import Foundation
import Testing

@testable import AirCookerCore

private func mealRow(_ meal: Meal, id: UUID = UUID()) throws -> LocalEntity {
  LocalEntity(id: id, kind: .meal, revision: 1, deleted: false, payload: try Codec.json(meal))
}
@Test func civilDatesStayStableAcrossDSTAndYearBoundaries() throws {
  #expect(try PlanningDate.adding(7, to: "2026-10-19") == "2026-10-26")
  #expect(try PlanningDate.monday(containing: "2027-01-01") == "2026-12-28")
  #expect(try PlanningDate.adding(1, to: "2028-02-28") == "2028-02-29")
  #expect(throws: PlanningError.self) { try PlanningDate.parse("2026-02-29") }
  #expect(throws: PlanningError.self) { try PlanningDate.parse("2026-2-01") }
}
@Test func recurrenceHonoursIntervalEndAndExceptions() throws {
  var meal = Meal(recipeID: UUID(), date: "2026-10-19", category: "dinner")
  meal.recurrence = Recurrence(intervalWeeks: 2, until: "2026-12-14", exceptions: ["2026-11-02"])
  #expect(
    try MealPlanning.occurrences(meal, from: "2026-10-20", through: "2026-12-31") == [
      "2026-11-16", "2026-11-30", "2026-12-14",
    ])
  #expect(throws: PlanningError.self) {
    try MealPlanning.occurrences(meal, from: "2026-01-01", through: "2028-01-01")
  }
  meal.recurrence?.intervalWeeks = 0
  #expect(throws: PlanningError.self) {
    try MealPlanning.occurrences(meal, from: "2026-10-19", through: "2026-10-25")
  }
}
@Test func movingRecurringOccurrencePreservesSeriesAndDetachesOnlyThatDate() throws {
  var meal = Meal(recipeID: UUID(), date: "2026-10-19", category: "dinner")
  meal.recurrence = Recurrence(until: "2026-11-30")
  let row = try mealRow(meal)
  let occurrence = try #require(
    MealPlanning.expand([row], from: "2026-10-26", through: "2026-11-01").first)
  let edits = try MealPlanning.moveOccurrence(occurrence, to: "2026-10-28", category: "lunch")
  #expect(edits.count == 2 && edits[0].id == row.id && edits[1].id != row.id)
  let master = try JSONDecoder().decode(Meal.self, from: JSONEncoder().encode(edits[0].payload))
  let detached = try JSONDecoder().decode(Meal.self, from: JSONEncoder().encode(edits[1].payload))
  #expect(master.date == "2026-10-19" && master.recurrence?.exceptions == ["2026-10-26"])
  #expect(detached.date == "2026-10-28" && detached.recurrence == nil)
  #expect(
    try MealPlanning.occurrences(master, from: "2026-10-19", through: "2026-11-02") == [
      "2026-10-19", "2026-11-02",
    ])
}
@Test func copyingWeekMakesIndependentUncookedMealsWithoutInfiniteSeries() throws {
  var meal = Meal(recipeID: UUID(), date: "2026-10-19", category: "dinner")
  meal.cooked = true
  meal.recurrence = Recurrence(until: "2026-12-31")
  let edits = try MealPlanning.copy(
    [mealRow(meal)], from: "2026-10-26", through: "2026-11-01", to: "2026-11-02")
  #expect(edits.count == 1)
  let copied = try JSONDecoder().decode(Meal.self, from: JSONEncoder().encode(edits[0].payload))
  #expect(copied.date == "2026-11-02" && !copied.cooked && copied.recurrence == nil)
  meal.leftoverID = UUID()
  meal.recurrence = nil
  #expect(throws: PlanningError.self) {
    try MealPlanning.copy(
      [mealRow(meal)], from: "2026-10-19", through: "2026-10-25", to: "2026-10-26")
  }
}
@Test func templatesPreserveWeekdaysAndRequireAvailableRecipes() throws {
  let recipe = UUID()
  let meal = Meal(recipeID: recipe, date: "2026-10-25", category: "breakfast", servings: "3.5")
  let template = try MealPlanning.template(name: "Week", rows: [mealRow(meal)], week: "2026-10-19")
  #expect(template.meals[0].weekday == 6)
  let edits = try MealPlanning.apply(template, week: "2026-12-28", availableRecipes: [recipe])
  let applied = try JSONDecoder().decode(Meal.self, from: JSONEncoder().encode(edits[0].payload))
  #expect(applied.date == "2027-01-03" && applied.servings == "3.5")
  #expect(throws: PlanningError.self) {
    try MealPlanning.apply(template, week: "2026-12-28", availableRecipes: [])
  }
  #expect(throws: PlanningError.self) {
    try MealPlanning.apply(template, week: "2026-12-29", availableRecipes: [recipe])
  }
}
@Test func batchCopyAndOutboxRollBackTogetherOnFailure() async throws {
  let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let url = directory.appending(path: "local.sqlite3")
  let store = try LocalStore(url: url)
  let meal = Meal(recipeID: UUID(), date: "2026-10-19", category: "dinner")
  let id = UUID()
  let edits = [
    try LocalEdit(kind: .meal, id: id, value: meal),
    try LocalEdit(kind: .meal, id: id, value: meal),
  ]
  // Force the second write to fail after the first entity and outbox record were inserted.
  try executeTestSQL(
    url: url,
    sql:
      "CREATE TRIGGER fail_second BEFORE INSERT ON outbox WHEN (SELECT COUNT(*) FROM outbox)=1 BEGIN SELECT RAISE(ABORT,'synthetic failure'); END;"
  )
  await #expect(throws: StoreError.self) { try await store.saveBatch(edits) }
  #expect(try await store.entities(kind: .meal).isEmpty)
  #expect(try await store.pending().isEmpty)
  try executeTestSQL(url: url, sql: "DROP TRIGGER fail_second")
  try await store.saveBatch(edits)
  let reopened = try LocalStore(url: url)
  #expect(try await reopened.pending().count == 2)
  #expect(try await reopened.entities(kind: .meal).count == 1)
}
