import Foundation

public enum LeftoverError: Error, Sendable {
  case invalidPortions, insufficientPortions, notProduced, discarded, recipeInUse, inUse,
    unavailable
}
public enum PortionQuantity {
  public static func parse(_ text: String, allowZero: Bool = false) throws -> Decimal {
    guard
      text.range(of: #"^[0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$"#, options: .regularExpression)
        != nil,
      let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")),
      !value.isNaN, value >= 0, allowZero || value > 0, value <= 1_000_000
    else { throw LeftoverError.invalidPortions }
    return value
  }
}
public struct Leftover: Codable, Sendable {
  public var recipeID: UUID
  public var portions: String
  public var producedOn: String
  public var discarded: Bool
  public init(recipeID: UUID, portions: String, producedOn: String, discarded: Bool = false) {
    self.recipeID = recipeID
    self.portions = portions
    self.producedOn = producedOn
    self.discarded = discarded
  }
  enum CodingKeys: String, CodingKey {
    case recipeID = "recipe_id"
    case producedOn = "produced_on"
    case portions, discarded
  }
}
public enum LeftoverPlanning {
  public static func allocated(id: UUID, meals: [LocalEntity], excluding: UUID? = nil) throws
    -> Decimal
  {
    try meals.filter { $0.kind == .meal && !$0.deleted && $0.id != excluding }.reduce(Decimal(0)) {
      sum, row in
      let meal = try row.decode(Meal.self)
      return try sum + (meal.leftoverID == id ? PortionQuantity.parse(meal.servings) : 0)
    }
  }
  public static func available(id: UUID, leftover: Leftover, meals: [LocalEntity]) throws -> Decimal
  {
    if leftover.discarded { return 0 }
    return try max(0, PortionQuantity.parse(leftover.portions) - allocated(id: id, meals: meals))
  }
  public static func validate(id: UUID, leftover: Leftover, meals: [LocalEntity]) throws {
    let total = try PortionQuantity.parse(leftover.portions)
    _ = try PlanningDate.parse(leftover.producedOn)
    let booked = try meals.filter { !$0.deleted && $0.kind == .meal }.map {
      try $0.decode(Meal.self)
    }
    .filter { $0.leftoverID == id }
    guard booked.allSatisfy({ $0.recipeID == leftover.recipeID }) else {
      throw LeftoverError.recipeInUse
    }
    guard booked.allSatisfy({ $0.date >= leftover.producedOn }) else {
      throw LeftoverError.notProduced
    }
    guard try allocated(id: id, meals: meals) <= total else {
      throw LeftoverError.insufficientPortions
    }
  }
  public static func validateBooking(
    _ meal: Meal, id: UUID, leftover: Leftover,
    meals: [LocalEntity], replacing: UUID? = nil
  ) throws {
    _ = try PlanningDate.parse(meal.date)
    guard meal.recipeID == leftover.recipeID, meal.recurrence == nil,
      ["breakfast", "lunch", "dinner"].contains(meal.category)
    else { throw LeftoverError.unavailable }
    guard meal.date >= leftover.producedOn else { throw LeftoverError.notProduced }
    let amount = try PortionQuantity.parse(meal.servings)
    if leftover.discarded {
      let old = try meals.first(where: { $0.id == replacing && !$0.deleted })?.decode(Meal.self)
      guard let old, old.leftoverID == id, try amount <= PortionQuantity.parse(old.servings) else {
        throw LeftoverError.discarded
      }
    }
    guard
      try allocated(id: id, meals: meals, excluding: replacing) + amount
        <= PortionQuantity.parse(leftover.portions)
    else {
      throw LeftoverError.insufficientPortions
    }
  }
}
extension MealPlanning {
  public static func setCooked(_ item: MealOccurrence, cooked: Bool) throws -> [LocalEdit] {
    var changes = try moveOccurrence(item, to: item.date, category: item.meal.category)
    let last = changes.removeLast()
    var meal = try JSONDecoder().decode(Meal.self, from: JSONEncoder().encode(last.payload))
    meal.cooked = cooked
    changes.append(try LocalEdit(kind: .meal, id: last.id, value: meal))
    return changes
  }
}
