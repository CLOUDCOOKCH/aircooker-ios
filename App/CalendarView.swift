import AirCookerCore
import SwiftUI

private struct PlanPreview: Identifiable {
  let id = UUID()
  let edits: [LocalEdit]
}
struct CalendarView: View {
  @Environment(AppModel.self) private var model
  let initialDate: String?
  init(initialDate: String? = nil) { self.initialDate = initialDate }
  @State private var focusedInitialDate = false
  @State private var scrolledInitialDate = false
  @State private var weekOffset = 0
  @State private var assigning: Date?
  @State private var category = "dinner"
  @State private var visibleMeals: [MealOccurrence] = []
  @State private var preview: PlanPreview?
  @State private var namingTemplate = false
  @State private var templateName = ""
  @State private var selectingTemplate = false
  @State private var selectedTemplateEdits: [LocalEdit]?
  @State private var recurrence: MealOccurrence?
  @State private var moving: MealOccurrence?
  @State private var recordingLeftovers: MealOccurrence?
  var calendar: Calendar {
    var value = Calendar(identifier: .gregorian)
    value.firstWeekday = 2
    value.timeZone = TimeZone(identifier: model.householdTimeZone) ?? .current
    return value
  }
  var days: [Date] {
    let today = calendar.startOfDay(for: Date())
    let weekday = calendar.component(.weekday, from: today)
    let monday =
      calendar.date(
        byAdding: .day,
        value: -((weekday + 5) % 7) + weekOffset * 7, to: today) ?? today
    return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
  }
  var week: String { model.dateString(days.first ?? Date()) }
  var body: some View {
    ScrollViewReader { proxy in
      List {
        Section {
          HStack(spacing: 12) {
            Button {
              weekOffset -= 1
            } label: {
              Image(systemName: "chevron.left").frame(minWidth: 44, minHeight: 44)
            }.accessibilityLabel(Text("previous_week"))
            Spacer(minLength: 0)
            VStack(spacing: 2) {
              if let first = days.first, let last = days.last {
                (Text(first, format: .dateTime.day().month(.abbreviated)) + Text(" – ")
                  + Text(last, format: .dateTime.day().month(.abbreviated)))
                  .font(.headline).multilineTextAlignment(.center)
              }
              Button("this_week") { weekOffset = 0 }.font(.subheadline)
                .frame(minHeight: 44)
            }
            Spacer(minLength: 0)
            Button {
              weekOffset += 1
            } label: {
              Image(systemName: "chevron.right").frame(minWidth: 44, minHeight: 44)
            }.accessibilityLabel(Text("next_week"))
          }.buttonStyle(.borderless).listRowBackground(Color.clear)
        }
        ForEach(days, id: \.self) { day in
          let date = model.dateString(day)
          Section {
            ForEach(["breakfast", "lunch", "dinner"], id: \.self) { slot in
              let entries = visibleMeals.filter { $0.date == date && $0.meal.category == slot }
              VStack(alignment: .leading, spacing: 8) {
                Label(LocalizedStringKey(slot), systemImage: KitchenStyle.symbol(for: slot))
                  .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                ForEach(entries) { item in
                  NavigationLink {
                    RecipeDetail(id: item.meal.recipeID)
                  } label: {
                    HStack {
                      RecipePhotoView(imageID: model.recipe(item.meal.recipeID)?.imageID)
                        .frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 8))
                      Text(model.title(item.meal))
                      if item.meal.leftoverID != nil {
                        Image(systemName: "takeoutbag.and.cup.and.straw").accessibilityLabel(
                          Text("leftovers"))
                      }
                      if item.meal.recurrence != nil {
                        Image(systemName: "repeat").accessibilityLabel(Text("recurring_meal"))
                      }
                    }
                  }.draggable(item.id)
                    .contextMenu {
                      Button(item.meal.cooked ? "mark_uncooked" : "mark_cooked") {
                        perform { try MealPlanning.setCooked(item, cooked: !item.meal.cooked) }
                      }.disabled(!item.meal.cooked && item.date > model.dateString(Date()))
                      if item.meal.leftoverID == nil && item.date <= model.dateString(Date()) {
                        Button("record_leftovers") { recordingLeftovers = item }
                      }
                      Button("duplicate") { duplicate(item) }
                      Button("move_meal") { moving = item }
                      if item.meal.leftoverID == nil {
                        Button("repeat_meal") { recurrence = item }
                      }
                      Button("remove_occurrence", role: .destructive) {
                        perform { [try MealPlanning.removeOccurrence(item)] }
                      }
                      if item.meal.recurrence != nil {
                        Button("remove_series", role: .destructive) {
                          perform {
                            [
                              try LocalEdit(
                                kind: .meal, id: item.entityID,
                                value: item.meal, deleted: true)
                            ]
                          }
                        }
                      }
                    }
                }
                Button(entries.isEmpty ? "plan_meal" : "add_meal", systemImage: "plus") {
                  category = slot
                  assigning = day
                }.font(.subheadline).buttonStyle(.borderless).frame(minHeight: 44)
              }.padding(.vertical, 6)
                .dropDestination(for: String.self) { values, _ in
                  guard let value = values.first,
                    let item = visibleMeals.first(where: { $0.id == value })
                  else { return false }
                  perform { try MealPlanning.moveOccurrence(item, to: date, category: slot) }
                  return true
                }
            }
          } header: {
            HStack {
              VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                  Text(day, format: .dateTime.weekday(.wide)).font(.title3.weight(.semibold))
                  if date == model.dateString(Date()) {
                    Text("today").font(.caption).foregroundStyle(.tint)
                  }
                }
                Text(day, format: .dateTime.day().month(.wide)).font(.subheadline).foregroundStyle(
                  .secondary)
              }
              Spacer()
              Menu {
                Button("copy_day_tomorrow") {
                  prepare {
                    try MealPlanning.copy(
                      model.meals, from: date, through: date,
                      to: PlanningDate.adding(1, to: date))
                  }
                }
              } label: {
                Image(systemName: "ellipsis.circle").frame(minWidth: 44, minHeight: 44)
              }
              .accessibilityLabel(Text("day_actions"))
            }
          } footer: {
            if !visibleMeals.contains(where: { $0.date == date }) { Text("day_unplanned") }
          }.id(date)
        }
      }.navigationTitle("calendar")
        .onAppear {
          if !focusedInitialDate, let initialDate,
            let current = try? PlanningDate.monday(containing: model.dateString(Date())),
            let target = try? PlanningDate.monday(containing: initialDate),
            let distance = try? PlanningDate.distance(from: current, to: target)
          {
            weekOffset = distance / 7
          }
          focusedInitialDate = true
        }
        .environment(\.timeZone, TimeZone(identifier: model.householdTimeZone) ?? .current)
        .task(id: week) {
          if !scrolledInitialDate, let initialDate,
            (try? PlanningDate.monday(containing: initialDate)) == week
          {
            scrolledInitialDate = true
            await Task.yield()
            proxy.scrollTo(initialDate, anchor: .top)
          }
        }
        .toolbar {
          Menu {
            NavigationLink("weekly_suggestions") { SuggestionsView(week: week) }
            NavigationLink("leftovers") { LeftoversView() }
            Button("copy_week_next") {
              prepare {
                try MealPlanning.copy(
                  model.meals, from: week,
                  through: PlanningDate.adding(6, to: week), to: PlanningDate.adding(7, to: week))
              }
            }
            Button("save_week_template") { namingTemplate = true }
            Button("apply_week_template") { selectingTemplate = true }
          } label: {
            Label("week_actions", systemImage: "ellipsis.circle")
          }
        }
        .task(id: week + ":" + String(model.photoRevision)) {
          do {
            visibleMeals = try MealPlanning.expand(
              model.meals, from: week,
              through: PlanningDate.adding(6, to: week))
          } catch { model.report(error) }
        }
        .alert("save_week_template", isPresented: $namingTemplate) {
          TextField("template_name", text: $templateName)
          Button("save") {
            do {
              let value = try MealPlanning.template(
                name: templateName, rows: model.meals, week: week)
              Task { _ = await model.save(kind: .template, value: value) }
              templateName = ""
            } catch { model.report(error) }
          }
          Button("cancel", role: .cancel) {}
        }
        .sheet(item: $preview) { value in PlanningPreview(edits: value.edits) }
        .sheet(item: $recurrence) { item in RecurrenceEditor(item: item) }
        .sheet(item: $moving) { item in MealMoveEditor(item: item) }
        .sheet(item: $recordingLeftovers) { item in LeftoverEditor(source: item) }
        .sheet(
          isPresented: $selectingTemplate,
          onDismiss: {
            if let edits = selectedTemplateEdits {
              selectedTemplateEdits = nil
              preview = PlanPreview(edits: edits)
            }
          }
        ) {
          NavigationStack {
            List {
              if model.templates.isEmpty {
                ContentUnavailableView("no_templates", systemImage: "calendar.badge.plus")
              }
              ForEach(model.templates) { row in
                if let template = try? row.decode(MealTemplate.self) {
                  Button(template.name) {
                    do {
                      let edits = try MealPlanning.apply(
                        template, week: week,
                        availableRecipes: Set(model.recipes.map(\.id)))
                      selectedTemplateEdits = edits
                      selectingTemplate = false
                    } catch { model.report(error) }
                  }.swipeActions {
                    Button("remove", role: .destructive) {
                      Task {
                        _ = await model.save(
                          kind: .template, id: row.id,
                          value: template, delete: true)
                      }
                    }
                  }
                }
              }
            }.navigationTitle("apply_week_template")
              .toolbar { Button("cancel") { selectingTemplate = false } }
          }
        }
        .sheet(isPresented: Binding(get: { assigning != nil }, set: { if !$0 { assigning = nil } }))
      {
        if let day = assigning {
          MealAssignmentView(date: model.dateString(day), category: category) { assigning = nil }
        }
      }
    }
  }
  private func prepare(_ work: () throws -> [LocalEdit]) {
    do { preview = PlanPreview(edits: try work()) } catch { model.report(error) }
  }
  private func perform(_ work: () throws -> [LocalEdit]) {
    do {
      let edits = try work()
      Task { _ = await model.saveBatch(edits) }
    } catch { model.report(error) }
  }
  private func duplicate(_ item: MealOccurrence) {
    perform {
      guard item.meal.leftoverID == nil else { throw PlanningError.leftoverCannotBeCopied }
      var copy = item.meal
      copy.date = item.date
      copy.recurrence = nil
      copy.cooked = false
      return [try LocalEdit(kind: .meal, value: copy)]
    }
  }
}

struct PlanningPreview: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  let edits: [LocalEdit]
  @State private var saving = false
  var body: some View {
    NavigationStack {
      List {
        Section { Text("plan_preview_hint") }
        ForEach(Array(edits.enumerated()), id: \.offset) { _, edit in
          if let meal = try? JSONDecoder().decode(
            Meal.self, from: JSONEncoder().encode(edit.payload))
          {
            VStack(alignment: .leading) {
              Text(model.title(meal)).font(.headline)
              Text(meal.date)
              Text(LocalizedStringKey(meal.category)).foregroundStyle(.secondary)
            }
          }
        }
      }.navigationTitle("plan_preview")
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("cancel") { dismiss() } }
          ToolbarItem(placement: .confirmationAction) {
            Button("apply_plan") {
              saving = true
              Task {
                if await model.saveBatch(edits) { dismiss() }
                saving = false
              }
            }.disabled(edits.isEmpty || saving)
          }
        }
    }.safeAreaInset(edge: .bottom) { OperationErrorNotice() }
      .interactiveDismissDisabled(saving)
  }
}
struct RecurrenceEditor: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  let item: MealOccurrence
  @State private var interval = 1
  @State private var end = Date()
  var body: some View {
    NavigationStack {
      Form {
        Text("recurrence_series_hint")
        Stepper("every_weeks \(interval)", value: $interval, in: 1...52)
        DatePicker("repeat_until", selection: $end, displayedComponents: .date)
      }.navigationTitle("repeat_meal")
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("cancel") { dismiss() } }
          ToolbarItem(placement: .confirmationAction) {
            Button("save") {
              var meal = item.meal
              meal.recurrence = Recurrence(
                intervalWeeks: interval, until: model.dateString(end),
                exceptions: item.meal.recurrence?.exceptions ?? [])
              do {
                _ = try MealPlanning.occurrences(meal, from: item.date, through: item.date)
                Task {
                  if await model.save(kind: .meal, id: item.entityID, value: meal) { dismiss() }
                }
              } catch { model.report(error) }
            }
          }
        }
        .onAppear {
          interval = item.meal.recurrence?.intervalWeeks ?? 1
          end =
            localDate(item.meal.recurrence?.until)
            ?? Calendar.current.date(byAdding: .day, value: 28, to: localDate(item.date) ?? Date())
            ?? Date()
        }
    }.safeAreaInset(edge: .bottom) { OperationErrorNotice() }
      .environment(\.timeZone, TimeZone(identifier: model.householdTimeZone) ?? .current)
  }
  private func localDate(_ value: String?) -> Date? {
    guard let value else { return nil }
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: model.householdTimeZone)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.date(from: value)
  }
}
struct MealMoveEditor: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  let item: MealOccurrence
  @State private var date = Date()
  @State private var category = "dinner"
  var body: some View {
    NavigationStack {
      Form {
        DatePicker("meal_date", selection: $date, displayedComponents: .date)
        Picker("meal_category", selection: $category) {
          ForEach(["breakfast", "lunch", "dinner"], id: \.self) {
            Text(LocalizedStringKey($0)).tag($0)
          }
        }
      }.navigationTitle("move_meal")
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("cancel") { dismiss() } }
          ToolbarItem(placement: .confirmationAction) {
            Button("save") {
              do {
                let edits = try MealPlanning.moveOccurrence(
                  item, to: model.dateString(date), category: category)
                Task { if await model.saveBatch(edits) { dismiss() } }
              } catch { model.report(error) }
            }
          }
        }.onAppear {
          category = item.meal.category
          let formatter = DateFormatter()
          formatter.calendar = Calendar(identifier: .gregorian)
          formatter.locale = Locale(identifier: "en_US_POSIX")
          formatter.timeZone = TimeZone(identifier: model.householdTimeZone)
          formatter.dateFormat = "yyyy-MM-dd"
          date = formatter.date(from: item.date) ?? Date()
        }
    }.safeAreaInset(edge: .bottom) { OperationErrorNotice() }
      .environment(\.timeZone, TimeZone(identifier: model.householdTimeZone) ?? .current)
  }
}
struct PantryView: View {
  @Environment(AppModel.self) private var model
  @State private var name = ""
  @State private var search = ""
  var body: some View {
    List {
      Section { NavigationLink("leftovers") { LeftoversView() } }

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
      Section {
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
      } header: {
        Text("staples")
      } footer: {
        Text("pantry_exclusion_hint")
      }
    }.navigationTitle("pantry").searchable(text: $search)
  }
}
