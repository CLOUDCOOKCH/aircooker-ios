import Foundation
import Testing

@testable import AirCookerCore

@Test func recipeCodecMatchesCanonicalServerFixture() throws {
  let url = try #require(
    Bundle.module.url(forResource: "recipe", withExtension: "json", subdirectory: "Fixtures"))
  let raw = try Data(contentsOf: url)
  let recipe = try JSONDecoder().decode(Recipe.self, from: raw)
  #expect(recipe.title == "Fixture soup")
  #expect(recipe.ingredients.first?.quantity == "200")
  let encoded = try JSONEncoder().encode(recipe)
  // Optional nulls may be omitted, but every populated server value must round-trip.
  #expect(try JSONDecoder().decode(Recipe.self, from: encoded) == recipe)
}

@Test func mutationCodecMatchesCanonicalServerFixture() throws {
  let url = try #require(
    Bundle.module.url(forResource: "mutation", withExtension: "json", subdirectory: "Fixtures"))
  let value = try JSONDecoder().decode(Mutation.self, from: Data(contentsOf: url))
  #expect(value.kind == .recipe)
  #expect(value.operation == "upsert")
  #expect(value.idempotencyKey == value.mutationID)
  let data = try JSONEncoder().encode(value)
  let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  #expect(object["base_revision"] as? Int == 0)
  #expect(object["device_id"] is String)
  #expect(object["client_timestamp"] is String)
}

@Test func planningCodecsMatchCanonicalServerFixtures() throws {
  let mealURL = try #require(
    Bundle.module.url(
      forResource: "recurring-meal", withExtension: "json", subdirectory: "Fixtures"))
  let meal = try JSONDecoder().decode(Meal.self, from: Data(contentsOf: mealURL))
  #expect(meal.servings == "3.5" && meal.recurrence?.intervalWeeks == 2)
  #expect(
    try MealPlanning.occurrences(meal, from: "2026-10-20", through: "2026-12-31") == [
      "2026-11-16", "2026-11-30", "2026-12-14",
    ])
  let roundTrip = try JSONDecoder().decode(Meal.self, from: JSONEncoder().encode(meal))
  #expect(roundTrip.recurrence == meal.recurrence)
  let templateURL = try #require(
    Bundle.module.url(forResource: "template", withExtension: "json", subdirectory: "Fixtures"))
  let template = try JSONDecoder().decode(MealTemplate.self, from: Data(contentsOf: templateURL))
  #expect(template.name == "Fixture week" && template.meals[0].weekday == 6)
  #expect(template.meals[0].recipeID == meal.recipeID)
  let original =
    try JSONSerialization.jsonObject(with: Data(contentsOf: templateURL)) as? NSDictionary
  let encoded =
    try JSONSerialization.jsonObject(with: JSONEncoder().encode(template)) as? NSDictionary
  #expect(original == encoded)
}
