import Foundation
import Testing

@testable import AirCookerCore

private func instant(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
private func snapshot(_ meals: [Meal]) throws -> PlanningSnapshot {
  try PlanningSnapshot(
    recipes: [],
    meals: meals.map {
      LocalEntity(id: UUID(), kind: .meal, revision: 1, deleted: false, payload: try Codec.json($0))
    })
}
@Test func deepLinksRoundTripAndRejectUnsupportedInputs() throws {
  let id = UUID()
  for value in [
    AppDestination.meal(id: id, date: "2026-10-20"), .calendar(date: "2026-10-20"), .recipe(id: id),
  ] {
    #expect(AppDestination(url: value.url) == value)
  }
  for raw in [
    "https://meal/" + id.uuidString, "aircooker://recipe/../settings",
    "aircooker://calendar?date=2026-02-31", "aircooker://calendar?date=2026-10-20&date=2026-10-21",
    "aircooker://calendar?date=2026-10-20&token=x",
    "aircooker://user:password@calendar?date=2026-10-20",
    "aircooker://recipe/" + id.uuidString + "#delete",
  ] {
    #expect(AppDestination(url: URL(string: raw)!) == nil)
  }
}
@Test func remindersUseHouseholdDatesAndSkipCookedMeals() throws {
  let rid = UUID()
  let meal = Meal(recipeID: rid, date: "2026-10-20", category: "dinner")
  var cooked = Meal(recipeID: rid, date: "2026-10-21", category: "dinner")
  cooked.cooked = true
  var preferences = ReminderPreferences()
  preferences.enabled = true
  let result = try MealPresentation.reminders(
    snapshot: snapshot([meal, cooked]), preferences: preferences,
    timeZone: "America/Los_Angeles", now: instant("2026-10-21T00:00:00Z"))
  #expect(result.count == 1 && result[0].date == "2026-10-20")
  #expect(result[0].fireDate == instant("2026-10-21T01:00:00Z"))
}
@Test func reminderTimesHandleDSTGapsAndRepeatedHours() throws {
  var preferences = ReminderPreferences()
  preferences.enabled = true
  preferences.times = ["breakfast": ReminderTime(hour: 2, minute: 30)]
  let spring = Meal(recipeID: UUID(), date: "2026-03-29", category: "breakfast")
  let first = try MealPresentation.reminders(
    snapshot: snapshot([spring]), preferences: preferences,
    timeZone: "Europe/Zurich", now: instant("2026-03-28T12:00:00Z"))
  #expect(first.first?.fireDate == instant("2026-03-29T01:00:00Z"))
  let autumn = Meal(recipeID: UUID(), date: "2026-10-25", category: "breakfast")
  let second = try MealPresentation.reminders(
    snapshot: snapshot([autumn]), preferences: preferences,
    timeZone: "Europe/Zurich", now: instant("2026-10-24T12:00:00Z"))
  #expect(second.first?.fireDate == instant("2026-10-25T00:30:00Z"))
}
@Test func recurrenceRemindersGroupSlotsAndKeepEarliestFifty() throws {
  var meals: [Meal] = []
  for category in ["breakfast", "lunch", "dinner"] {
    for offset in 0..<7 {
      var meal = Meal(
        recipeID: UUID(), date: try PlanningDate.adding(offset, to: "2026-10-19"),
        category: category)
      meal.recurrence = Recurrence(until: "2026-12-31")
      meals.append(meal)
    }
  }
  meals.append(meals[0])
  var preferences = ReminderPreferences()
  preferences.enabled = true
  let reminders = try MealPresentation.reminders(
    snapshot: snapshot(meals), preferences: preferences,
    timeZone: "UTC", now: instant("2026-10-19T00:00:00Z"))
  #expect(reminders.count == 50 && Set(reminders.map(\.id)).count == 50)
  #expect(reminders[0].fireDate == instant("2026-10-19T08:00:00Z"))
  #expect(reminders[0].destination == .calendar(date: "2026-10-19"))
  #expect(reminders.last!.fireDate >= reminders[0].fireDate)
  preferences.enabled = false
  #expect(
    try MealPresentation.reminders(
      snapshot: snapshot(meals), preferences: preferences, timeZone: "UTC", now: Date()
    ).isEmpty)
}
@Test func widgetCacheRollsOverOfflineAndExpiresWithoutShowingOldMeals() throws {
  var meal = Meal(recipeID: UUID(), date: "2026-10-19", category: "dinner")
  meal.recurrence = Recurrence(until: "2026-12-31")
  let widget = try MealWidgetSnapshot.build(
    snapshot: snapshot([meal]), timeZone: "Europe/Zurich", now: instant("2026-10-19T12:00:00Z"))
  let decoded = try MealWidgetSnapshot.decode(JSONEncoder().encode(widget))
  #expect(decoded.day(at: instant("2026-10-20T12:00:00Z"))?.slots[2].meals.isEmpty == true)
  #expect(decoded.day(at: instant("2026-10-26T12:00:00Z"))?.slots[2].meals.count == 1)
  #expect(decoded.day(at: instant("2026-11-02T12:00:00Z")) == nil)
  let dates = try decoded.timelineDates(after: instant("2026-10-24T12:00:00Z"))
  #expect(dates.contains(instant("2026-10-25T23:00:00Z")))
}
@Test func widgetCacheRejectsUnsupportedVersionsAndHonoursNamePrivacy() throws {
  var recipe = Recipe()
  recipe.title = "Private soup"
  let rid = UUID()
  let meal = Meal(recipeID: rid, date: "2026-10-20", category: "dinner")
  let data = try PlanningSnapshot(
    recipes: [
      LocalEntity(id: rid, kind: .recipe, revision: 1, deleted: false, payload: Codec.json(recipe))
    ], meals: snapshot([meal]).meals)
  let widget = try MealWidgetSnapshot.build(
    snapshot: data, timeZone: "UTC", now: instant("2026-10-20T00:00:00Z"), showNames: false)
  #expect(widget.days[0].slots[2].meals[0].title == nil)
  let raw = try JSONEncoder().encode(widget)
  #expect(!String(decoding: raw, as: UTF8.self).contains(recipe.title))
  #expect(throws: PresentationError.self) {
    try MealPresentation.civilDate(Date(timeIntervalSince1970: 1e100), timeZone: "UTC")
  }
  var corrupt = try #require(JSONSerialization.jsonObject(with: raw) as? [String: Any])
  var days = try #require(corrupt["days"] as? [[String: Any]])
  var slots = try #require(days[0]["slots"] as? [[String: Any]])
  slots[0]["additionalCount"] = Int.max
  days[0]["slots"] = slots
  corrupt["days"] = days
  #expect(throws: PresentationError.self) {
    try MealWidgetSnapshot.decode(JSONSerialization.data(withJSONObject: corrupt))
  }
  var object = try #require(JSONSerialization.jsonObject(with: raw) as? [String: Any])
  object["version"] = 999
  #expect(throws: PresentationError.self) {
    try MealWidgetSnapshot.decode(JSONSerialization.data(withJSONObject: object))
  }
}
