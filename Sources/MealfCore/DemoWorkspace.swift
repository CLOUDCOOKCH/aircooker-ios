import Foundation

/// Explicit sample data belongs to its own database and can never be bound to
/// a real server. It is not an alternative transport or an integration mock.
public enum DemoWorkspace {
  public static let instanceID = "a1c00000-0000-4000-8000-000000000000"
  public static let photoID = UUID(uuidString: "a1c00000-0000-4000-8000-000000000099")!
  public static func databaseURL(in directory: URL) -> URL {
    directory.appending(path: "offline-demo/mealf.sqlite3")
  }
  private static func id(_ number: Int) -> UUID {
    UUID(uuidString: String(format: "a1c00000-0000-4000-8000-%012d", number))!
  }
  public static func seed(
    now: Date, timeZone: String, language: String, withPhoto: Bool = false
  ) throws -> [LocalEdit] {
    let german = language == "de"
    func text(_ en: String, _ de: String) -> String { german ? de : en }
    func ingredient(_ en: String, _ de: String, _ quantity: String, _ unit: String) -> Ingredient {
      var value = Ingredient(name: text(en, de))
      value.quantity = quantity
      value.unit = unit
      value.originalText = "\(quantity) \(unit) \(value.name)"
      return value
    }
    let titles = [
      text("Lemon chicken & potatoes", "Zitronenhähnchen mit Kartoffeln"),
      text("Tomato & basil pasta", "Tomaten-Basilikum-Pasta"),
      text("Chickpea & herb salad", "Kichererbsensalat mit Kräutern"),
      text("Overnight oats", "Haferflocken über Nacht"),
      text("Blueberry pancakes", "Heidelbeerpfannkuchen"),
      text("Roasted vegetable bowl", "Ofengemüse-Bowl"),
      text("Vegetable soup", "Gemüsesuppe"),
    ]
    let ingredients: [[Ingredient]] = [
      [
        ingredient("chicken", "Hähnchen", "400", "g"),
        ingredient("potatoes", "Kartoffeln", "400", "g"),
        ingredient("lemon", "Zitrone", "1", "piece"),
        ingredient("olive oil", "Olivenöl", "1", "tbsp"),
      ],
      [
        ingredient("pasta", "Pasta", "200", "g"), ingredient("tomatoes", "Tomaten", "300", "g"),
        ingredient("basil", "Basilikum", "10", "g"),
      ],
      [
        ingredient("cooked chickpeas", "gekochte Kichererbsen", "250", "g"),
        ingredient("cucumber", "Gurke", "1", "piece"),
        ingredient("parsley", "Petersilie", "10", "g"),
      ],
      [ingredient("oats", "Haferflocken", "100", "g"), ingredient("milk", "Milch", "250", "ml")],
      [
        ingredient("flour", "Mehl", "150", "g"), ingredient("milk", "Milch", "200", "ml"),
        ingredient("egg", "Ei", "1", "piece"),
        ingredient("blueberries", "Heidelbeeren", "100", "g"),
      ],
      [
        ingredient("carrots", "Möhren", "200", "g"),
        ingredient("courgette", "Zucchini", "1", "piece"),
        ingredient("cooked rice", "gekochter Reis", "200", "g"),
      ],
      [
        ingredient("carrots", "Möhren", "200", "g"),
        ingredient("potatoes", "Kartoffeln", "200", "g"),
        ingredient("vegetable stock", "Gemüsebrühe", "600", "ml"),
      ],
    ]
    let steps = [
      text(
        "Roast the chicken, potatoes, lemon and oil until the potatoes are tender and the chicken reaches at least 75°C at its thickest point.",
        "Hähnchen, Kartoffeln, Zitrone und Öl im Ofen garen, bis die Kartoffeln weich sind und das Fleisch an der dicksten Stelle mindestens 75 °C erreicht."
      ),
      text(
        "Cook the pasta. Simmer the tomatoes, combine with the pasta and finish with basil.",
        "Pasta kochen. Tomaten köcheln lassen, mit der Pasta mischen und Basilikum hinzufügen."),
      text(
        "Dice the cucumber and chop the herbs. Toss with the cooked chickpeas.",
        "Gurke würfeln und Kräuter hacken. Mit den gekochten Kichererbsen mischen."),
      text(
        "Mix oats and milk, cover and refrigerate overnight.",
        "Haferflocken und Milch mischen, abdecken und über Nacht in den Kühlschrank stellen."),
      text(
        "Mix the batter, fold in blueberries and cook small pancakes until cooked through.",
        "Teig mischen, Heidelbeeren unterheben und kleine Pfannkuchen vollständig durchbacken."),
      text(
        "Roast the vegetables until tender and serve over freshly cooked rice.",
        "Gemüse im Ofen weich garen und auf frisch gekochtem Reis servieren."),
      text(
        "Dice the vegetables and simmer in the stock until tender.",
        "Gemüse würfeln und in der Brühe weich köcheln lassen."),
    ]
    var edits: [LocalEdit] = []
    for index in titles.indices {
      var recipe = Recipe(title: titles[index])
      recipe.sourcePlatform = "demo"
      recipe.ingredients = ingredients[index]
      recipe.steps = [steps[index]]
      recipe.notes = text(
        "Sample recipe for exploring mealf. Check and adapt before cooking.",
        "Beispielrezept zum Erkunden von mealf. Vor dem Kochen prüfen und anpassen.")
      recipe.rating = index < 3 ? 5 - index % 2 : nil
      recipe.provenance = ["origin": "offline-demo", "illustrative": "true"]
      if index == 0 && withPhoto { recipe.imageID = photoID }
      edits.append(try LocalEdit(kind: .recipe, id: id(index + 1), value: recipe))
    }
    let today = try MealPresentation.civilDate(now, timeZone: timeZone)
    let monday = try PlanningDate.monday(containing: today)
    let todayOffset = try PlanningDate.distance(from: monday, to: today)
    var dinnerDays: Set<Int> = [0, 1, 2, 4, 6]
    if !dinnerDays.contains(todayOffset) {
      dinnerDays.remove(0)
      dinnerDays.insert(todayOffset)
    }
    let dinnerRecipes = [2, 6, 1, 2, 7, 6, 1]
    for offset in dinnerDays.sorted() {
      let date = try PlanningDate.adding(offset, to: monday)
      let recipeID = date == today ? id(1) : id(dinnerRecipes[offset])
      edits.append(
        try LocalEdit(
          kind: .meal, id: id(20 + offset),
          value: Meal(recipeID: recipeID, date: date, category: "dinner")))
    }
    let breakfastDays = Array([5, 6, 0].filter { $0 != todayOffset }.prefix(2))
    for (index, offset) in breakfastDays.enumerated() {
      edits.append(
        try LocalEdit(
          kind: .meal, id: id(30 + index),
          value: Meal(
            recipeID: id(index == 0 ? 5 : 4), date: PlanningDate.adding(offset, to: monday),
            category: "breakfast")))
    }
    let lunchDay = [1, 0, 2].first { $0 != todayOffset }!
    edits.append(
      try LocalEdit(
        kind: .meal, id: id(32),
        value: Meal(
          recipeID: id(7), date: PlanningDate.adding(lunchDay, to: monday), category: "lunch")))
    var history = Meal(
      recipeID: id(2), date: try PlanningDate.adding(-7, to: monday), category: "dinner")
    history.cooked = true
    edits.append(try LocalEdit(kind: .meal, id: id(28), value: history))
    edits.append(
      try LocalEdit(
        kind: .leftover, id: id(40),
        value: Leftover(recipeID: id(7), portions: "2", producedOn: today)))
    edits.append(
      try LocalEdit(kind: .pantry, id: id(50), value: PantryItem(name: text("salt", "Salz"))))
    edits.append(
      try LocalEdit(
        kind: .pantry, id: id(51), value: PantryItem(name: text("olive oil", "Olivenöl"))))
    edits.append(
      try LocalEdit(
        kind: .template, id: id(60),
        value: MealTemplate(
          name: text("A simple week", "Eine einfache Woche"),
          meals: [TemplateSlot(weekday: 2, category: "dinner", recipeID: id(1), servings: "2")])))
    return edits
  }
}
