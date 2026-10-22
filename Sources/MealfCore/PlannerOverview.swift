import Foundation

public struct PlannerDay: Identifiable, Sendable {
  public let date: String
  public let isToday: Bool
  public let categories: Set<String>
  public let meals: [MealOccurrence]
  public var id: String { date }
}

/// A read-only projection of real local meals, shared by the Home week selector
/// and its summary. Device time zones and duplicate dishes cannot inflate slots.
public struct PlannerOverview: Sendable {
  public static let categories = ["breakfast", "lunch", "dinner"]
  public let today: String
  public let selectedDate: String
  public let monday: String
  public let days: [PlannerDay]
  public var selectedMeals: [MealOccurrence] { days.first { $0.date == selectedDate }?.meals ?? [] }
  public var plannedSlots: Int { days.reduce(0) { $0 + $1.categories.count } }
  public var totalSlots: Int { days.count * Self.categories.count }
  public var plannedDays: Int { days.filter { !$0.meals.isEmpty }.count }

  public static func build(
    meals: [LocalEntity], now: Date, timeZone: String, selectedDate: String? = nil
  ) throws -> Self {
    let today = try MealPresentation.civilDate(now, timeZone: timeZone)
    let selected = selectedDate ?? today
    let monday = try PlanningDate.monday(containing: selected)
    let sunday = try PlanningDate.adding(6, to: monday)
    let occurrences = try MealPlanning.expand(meals, from: monday, through: sunday)
    let positions = Dictionary(uniqueKeysWithValues: categories.enumerated().map { ($1, $0) })
    let days = try (0..<7).map { offset in
      let date = try PlanningDate.adding(offset, to: monday)
      let entries = occurrences.filter { $0.date == date }.sorted {
        let left = positions[$0.meal.category] ?? Int.max
        let right = positions[$1.meal.category] ?? Int.max
        return (left, $0.meal.order, $0.id) < (right, $1.meal.order, $1.id)
      }
      return PlannerDay(
        date: date, isToday: date == today,
        categories: Set(entries.map { $0.meal.category }).intersection(categories), meals: entries)
    }
    return Self(today: today, selectedDate: selected, monday: monday, days: days)
  }
}
