import Foundation
import Testing

@testable import MealfCore

private func overviewRow(_ meal: Meal, deleted: Bool = false) throws -> LocalEntity {
  LocalEntity(id: UUID(), kind: .meal, revision: 1, deleted: deleted, payload: try Codec.json(meal))
}
private let overviewInstant = ISO8601DateFormatter().date(from: "2026-10-19T00:30:00Z")!

@Test func overviewUsesHouseholdMondayAndCivilDatesAcrossDeviceBoundaries() throws {
  let west = try PlannerOverview.build(
    meals: [], now: overviewInstant, timeZone: "America/Los_Angeles")
  #expect(west.today == "2026-10-18" && west.monday == "2026-10-12")
  #expect(
    west.days.map(\.date) == (try (0..<7).map { try PlanningDate.adding($0, to: "2026-10-12") }))
  #expect(west.days.last?.isToday == true && west.totalSlots == 21)
  let east = try PlannerOverview.build(meals: [], now: overviewInstant, timeZone: "Europe/Berlin")
  #expect(east.today == "2026-10-19" && east.monday == "2026-10-19")
  #expect(east.days.first?.isToday == true)
}
@Test func overviewCountsMealSlotsWithoutDoubleCountingDishesAndIncludesLeftovers() throws {
  let id = UUID()
  var leftover = Meal(recipeID: id, date: "2026-10-19", category: "lunch")
  leftover.leftoverID = UUID()
  let rows = try [
    overviewRow(Meal(recipeID: id, date: "2026-10-19", category: "dinner")),
    overviewRow(leftover),
    overviewRow(Meal(recipeID: id, date: "2026-10-19", category: "dinner")),
    overviewRow(Meal(recipeID: id, date: "2026-10-20", category: "breakfast")),
    overviewRow(Meal(recipeID: id, date: "2026-10-19", category: "breakfast"), deleted: true),
  ]
  let value = try PlannerOverview.build(meals: rows, now: overviewInstant, timeZone: "UTC")
  #expect(value.plannedSlots == 3 && value.plannedDays == 2)
  #expect(value.selectedMeals.map { $0.meal.category } == ["lunch", "dinner", "dinner"])
  #expect(value.selectedMeals.first?.meal.leftoverID == leftover.leftoverID)
}
@Test func overviewExpandsRecurringMealsAndHonoursExceptionsAcrossYearBoundary() throws {
  var meal = Meal(recipeID: UUID(), date: "2026-12-28", category: "dinner")
  meal.recurrence = Recurrence(until: "2027-01-18", exceptions: ["2027-01-04"])
  let rows = try [overviewRow(meal)]
  let selected = try PlannerOverview.build(
    meals: rows, now: overviewInstant,
    timeZone: "UTC", selectedDate: "2027-01-11")
  #expect(selected.monday == "2027-01-11" && selected.selectedMeals.count == 1)
  #expect(selected.days.allSatisfy { !$0.isToday })
  let skipped = try PlannerOverview.build(
    meals: rows, now: overviewInstant,
    timeZone: "UTC", selectedDate: "2027-01-04")
  #expect(skipped.selectedMeals.isEmpty && skipped.plannedSlots == 0)
}
@Test func overviewRejectsInvalidDatesAndZonesInsteadOfDisplayingInventedState() throws {
  #expect(throws: (any Error).self) {
    try PlannerOverview.build(meals: [], now: overviewInstant, timeZone: "Not/AZone")
  }
  #expect(throws: (any Error).self) {
    try PlannerOverview.build(
      meals: [], now: overviewInstant, timeZone: "UTC", selectedDate: "2026-02-31")
  }
}
