import Foundation

public enum CookingQuantityError: Error, Sendable { case invalid, invalidServings }

/// Manual editor input only. Both decimal separators mean decimals, never digit grouping.
public struct CookingQuantity: Equatable, Sendable {
  public let lower: String?
  public let upper: String?
  public let unquantified: String?

  public static func display(_ ingredient: Ingredient) -> String {
    [ingredient.quantity, ingredient.quantityMax].compactMap { $0 }.joined(separator: "–")
  }

  public static func parse(_ text: String) throws -> Self {
    let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard raw.count <= 100 else { throw CookingQuantityError.invalid }
    if raw.isEmpty { return Self(lower: nil, upper: nil, unquantified: nil) }
    // Preserve freely written measures, e.g. "to taste", without numeric invention.
    if raw.rangeOfCharacter(from: .decimalDigits) == nil,
      !raw.contains(where: { "¼½¾⅐⅑⅒⅓⅔⅕⅖⅗⅘⅙⅚⅛⅜⅝⅞".contains($0) })
    {
      return Self(lower: nil, upper: nil, unquantified: raw)
    }
    let parts = raw.replacingOccurrences(of: #"(?<![eE])-"#, with: "–", options: .regularExpression)
      .split(
        separator: "–", omittingEmptySubsequences: false)
    guard (1...2).contains(parts.count) else { throw CookingQuantityError.invalid }
    let values = try parts.map { try scalar(String($0)) }
    guard values.count == 1 || values[1] >= values[0] else {
      throw CookingQuantityError.invalid
    }
    return Self(
      lower: NSDecimalNumber(decimal: values[0]).stringValue,
      upper: values.count == 2 ? NSDecimalNumber(decimal: values[1]).stringValue : nil,
      unquantified: nil)
  }

  private static func scalar(_ input: String) throws -> Decimal {
    var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
    for (symbol, fraction) in [
      "¼": "1/4", "½": "1/2", "¾": "3/4", "⅐": "1/7", "⅑": "1/9", "⅒": "1/10",
      "⅓": "1/3", "⅔": "2/3", "⅕": "1/5", "⅖": "2/5", "⅗": "3/5", "⅘": "4/5",
      "⅙": "1/6", "⅚": "5/6", "⅛": "1/8", "⅜": "3/8", "⅝": "5/8", "⅞": "7/8",
    ] {
      text = text.replacingOccurrences(of: symbol, with: " " + fraction)
    }
    text = text.replacingOccurrences(of: "⁄", with: "/")
    let words = text.split(whereSeparator: \.isWhitespace)
    guard (1...2).contains(words.count) else { throw CookingQuantityError.invalid }
    let locale = Locale(identifier: "en_US_POSIX")
    let value: Decimal
    if let last = words.last, last.contains("/") {
      let fraction = last.split(separator: "/", omittingEmptySubsequences: false)
      guard fraction.count == 2,
        fraction.allSatisfy({ $0.range(of: #"^[0-9]{1,6}$"#, options: .regularExpression) != nil }),
        let numerator = Decimal(string: String(fraction[0]), locale: locale),
        let denominator = Decimal(string: String(fraction[1]), locale: locale), denominator > 0
      else { throw CookingQuantityError.invalid }
      var whole: Decimal = 0
      if words.count == 2 {
        guard words[0].range(of: #"^[0-9]{1,7}$"#, options: .regularExpression) != nil,
          let parsed = Decimal(string: String(words[0]), locale: locale), numerator < denominator
        else { throw CookingQuantityError.invalid }
        whole = parsed
      }
      var divided = numerator / denominator
      var rounded: Decimal = 0
      NSDecimalRound(&rounded, &divided, 12, .plain)
      value = whole + rounded
    } else {
      guard words.count == 1,
        text.range(
          of: #"^[0-9]+(?:[.,][0-9]+)?(?:[eE][+-]?[0-9]{1,3})?$"#, options: .regularExpression)
          != nil,
        let parsed = Decimal(string: text.replacingOccurrences(of: ",", with: "."), locale: locale)
      else { throw CookingQuantityError.invalid }
      value = parsed
    }
    guard !value.isNaN, value >= 0, value <= 1_000_000 else {
      throw CookingQuantityError.invalid
    }
    return value
  }

  public static func normalise(_ recipe: Recipe) throws -> Recipe {
    var result = recipe
    let servings = try parse(recipe.servings)
    guard let count = servings.lower, servings.upper == nil,
      try PortionQuantity.parse(count) > 0
    else { throw CookingQuantityError.invalidServings }
    result.servings = count
    result.ingredients = try recipe.ingredients.map { ingredient in
      var item = ingredient
      guard ingredient.quantity != nil || ingredient.quantityMax == nil else {
        throw CookingQuantityError.invalid
      }
      let original = display(ingredient).trimmingCharacters(in: .whitespacesAndNewlines)
      let parsed = try parse(original)
      item.quantity = parsed.lower
      item.quantityMax = parsed.upper
      if (item.originalText.isEmpty || parsed.unquantified != nil) && !original.isEmpty {
        item.originalText = [original, item.unit, item.name].filter { !$0.isEmpty }.joined(
          separator: " ")
      }
      return item
    }
    return result
  }
}
