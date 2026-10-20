import Foundation

public enum PlanningError: Error, Sendable {
  case invalidDate, invalidWindow, invalidRecurrence, unavailableRecipe, invalidTemplate
  case leftoverCannotBeCopied, tooManyChanges
}

// Planning dates are civil dates. Arithmetic uses a fixed Gregorian UTC calendar;
// the household time zone is used only when converting an absolute instant to a date.
public enum PlanningDate {
  private static var calendar: Calendar {
    var result = Calendar(identifier: .gregorian)
    result.timeZone = TimeZone(secondsFromGMT: 0)!
    result.locale = Locale(identifier: "en_US_POSIX")
    return result
  }
  public static func parse(_ text: String) throws -> Date {
    let parts = text.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
      let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
      (1...9999).contains(year),
      let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
      string(date) == text
    else { throw PlanningError.invalidDate }
    return date
  }
  public static func string(_ date: Date) -> String {
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
  }
  public static func adding(_ days: Int, to text: String) throws -> String {
    guard let result = calendar.date(byAdding: .day, value: days, to: try parse(text)) else {
      throw PlanningError.invalidDate
    }
    let value = string(result)
    _ = try parse(value)
    return value
  }
  public static func distance(from start: String, to end: String) throws -> Int {
    calendar.dateComponents([.day], from: try parse(start), to: try parse(end)).day!
  }
  public static func monday(containing text: String) throws -> String {
    let weekday = calendar.component(.weekday, from: try parse(text))
    return try adding(-((weekday + 5) % 7), to: text)
  }
}

public struct Recurrence: Codable, Sendable, Equatable {
  public var intervalWeeks: Int
  public var until: String
  public var exceptions: [String]
  public init(intervalWeeks: Int = 1, until: String, exceptions: [String] = []) {
    self.intervalWeeks = intervalWeeks
    self.until = until
    self.exceptions = exceptions
  }
  enum CodingKeys: String, CodingKey {
    case intervalWeeks = "interval_weeks"
    case until, exceptions
  }
}
public struct TemplateSlot: Codable, Sendable {
  public var weekday: Int
  public var category: String
  public var recipeID: UUID
  public var servings: String
  public init(weekday: Int, category: String, recipeID: UUID, servings: String) {
    self.weekday = weekday
    self.category = category
    self.recipeID = recipeID
    self.servings = servings
  }
  enum CodingKeys: String, CodingKey {
    case weekday, category, servings
    case recipeID = "recipe_id"
  }
}
public struct MealTemplate: Codable, Sendable {
  public var name: String
  public var meals: [TemplateSlot]
  public init(name: String, meals: [TemplateSlot]) {
    self.name = name
    self.meals = meals
  }
}
public struct MealOccurrence: Identifiable, Sendable {
  public let entityID: UUID
  public let date: String
  public let meal: Meal
  public var id: String { entityID.uuidString + ":" + date }
}
public struct LocalEdit: Sendable {
  public let kind: EntityKind
  public let id: UUID
  public let payload: JSONValue
  public let deleted: Bool
  public init<T: Encodable>(kind: EntityKind, id: UUID = UUID(), value: T, deleted: Bool = false)
    throws
  {
    self.kind = kind
    self.id = id
    self.payload = try Codec.json(value)
    self.deleted = deleted
  }
}

public enum MealPlanning {
  public static func occurrences(_ meal: Meal, from start: String, through end: String) throws
    -> [String]
  {
    let window = try PlanningDate.distance(from: start, to: end)
    guard (0...366).contains(window) else { throw PlanningError.invalidWindow }
    _ = try PlanningDate.parse(meal.date)
    guard let rule = meal.recurrence else {
      return start <= meal.date && meal.date <= end ? [meal.date] : []
    }
    let duration = try PlanningDate.distance(from: meal.date, to: rule.until)
    guard (1...52).contains(rule.intervalWeeks), (0...3660).contains(duration),
      rule.exceptions.count <= 520
    else { throw PlanningError.invalidRecurrence }
    for exception in rule.exceptions { _ = try PlanningDate.parse(exception) }
    let step = 7 * rule.intervalWeeks
    let elapsed = try PlanningDate.distance(from: meal.date, to: start)
    let offset = max(0, (elapsed + step - 1) / step)
    var current = try PlanningDate.adding(offset * step, to: meal.date)
    var result: [String] = []
    let last = min(end, rule.until)
    while current <= last {
      if !rule.exceptions.contains(current) { result.append(current) }
      if try PlanningDate.distance(from: current, to: last) < step { break }
      current = try PlanningDate.adding(step, to: current)
    }
    return result
  }
  public static func expand(_ rows: [LocalEntity], from start: String, through end: String) throws
    -> [MealOccurrence]
  {
    try rows.filter { !$0.deleted && $0.kind == .meal }.flatMap { row in
      let meal = try row.decode(Meal.self)
      return try occurrences(meal, from: start, through: end).map {
        MealOccurrence(entityID: row.id, date: $0, meal: meal)
      }
    }.sorted { ($0.date, $0.meal.order, $0.id) < ($1.date, $1.meal.order, $1.id) }
  }
  public static func removeOccurrence(_ item: MealOccurrence) throws -> LocalEdit {
    var meal = item.meal
    guard var rule = meal.recurrence else {
      return try LocalEdit(kind: .meal, id: item.entityID, value: meal, deleted: true)
    }
    guard rule.exceptions.count < 520 else { throw PlanningError.invalidRecurrence }
    rule.exceptions = Array(Set(rule.exceptions + [item.date])).sorted()
    meal.recurrence = rule
    return try LocalEdit(kind: .meal, id: item.entityID, value: meal)
  }
  public static func moveOccurrence(_ item: MealOccurrence, to date: String, category: String)
    throws
    -> [LocalEdit]
  {
    _ = try PlanningDate.parse(date)
    guard ["breakfast", "lunch", "dinner"].contains(category) else {
      throw PlanningError.invalidTemplate
    }
    var moved = item.meal
    moved.date = date
    moved.category = category
    moved.recurrence = nil
    if item.meal.recurrence == nil {
      return [try LocalEdit(kind: .meal, id: item.entityID, value: moved)]
    }
    // An exception and its detached replacement share one local transaction.
    return [try removeOccurrence(item), try LocalEdit(kind: .meal, value: moved)]
  }
  public static func copy(
    _ rows: [LocalEntity], from start: String, through end: String,
    to destination: String
  ) throws -> [LocalEdit] {
    _ = try PlanningDate.parse(destination)
    let items = try expand(rows, from: start, through: end)
    guard items.count <= 100 else { throw PlanningError.tooManyChanges }
    return try items.map { item in
      guard item.meal.leftoverID == nil else { throw PlanningError.leftoverCannotBeCopied }
      var meal = item.meal
      let offset = try PlanningDate.distance(from: start, to: item.date)
      meal.date = try PlanningDate.adding(offset, to: destination)
      meal.recurrence = nil
      meal.cooked = false
      return try LocalEdit(kind: .meal, value: meal)
    }
  }
  public static func template(name: String, rows: [LocalEntity], week: String) throws
    -> MealTemplate
  {
    guard name.count <= 200, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      try PlanningDate.monday(containing: week) == week
    else { throw PlanningError.invalidTemplate }
    let items = try expand(rows, from: week, through: PlanningDate.adding(6, to: week))
    guard items.count <= 100 else { throw PlanningError.tooManyChanges }
    let slots = try items.map { item in
      guard item.meal.leftoverID == nil else { throw PlanningError.leftoverCannotBeCopied }
      return try TemplateSlot(
        weekday: PlanningDate.distance(from: week, to: item.date),
        category: item.meal.category, recipeID: item.meal.recipeID, servings: item.meal.servings)
    }
    return MealTemplate(name: name, meals: slots)
  }
  public static func apply(_ template: MealTemplate, week: String, availableRecipes: Set<UUID>)
    throws
    -> [LocalEdit]
  {
    guard template.meals.count <= 100, try PlanningDate.monday(containing: week) == week else {
      throw PlanningError.invalidTemplate
    }
    return try template.meals.map { slot in
      guard availableRecipes.contains(slot.recipeID) else { throw PlanningError.unavailableRecipe }
      guard (0...6).contains(slot.weekday),
        ["breakfast", "lunch", "dinner"].contains(slot.category),
        let servings = Decimal(string: slot.servings), servings > 0, servings <= 1_000_000
      else { throw PlanningError.invalidTemplate }
      return try LocalEdit(
        kind: .meal,
        value: Meal(
          recipeID: slot.recipeID,
          date: PlanningDate.adding(slot.weekday, to: week), category: slot.category,
          servings: slot.servings))
    }
  }
}
