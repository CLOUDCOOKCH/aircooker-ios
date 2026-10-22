import Foundation

public enum PresentationError: Error, Sendable { case invalidPreferences, invalidSnapshot }
public enum AppDestination: Equatable, Sendable, Identifiable {
  case calendar(date: String)
  case recipe(id: UUID)
  case meal(id: UUID, date: String)
  public var id: String { url.absoluteString }
  public var url: URL {
    var c = URLComponents()
    c.scheme = "mealf"
    switch self {
    case .calendar(let date):
      c.host = "calendar"
      c.queryItems = [URLQueryItem(name: "date", value: date)]
    case .recipe(let id):
      c.host = "recipe"
      c.path = "/" + id.uuidString
    case .meal(let id, let date):
      c.host = "meal"
      c.path = "/" + id.uuidString
      c.queryItems = [URLQueryItem(name: "date", value: date)]
    }
    return c.url!
  }
  public init?(url: URL) {
    guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
      c.scheme?.lowercased() == "mealf",
      c.user == nil, c.password == nil, c.port == nil, c.fragment == nil
    else { return nil }
    let items = c.queryItems ?? []
    switch c.host?.lowercased() {
    case "calendar":
      guard c.path.isEmpty || c.path == "/", items.count == 1, items[0].name == "date",
        let date = items[0].value, (try? PlanningDate.parse(date)) != nil
      else { return nil }
      self = .calendar(date: date)
    case "recipe", "meal":
      guard c.path.count == 37, c.path.first == "/",
        let id = UUID(uuidString: String(c.path.dropFirst()))
      else { return nil }
      if c.host?.lowercased() == "recipe" {
        guard items.isEmpty else { return nil }
        self = .recipe(id: id)
      } else {
        guard items.count == 1, items[0].name == "date", let date = items[0].value,
          (try? PlanningDate.parse(date)) != nil
        else { return nil }
        self = .meal(id: id, date: date)
      }
    default: return nil
    }
  }
}
public struct ReminderTime: Codable, Sendable, Equatable {
  public var hour: Int
  public var minute: Int
  public init(hour: Int, minute: Int = 0) {
    self.hour = hour
    self.minute = minute
  }
}
public struct ReminderPreferences: Codable, Sendable {
  public var enabled = false
  public var showRecipeNames = false
  public var times: [String: ReminderTime] = [
    "breakfast": ReminderTime(hour: 8), "lunch": ReminderTime(hour: 12),
    "dinner": ReminderTime(hour: 18),
  ]
  public init() {}
}
public struct PlannedReminder: Identifiable, Sendable {
  public let id: String
  public let fireDate: Date
  public let date: String
  public let category: String
  public let time: ReminderTime
  public let timeZone: String
  public let destination: AppDestination
  public let recipeTitles: [String]
}
public enum MealPresentation {
  public static func civilDate(_ instant: Date, timeZone: String) throws -> String {
    guard let zone = TimeZone(identifier: timeZone), instant.timeIntervalSince1970.isFinite,
      (-62_135_596_800...253_402_300_799).contains(instant.timeIntervalSince1970)
    else {
      throw PresentationError.invalidPreferences
    }
    var c = Calendar(identifier: .gregorian)
    c.timeZone = zone
    let parts = c.dateComponents([.year, .month, .day], from: instant)
    guard let year = parts.year, let month = parts.month, let day = parts.day,
      (1...9999).contains(year)
    else { throw PresentationError.invalidPreferences }
    return String(format: "%04d-%02d-%02d", year, month, day)
  }
  public static func startOfDay(_ date: String, timeZone: String) throws -> Date {
    _ = try PlanningDate.parse(date)
    guard let zone = TimeZone(identifier: timeZone) else {
      throw PresentationError.invalidPreferences
    }
    let parts = date.split(separator: "-").compactMap { Int($0) }
    var c = Calendar(identifier: .gregorian)
    c.timeZone = zone
    guard
      let instant = c.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
      try civilDate(instant, timeZone: timeZone) == date
    else { throw PresentationError.invalidPreferences }
    return c.startOfDay(for: instant)
  }
  public static func reminders(
    snapshot: PlanningSnapshot, preferences: ReminderPreferences,
    timeZone: String, now: Date, limit: Int = 50
  ) throws -> [PlannedReminder] {
    guard preferences.enabled else { return [] }
    guard let zone = TimeZone(identifier: timeZone), (1...50).contains(limit),
      preferences.times.keys.allSatisfy({ ["breakfast", "lunch", "dinner"].contains($0) }),
      preferences.times.values.allSatisfy({
        (0...23).contains($0.hour) && (0...59).contains($0.minute)
      })
    else { throw PresentationError.invalidPreferences }
    let today = try civilDate(now, timeZone: timeZone)
    let end = try PlanningDate.adding(27, to: today)
    let items = try MealPlanning.expand(snapshot.meals, from: today, through: end).filter {
      !$0.meal.cooked
    }
    let groups = Dictionary(grouping: items) { $0.date + ":" + $0.meal.category }
    let recipes = try Dictionary(
      uniqueKeysWithValues: snapshot.recipes.filter { !$0.deleted }.map {
        ($0.id, try $0.decode(Recipe.self))
      })
    var c = Calendar(identifier: .gregorian)
    c.timeZone = zone
    var result: [PlannedReminder] = []
    for (key, group) in groups {
      guard let first = group.first, let time = preferences.times[first.meal.category] else {
        continue
      }
      let midnight = try startOfDay(first.date, timeZone: timeZone)
      // Spring gaps advance to the next real time; autumn repeats use the first instance.
      guard
        let fireDate = c.nextDate(
          after: midnight.addingTimeInterval(-1),
          matching: DateComponents(hour: time.hour, minute: time.minute, second: 0),
          matchingPolicy: .nextTime, repeatedTimePolicy: .first),
        fireDate > now, try civilDate(fireDate, timeZone: timeZone) == first.date
      else { continue }
      let destination: AppDestination =
        group.count == 1 ? .meal(id: first.entityID, date: first.date) : .calendar(date: first.date)
      result.append(
        PlannedReminder(
          id: "mealf.meal." + key, fireDate: fireDate,
          date: first.date, category: first.meal.category, time: time, timeZone: timeZone,
          destination: destination,
          recipeTitles: group.compactMap { recipes[$0.meal.recipeID]?.title }))
    }
    return Array(result.sorted { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }.prefix(limit))
  }
}
public struct WidgetMeal: Codable, Identifiable, Sendable {
  public let entityID: UUID
  public let recipeID: UUID
  public let date: String
  public let title: String?
  public var id: String { entityID.uuidString + ":" + date }
  public var destination: AppDestination { .meal(id: entityID, date: date) }
}
public struct WidgetSlot: Codable, Identifiable, Sendable {
  public let category: String
  public let meals: [WidgetMeal]
  public let additionalCount: Int
  public var id: String { category }
}
public struct WidgetDay: Codable, Sendable {
  public let date: String
  public let slots: [WidgetSlot]
}
public struct MealWidgetSnapshot: Codable, Sendable {
  public let version: Int
  public let timeZone: String
  public let generatedAt: Date
  public let days: [WidgetDay]
  public static func build(
    snapshot: PlanningSnapshot, timeZone: String, now: Date,
    showNames: Bool = true
  ) throws -> MealWidgetSnapshot {
    let today = try MealPresentation.civilDate(now, timeZone: timeZone)
    let end = try PlanningDate.adding(13, to: today)
    let items = try MealPlanning.expand(snapshot.meals, from: today, through: end)
    let recipes = try Dictionary(
      uniqueKeysWithValues: snapshot.recipes.filter { !$0.deleted }.map {
        ($0.id, try $0.decode(Recipe.self))
      })
    let days = try (0..<14).map { offset in
      let day = try PlanningDate.adding(offset, to: today)
      let slots = ["breakfast", "lunch", "dinner"].map { category in
        let entries = items.filter { $0.date == day && $0.meal.category == category }
        return WidgetSlot(
          category: category,
          meals: entries.prefix(3).map {
            WidgetMeal(
              entityID: $0.entityID, recipeID: $0.meal.recipeID, date: day,
              title: showNames ? recipes[$0.meal.recipeID]?.title : nil)
          }, additionalCount: max(0, entries.count - 3))
      }
      return WidgetDay(date: day, slots: slots)
    }
    return MealWidgetSnapshot(version: 1, timeZone: timeZone, generatedAt: now, days: days)
  }
  public func day(at instant: Date) -> WidgetDay? {
    guard let day = try? MealPresentation.civilDate(instant, timeZone: timeZone) else { return nil }
    return days.first { $0.date == day }
  }
  public func timelineDates(after instant: Date) throws -> [Date] {
    guard let last = days.last else { return [instant] }
    let dates = days.map(\.date) + [try PlanningDate.adding(1, to: last.date)]
    return [instant]
      + (try dates.map { try MealPresentation.startOfDay($0, timeZone: timeZone) }.filter {
        $0 > instant
      })
  }
  public static func decode(_ data: Data) throws -> MealWidgetSnapshot {
    guard data.count <= 1_048_576 else { throw PresentationError.invalidSnapshot }
    let value = try JSONDecoder().decode(Self.self, from: data)
    guard value.version == 1, TimeZone(identifier: value.timeZone) != nil, value.days.count == 14
    else { throw PresentationError.invalidSnapshot }
    let start = try MealPresentation.civilDate(value.generatedAt, timeZone: value.timeZone)
    for (offset, day) in value.days.enumerated() {
      guard day.date == (try PlanningDate.adding(offset, to: start)),
        day.slots.map(\.category) == ["breakfast", "lunch", "dinner"]
      else { throw PresentationError.invalidSnapshot }
      for slot in day.slots {
        guard slot.meals.count <= 3, slot.additionalCount >= 0,
          slot.additionalCount <= Int.max - 3,
          Set(slot.meals.map(\.id)).count == slot.meals.count,
          slot.meals.allSatisfy({ $0.date == day.date && ($0.title?.count ?? 0) <= 200 })
        else { throw PresentationError.invalidSnapshot }
      }
    }
    return value
  }
}
