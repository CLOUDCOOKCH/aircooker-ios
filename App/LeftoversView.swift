import MealfCore
import SwiftUI

struct LeftoversView: View {
  @Environment(AppModel.self) private var model
  @State private var creating = false
  @State private var editing: LocalEntity?
  @State private var scheduling: LocalEntity?
  var body: some View {
    List {
      if model.leftovers.isEmpty {
        ContentUnavailableView(
          "no_leftovers", systemImage: "takeoutbag.and.cup.and.straw",
          description: Text("leftovers_empty_hint"))
      }
      ForEach(model.leftovers) { row in
        if let leftover = try? row.decode(Leftover.self) {
          VStack(alignment: .leading, spacing: 8) {
            Text(model.recipe(leftover.recipeID)?.title ?? String(localized: "recipe_unavailable"))
              .font(.headline)
            Text("produced_date \(model.displayPlanningDate(leftover.producedOn))")
              .font(.caption).foregroundStyle(.secondary)
            if leftover.discarded {
              Text("leftovers_discarded").foregroundStyle(.secondary)
            } else {
              Text("available_portions \(model.availablePortions(row))")
              HStack {
                Button("schedule_leftovers") { scheduling = row }
                  .disabled(!model.canScheduleLeftover(row))
                Spacer()
                Button("edit") { editing = row }
              }.buttonStyle(.borderless)
            }
          }.padding(.vertical, 6)
        }
      }
    }.navigationTitle("leftovers")
      .toolbar { Button("record_leftovers", systemImage: "plus") { creating = true } }
      .sheet(isPresented: $creating) { LeftoverEditor() }
      .sheet(item: $editing) { LeftoverEditor(existing: $0) }
      .sheet(item: $scheduling) { row in
        NavigationStack { LeftoverScheduleView(row: row) }
      }
  }
}
struct LeftoverEditor: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  let existing: LocalEntity?
  let source: MealOccurrence?
  @State private var recipeID: UUID?
  @State private var available = "2"
  @State private var produced = Date()
  @State private var saving = false
  @State private var confirmingDiscard = false
  init(existing: LocalEntity? = nil, source: MealOccurrence? = nil) {
    self.existing = existing
    self.source = source
    _recipeID = State(initialValue: source?.meal.recipeID)
  }
  var body: some View {
    NavigationStack {
      Form {
        Section("recipe") {
          Picker("choose_recipe", selection: $recipeID) {
            Text("choose_recipe").tag(nil as UUID?)
            ForEach(model.recipes) { row in
              if let recipe = try? row.decode(Recipe.self) {
                Text(recipe.title).tag(Optional(row.id))
              }
            }
          }.disabled(existing != nil || source != nil)
          DatePicker("produced_on", selection: $produced, in: ...Date(), displayedComponents: .date)
            .disabled(existing != nil || source != nil)
        }
        Section {
          TextField("unplanned_portions", text: $available).keyboardType(.decimalPad)
          if let existing { Text("reserved_portions \(model.allocatedPortions(existing))") }
        } header: {
          Text("unplanned_portions")
        } footer: {
          Text("leftovers_portion_hint")
        }
        if existing != nil {
          Section {
            Button("discard_leftovers", role: .destructive) { confirmingDiscard = true }
          }
        }
      }.navigationTitle(existing == nil ? "record_leftovers" : "edit_leftovers")
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("cancel") { dismiss() } }
          ToolbarItem(placement: .confirmationAction) {
            Button("save") { save(discard: false) }
              .disabled(
                saving || recipeID == nil
                  || (try? model.parsePortions(available, allowZero: existing != nil)) == nil)
          }
        }
        .onAppear {
          if let existing, let leftover = try? existing.decode(Leftover.self) {
            recipeID = leftover.recipeID
            available = model.availablePortions(existing)
            produced = model.planningDate(leftover.producedOn) ?? Date()
          } else if let source {
            produced = model.planningDate(source.date) ?? Date()
          } else {
            recipeID = model.recipes.first?.id
          }
        }
        .confirmationDialog(
          "discard_leftovers_question", isPresented: $confirmingDiscard,
          titleVisibility: .visible
        ) {
          Button("discard_leftovers", role: .destructive) { save(discard: true) }
        } message: {
          Text("discard_leftovers_hint")
        }
    }.safeAreaInset(edge: .bottom) { OperationErrorNotice() }
      .environment(\.timeZone, TimeZone(identifier: model.householdTimeZone) ?? .current)
      .interactiveDismissDisabled(saving)
  }
  private func save(discard: Bool) {
    guard let recipeID, !saving else { return }
    saving = true
    Task {
      let success = await model.saveLeftover(
        existing: existing, source: source, recipeID: recipeID,
        unplanned: available, producedOn: model.dateString(produced), discard: discard)
      saving = false
      if success { dismiss() }
    }
  }
}
struct LeftoverScheduleView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  let row: LocalEntity
  var initialDate: String? = nil
  var initialCategory = "dinner"
  @State private var date = Date()
  @State private var category = "dinner"
  @State private var portions = "2"
  @State private var saving = false
  var body: some View {
    Form {
      if let leftover = try? row.decode(Leftover.self) {
        Section {
          Text(model.recipe(leftover.recipeID)?.title ?? String(localized: "recipe_unavailable"))
            .font(.headline)
          Text("available_portions \(model.availablePortions(row))")
        }
      }
      Section {
        DatePicker("meal_date", selection: $date, displayedComponents: .date)
        Picker("meal_category", selection: $category) {
          ForEach(["breakfast", "lunch", "dinner"], id: \.self) {
            Text(LocalizedStringKey($0)).tag($0)
          }
        }
        TextField("portions", text: $portions).keyboardType(.decimalPad)
      }
      Text("leftovers_shopping_hint").font(.footnote).foregroundStyle(.secondary)
      Button("schedule_leftovers") {
        saving = true
        Task {
          if await model.scheduleLeftover(
            id: row.id, date: model.dateString(date),
            category: category, portions: portions)
          {
            dismiss()
          }
          saving = false
        }
      }.disabled(saving || (try? model.parsePortions(portions)) == nil)
    }.navigationTitle("schedule_leftovers")
      .safeAreaInset(edge: .bottom) { OperationErrorNotice() }
      .environment(\.timeZone, TimeZone(identifier: model.householdTimeZone) ?? .current)
      .onAppear {
        category = initialCategory
        date = initialDate.flatMap { model.planningDate($0) } ?? Date()
        portions = model.defaultLeftoverPortions(row)
      }
  }
}
