import Foundation

public enum SuggestionError: Error, Sendable { case invalidOptions, stalePreview }
public struct PlanningSnapshot: Sendable {
  public let recipes: [LocalEntity]
  public let meals: [LocalEntity]
  public let leftovers: [LocalEntity]
  public init(recipes: [LocalEntity], meals: [LocalEntity], leftovers: [LocalEntity] = []) {
    self.recipes = recipes
    self.meals = meals
    self.leftovers = leftovers
  }
  public func basis() throws -> Data {
    let rows = (recipes + meals + leftovers).sorted {
      ($0.kind.rawValue, $0.id.uuidString) < ($1.kind.rawValue, $1.id.uuidString)
    }.map { row in
      JSONValue.object([
        "kind": .string(row.kind.rawValue), "id": .string(row.id.uuidString),
        "revision": .string(String(row.revision)), "deleted": .bool(row.deleted),
        "payload": row.payload,
      ])
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(rows)
  }
}
public struct SuggestionOptions: Sendable {
  public var categories: Set<String>
  public var allowRepeats: Bool
  public var servings: String?
  public var seed: Int
  public init(
    categories: Set<String> = ["dinner"], allowRepeats: Bool = false,
    servings: String? = nil, seed: Int = 0
  ) {
    self.categories = categories
    self.allowRepeats = allowRepeats
    self.servings = servings
    self.seed = seed
  }
}
public struct SuggestedMeal: Identifiable, Sendable {
  public let meal: Meal
  public let reasons: [String]
  public var id: String {
    "\(meal.date):\(meal.category):\(meal.recipeID.uuidString):\(meal.leftoverID?.uuidString ?? "new")"
  }
}
public struct WeeklyPreview: Sendable {
  public let monday: String
  public let basis: Data
  public let suggestions: [SuggestedMeal]
}
public enum WeeklyRecommendations {
  private static func tie(seed: Int, day: String, category: String, recipe: UUID) -> Int {
    var value: UInt64 = 14_695_981_039_346_656_037
    for byte in "\(seed):\(day):\(category):\(recipe.uuidString.lowercased())".utf8 {
      value = (value ^ UInt64(byte)) &* 1_099_511_628_211
    }
    return Int(value % 10)
  }
  public static func generate(
    snapshot: PlanningSnapshot, week: String,
    options: SuggestionOptions = SuggestionOptions()
  ) throws -> WeeklyPreview {
    let categories = ["breakfast", "lunch", "dinner"].filter { options.categories.contains($0) }
    guard !categories.isEmpty, categories.count == options.categories.count,
      (0...2_147_483_647).contains(options.seed), try PlanningDate.monday(containing: week) == week
    else {
      throw SuggestionError.invalidOptions
    }
    let servings = try options.servings.map { try PortionQuantity.parse($0) }
    if let servings, servings > 100 { throw SuggestionError.invalidOptions }
    var recipes: [UUID: Recipe] = [:]
    for row in snapshot.recipes where !row.deleted { recipes[row.id] = try row.decode(Recipe.self) }
    var leftovers: [UUID: Leftover] = [:]
    var available: [UUID: Decimal] = [:]
    for row in snapshot.leftovers where !row.deleted {
      let leftover = try row.decode(Leftover.self)
      leftovers[row.id] = leftover
      available[row.id] = try LeftoverPlanning.available(
        id: row.id, leftover: leftover, meals: snapshot.meals)
    }
    let end = try PlanningDate.adding(6, to: week)
    let historyStart = try PlanningDate.adding(-60, to: week)
    var occupied = Set<String>()
    var used: [UUID: Int] = [:]
    var lastCooked: [UUID: String] = [:]
    var lastPlanned: [UUID: String] = [:]
    var frequency: [UUID: Int] = [:]
    for item in try MealPlanning.expand(snapshot.meals, from: week, through: end) {
      occupied.insert(item.date + ":" + item.meal.category)
      used[item.meal.recipeID, default: 0] += 1
    }
    for item in try MealPlanning.expand(
      snapshot.meals, from: historyStart, through: PlanningDate.adding(-1, to: week))
    {
      lastPlanned[item.meal.recipeID] = max(
        lastPlanned[item.meal.recipeID] ?? historyStart, item.date)
      if item.date >= (try PlanningDate.adding(-14, to: week)) {
        frequency[item.meal.recipeID, default: 0] += 1
      }
    }
    for row in snapshot.meals where !row.deleted {
      let meal = try row.decode(Meal.self)
      if meal.cooked && meal.date < week {
        lastCooked[meal.recipeID] = max(lastCooked[meal.recipeID] ?? meal.date, meal.date)
      }
    }
    var results: [SuggestedMeal] = []
    for offset in 0..<7 {
      let day = try PlanningDate.adding(offset, to: week)
      for category in categories where !occupied.contains(day + ":" + category) {
        let reusable = try leftovers.filter { id, leftover in
          guard let recipe = recipes[leftover.recipeID], !leftover.discarded,
            leftover.producedOn <= day
          else { return false }
          let amount = try servings ?? PortionQuantity.parse(recipe.servings)
          return available[id, default: 0] >= amount
        }.sorted {
          ($0.value.producedOn, $0.key.uuidString) < ($1.value.producedOn, $1.key.uuidString)
        }
        if let (id, leftover) = reusable.first, let recipe = recipes[leftover.recipeID] {
          let amount = try servings ?? PortionQuantity.parse(recipe.servings)
          available[id, default: 0] -= amount
          var meal = Meal(
            recipeID: leftover.recipeID, date: day, category: category,
            servings: NSDecimalNumber(decimal: amount).stringValue)
          meal.leftoverID = id
          results.append(SuggestedMeal(meal: meal, reasons: ["use_available_leftovers"]))
          used[leftover.recipeID, default: 0] += 1
          continue
        }
        let candidates = recipes.filter { options.allowRepeats || used[$0.key, default: 0] == 0 }
        var ranked: [(UUID, Recipe, Int)] = []
        for (id, recipe) in candidates {
          let cookedDays = try min(
            60, PlanningDate.distance(from: lastCooked[id] ?? historyStart, to: week))
          let plannedDays = try min(
            30, PlanningDate.distance(from: lastPlanned[id] ?? historyStart, to: week))
          let score =
            (recipe.rating ?? 3) * 5 + cookedDays + plannedDays
            - 100 * used[id, default: 0] - 10 * frequency[id, default: 0]
            + tie(seed: options.seed, day: day, category: category, recipe: id)
          ranked.append((id, recipe, score))
        }
        ranked.sort { $0.2 == $1.2 ? $0.0.uuidString < $1.0.uuidString : $0.2 > $1.2 }
        guard let (id, recipe, _) = ranked.first else { continue }
        var reasons = [(recipe.rating ?? 0) >= 4 ? "positively_rated" : "library_variety"]
        let cookedDays = try lastCooked[id].map { try PlanningDate.distance(from: $0, to: week) }
        if cookedDays == nil || cookedDays! > 14 {
          reasons.append("not_cooked_recently")
        }
        if used[id, default: 0] == 0 { reasons.append("not_planned_this_week") }
        let amount = try servings ?? PortionQuantity.parse(recipe.servings)
        results.append(
          SuggestedMeal(
            meal: Meal(
              recipeID: id, date: day, category: category,
              servings: NSDecimalNumber(decimal: amount).stringValue), reasons: reasons))
        used[id, default: 0] += 1
      }
    }
    return try WeeklyPreview(monday: week, basis: snapshot.basis(), suggestions: results)
  }
}
