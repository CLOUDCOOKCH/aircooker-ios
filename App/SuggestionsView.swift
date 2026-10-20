import AirCookerCore
import SwiftUI

struct SuggestionsView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  let week: String
  @AppStorage("suggestionAllowRepeats") private var allowRepeats = false
  @AppStorage("suggestionUseRecipeServings") private var recipeServings = true
  @AppStorage("suggestionServings") private var servings = 2
  @State private var categories: Set<String> = ["dinner"]
  @State private var preview: WeeklyPreview?
  @State private var selected = Set<String>()
  @State private var generating = false
  @State private var saving = false
  @State private var seed = 0
  var body: some View {
    List {
      Section {
        Text("suggestions_local_hint")
        Text("week_of \(model.displayPlanningDate(week))").foregroundStyle(.secondary)
      }
      Section("suggestion_preferences") {
        ForEach(["breakfast", "lunch", "dinner"], id: \.self) { category in
          Toggle(
            LocalizedStringKey(category),
            isOn: Binding(
              get: { categories.contains(category) },
              set: { value in
                if value { categories.insert(category) } else { categories.remove(category) }
                invalidate()
              }))
        }
        Toggle("allow_recipe_repeats", isOn: $allowRepeats).onChange(of: allowRepeats) {
          invalidate()
        }
        Toggle("use_recipe_servings", isOn: $recipeServings).onChange(of: recipeServings) {
          invalidate()
        }
        if !recipeServings {
          Stepper("servings_count \(servings)", value: $servings, in: 1...100)
            .onChange(of: servings) { invalidate() }
        }
      }
      Section {
        Button(
          preview == nil ? "generate_suggestions" : "regenerate_suggestions",
          systemImage: "arrow.clockwise"
        ) {
          seed = (seed + 1) % 2_147_483_648
          Task { await generate() }
        }.disabled(categories.isEmpty || generating || saving)
        if generating { ProgressView("generating_suggestions") }
      }
      if let preview {
        Section("suggested_meals") {
          if preview.suggestions.isEmpty {
            ContentUnavailableView(
              "no_suggestions", systemImage: "calendar.badge.checkmark",
              description: Text("no_suggestions_hint"))
          }
          ForEach(preview.suggestions) { suggestion in
            Toggle(
              isOn: Binding(
                get: { selected.contains(suggestion.id) },
                set: { value in
                  if value {
                    selected.insert(suggestion.id)
                  } else {
                    selected.remove(suggestion.id)
                  }
                })
            ) {
              VStack(alignment: .leading, spacing: 6) {
                Text(model.title(suggestion.meal)).font(.headline)
                Text(model.displayPlanningDate(suggestion.meal.date)).font(.subheadline)
                Text(LocalizedStringKey(suggestion.meal.category)).foregroundStyle(.secondary)
                Text("plan_portions \(suggestion.meal.servings)").font(.caption)
                if let id = suggestion.meal.leftoverID,
                  let row = model.leftovers.first(where: { $0.id == id }),
                  let leftover = try? row.decode(Leftover.self)
                {
                  Text("produced_date \(model.displayPlanningDate(leftover.producedOn))").font(
                    .caption)
                }
                ForEach(suggestion.reasons, id: \.self) { reason in
                  Text(LocalizedStringKey("suggestion_reason_" + reason))
                    .font(.caption).foregroundStyle(.secondary)
                }
              }.padding(.vertical, 4)
            }
          }
        } footer: {
          Text("suggestions_variety_hint")
        }
      }
    }.navigationTitle("weekly_suggestions")
      .toolbar {
        Button("apply_selected") {
          guard let preview else { return }
          saving = true
          Task {
            if await model.applySuggestions(preview, selected: selected) { dismiss() }
            saving = false
          }
        }.disabled(preview == nil || selected.isEmpty || saving || generating)
      }
      .safeAreaInset(edge: .bottom) { OperationErrorNotice() }
      .task { await generate() }
  }
  private func invalidate() {
    preview = nil
    selected = []
  }
  private func generate() async {
    guard !generating, !categories.isEmpty, let store = model.store else { return }
    generating = true
    defer { generating = false }
    do {
      let snapshot = try await store.planningSnapshot()
      let options = SuggestionOptions(
        categories: categories, allowRepeats: allowRepeats,
        servings: recipeServings ? nil : String(servings), seed: seed)
      let targetWeek = week
      let value = try await Task.detached(priority: .userInitiated) {
        try WeeklyRecommendations.generate(snapshot: snapshot, week: targetWeek, options: options)
      }.value
      try Task.checkCancellation()
      preview = value
      selected = Set(value.suggestions.map(\.id))
    } catch is CancellationError {
    } catch { model.report(error) }
  }
}
