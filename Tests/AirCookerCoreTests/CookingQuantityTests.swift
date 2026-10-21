import Foundation
import Testing

@testable import AirCookerCore

@Test func cookingQuantitiesParseFractionsDecimalsAndRanges() throws {
  for (input, lower, upper) in [
    ("½", "0.5", nil), ("1½", "1.5", nil), ("1 1/2", "1.5", nil),
    ("1⁄4", "0.25", nil), ("1,25", "1.25", nil), ("1.000", "1", nil),
    ("1/2–3/4", "0.5", "0.75"), ("1 - 2", "1", "2"),
    ("0", "0", nil), ("1000000", "1000000", nil),
    ("1e-3–2e-3", "0.001", "0.002"), ("1E+3", "1000", nil),
  ] as [(String, String, String?)] {
    let parsed = try CookingQuantity.parse(input)
    #expect(parsed.lower == lower)
    #expect(parsed.upper == upper)
    #expect(parsed.unquantified == nil)
  }
  #expect(try CookingQuantity.parse("⅓").lower == "0.333333333333")
  #expect(try CookingQuantity.parse("  ").lower == nil)
  #expect(try CookingQuantity.parse("nach Geschmack").unquantified == "nach Geschmack")
}

@Test func cookingQuantitiesRejectInvalidArithmeticAndNumericPrefixes() {
  for input in [
    "1/0", "1/2/3", "2–1", "-1", "1–2–3", "1 5/2", "1 2", "2 cups", "2,000.5",
    "1e999", "1000001", "1–", "–1", String(repeating: "1", count: 101),
  ] {
    #expect(throws: (any Error).self) { try CookingQuantity.parse(input) }
  }
}

@Test func recipeNormalisationPreservesTextAndEncodesCanonicalQuantities() throws {
  var recipe = Recipe(title: "Pancakes")
  recipe.servings = "1 1/2"
  var flour = Ingredient(name: "flour")
  flour.quantity = "½–¾"
  flour.unit = "kg"
  flour.preparation = "sifted"
  var salt = Ingredient(name: "salt")
  salt.quantity = "to taste"
  salt.originalText = "Previous amount"
  recipe.ingredients = [flour, salt]
  let normal = try CookingQuantity.normalise(recipe)
  #expect(normal.servings == "1.5")
  #expect(normal.ingredients[0].quantity == "0.5")
  #expect(normal.ingredients[0].quantityMax == "0.75")
  #expect(normal.ingredients[0].originalText == "½–¾ kg flour")
  #expect(normal.ingredients[0].preparation == "sifted")
  #expect(normal.ingredients[0].scaled(by: 2).quantityMax == "1.5")
  #expect(normal.ingredients[1].quantity == nil)
  #expect(normal.ingredients[1].originalText == "to taste salt")
  #expect(recipe.ingredients[0].quantity == "½–¾")
  let decoded = try JSONDecoder().decode(Recipe.self, from: JSONEncoder().encode(normal))
  #expect(decoded == normal)
  #expect(try CookingQuantity.normalise(normal) == normal)
}

@Test func recipeNormalisationRejectsOrphansAndInvalidServingsWithoutChangingDraft() {
  var recipe = Recipe(title: "Soup")
  recipe.servings = "2–3"
  #expect(throws: (any Error).self) { try CookingQuantity.normalise(recipe) }
  recipe.servings = "0"
  #expect(throws: (any Error).self) { try CookingQuantity.normalise(recipe) }
  recipe.servings = "to taste"
  #expect(throws: (any Error).self) { try CookingQuantity.normalise(recipe) }
  recipe.servings = "2"
  var item = Ingredient(name: "onion")
  item.quantityMax = "2"
  recipe.ingredients = [item]
  #expect(throws: (any Error).self) { try CookingQuantity.normalise(recipe) }
  #expect(recipe.ingredients[0].quantityMax == "2")
}

@Test func normalisedEditorRecipePersistsCanonicalOfflineMutation() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  let url = root.appendingPathComponent("local.sqlite3")
  let store = try LocalStore(url: url)
  var recipe = Recipe(title: "Cake")
  var flour = Ingredient(name: "flour")
  flour.quantity = "1/2"
  flour.quantityMax = "3/4"
  recipe.ingredients = [flour]
  let normal = try CookingQuantity.normalise(recipe)
  let id = UUID()
  try await store.save(kind: .recipe, id: id, value: normal)
  let reopened = try LocalStore(url: url)
  let entity = try #require(try await reopened.entities(kind: .recipe).first)
  #expect(try entity.decode(Recipe.self) == normal)
  #expect(try await reopened.pending().count == 1)
}
