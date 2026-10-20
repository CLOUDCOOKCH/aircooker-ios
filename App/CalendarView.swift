import AirCookerCore
import SwiftUI

struct CalendarView: View {
  @Environment(AppModel.self) private var model
  @State private var weekOffset = 0
  @State private var assigning: Date?
  @State private var category = "dinner"
  var days: [Date] {
    var calendar = Calendar(identifier: .gregorian)
    calendar.firstWeekday = 2
    calendar.timeZone = TimeZone(identifier: model.householdTimeZone) ?? .current
    let today = calendar.startOfDay(for: Date())
    let weekday = calendar.component(.weekday, from: today)
    let monday =
      calendar.date(byAdding: .day, value: -((weekday + 5) % 7) + weekOffset * 7, to: today)
      ?? today
    return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
  }
  var body: some View {
    List {
      Section {
        HStack {
          Button("previous_week", systemImage: "chevron.left") { weekOffset -= 1 }
          Spacer()
          Button("this_week") { weekOffset = 0 }
          Spacer()
          Button("next_week", systemImage: "chevron.right") { weekOffset += 1 }
        }.labelStyle(.iconOnly)
      }
      ForEach(days, id: \.self) { day in
        Section {
          ForEach(["breakfast", "lunch", "dinner"], id: \.self) { slot in
            VStack(alignment: .leading, spacing: 8) {
              Text(LocalizedStringKey(slot)).font(.caption).foregroundStyle(.secondary)
              let entries = model.meals.filter { row in
                guard let meal = try? row.decode(Meal.self) else { return false }
                return meal.date == model.dateString(day) && meal.category == slot
              }
              ForEach(entries) { row in
                if let meal = try? row.decode(Meal.self) {
                  NavigationLink(model.title(meal)) { RecipeDetail(id: meal.recipeID) }
                    .draggable(row.id.uuidString)
                    .contextMenu {
                      Button("duplicate") {
                        Task { _ = await model.save(kind: .meal, value: meal) }
                      }
                      Button("move_tomorrow") {
                        var moved = meal
                        var calendar = Calendar(identifier: .gregorian)
                        calendar.timeZone =
                          TimeZone(identifier: model.householdTimeZone) ?? .current
                        moved.date = model.dateString(
                          calendar.date(byAdding: .day, value: 1, to: day) ?? day)
                        Task { _ = await model.save(kind: .meal, id: row.id, value: moved) }
                      }
                      Button("remove", role: .destructive) {
                        Task {
                          _ = await model.save(kind: .meal, id: row.id, value: meal, delete: true)
                        }
                      }
                    }
                }
              }
              Button(entries.isEmpty ? "plan_meal" : "add_meal", systemImage: "plus") {
                category = slot
                assigning = day
              }.font(.subheadline)
            }.padding(.vertical, 6)
              .dropDestination(for: String.self) { values, _ in
                guard let raw = values.first, let id = UUID(uuidString: raw),
                  let row = model.meals.first(where: { $0.id == id }),
                  var meal = try? row.decode(Meal.self)
                else { return false }
                meal.date = model.dateString(day)
                meal.category = slot
                Task { _ = await model.save(kind: .meal, id: id, value: meal) }
                return true
              }
          }
        } header: {
          Text(day, format: .dateTime.weekday(.wide).day().month())
        }
      }
    }.navigationTitle("calendar")
      .sheet(isPresented: Binding(get: { assigning != nil }, set: { if !$0 { assigning = nil } })) {
        NavigationStack {
          List(model.recipes) { row in
            if let recipe = try? row.decode(Recipe.self) {
              Button(recipe.title) {
                guard let day = assigning else { return }
                let meal = Meal(
                  recipeID: row.id, date: model.dateString(day), category: category,
                  servings: recipe.servings)
                Task { if await model.save(kind: .meal, value: meal) { assigning = nil } }
              }
            }
          }
          .navigationTitle("choose_recipe").toolbar { Button("cancel") { assigning = nil } }
        }
      }
  }
}
struct PantryView: View {
  @Environment(AppModel.self) private var model
  @State private var name = ""
  @State private var search = ""
  var body: some View {
    List {
      Section {
        HStack {
          TextField("pantry_item", text: $name)
          Button("add", systemImage: "plus") {
            let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return }
            Task {
              if await model.save(kind: .pantry, value: PantryItem(name: value)) { name = "" }
            }
          }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
      Section("staples") {
        ForEach(model.pantry) { row in
          if var item = try? row.decode(PantryItem.self),
            search.isEmpty || item.name.localizedCaseInsensitiveContains(search)
          {
            Toggle(
              item.name,
              isOn: Binding(
                get: { item.available },
                set: { new in
                  item.available = new
                  Task { _ = await model.save(kind: .pantry, id: row.id, value: item) }
                })
            )
            .swipeActions {
              Button("remove", role: .destructive) {
                Task { _ = await model.save(kind: .pantry, id: row.id, value: item, delete: true) }
              }
            }
          }
        }
      } footer: {
        Text("pantry_exclusion_hint")
      }
    }.navigationTitle("pantry").searchable(text: $search)
  }
}
