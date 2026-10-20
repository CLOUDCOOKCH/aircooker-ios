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
