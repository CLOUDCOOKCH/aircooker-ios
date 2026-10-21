import AirCookerCore
import SwiftUI

struct MealSlotSelection: Identifiable {
  let date: String
  let category: String
  var id: String { date + ":" + category }
}

/// Date-only labels deliberately format in UTC, independent of device travel.
enum KitchenDate {
  static func label(_ date: String, format: Date.FormatStyle) -> String {
    guard let value = try? PlanningDate.parse(date) else { return date }
    var format = format
    format.timeZone = TimeZone(secondsFromGMT: 0)!
    return value.formatted(format)
  }
}

struct PlannerWeekStrip: View {
  @Environment(\.locale) private var locale
  let overview: PlannerOverview
  let select: (String) -> Void
  let shift: (Int) -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      ViewThatFits(in: .horizontal) {
        HStack {
          month
          Spacer()
          actions
        }
        VStack(alignment: .leading, spacing: 6) {
          month
          actions
        }
      }
      ScrollViewReader { proxy in
        ScrollView(.horizontal) {
          HStack(spacing: 4) {
            ForEach(overview.days) { day in
              let selected = day.date == overview.selectedDate
              Button {
                select(day.date)
              } label: {
                VStack(spacing: 7) {
                  Text(
                    KitchenDate.label(day.date, format: .dateTime.weekday(.narrow).locale(locale))
                  )
                  .font(.caption.weight(.medium))
                  Text(KitchenDate.label(day.date, format: .dateTime.day().locale(locale)))
                    .font(.title3.weight(.semibold)).monospacedDigit()
                  Image(systemName: day.categories.isEmpty ? "circle" : "circle.fill")
                    .font(.caption2).imageScale(.small).accessibilityHidden(true)
                }
                .frame(minWidth: 44, minHeight: 76)
                .foregroundStyle(selected ? Color(uiColor: .systemBackground) : Color.primary)
                .background(
                  selected ? KitchenStyle.accent : Color.clear, in: Capsule())
              }.buttonStyle(.plain).id(day.date)
                .accessibilityLabel(
                  Text(
                    KitchenDate.label(
                      day.date,
                      format: .dateTime.weekday(.wide).day().month(.wide).locale(locale)))
                )
                .accessibilityValue(Text("planned_slots_count \(day.categories.count) \(3)"))
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityHint(day.isToday ? Text("today") : Text("select_planning_day"))
            }
          }.padding(6).kitchenGlass(in: Capsule()).padding(.vertical, 4)
        }.scrollIndicators(.hidden)
          .onChange(of: overview.selectedDate, initial: true) { _, date in
            proxy.scrollTo(date, anchor: .center)
          }
      }
    }
  }
  private var month: some View {
    Text(
      KitchenDate.label(
        overview.selectedDate,
        format: .dateTime.month(.wide).year().locale(locale))
    ).font(.headline)
  }
  private var actions: some View {
    HStack(spacing: 0) {
      Button("today") { select(overview.today) }.font(.subheadline).frame(minHeight: 44)
        .padding(.horizontal, 8)
      Button {
        shift(-7)
      } label: {
        Image(systemName: "chevron.left").frame(minWidth: 44, minHeight: 44)
      }.accessibilityLabel(Text("previous_week"))
      Button {
        shift(7)
      } label: {
        Image(systemName: "chevron.right").frame(minWidth: 44, minHeight: 44)
      }.accessibilityLabel(Text("next_week"))
    }.buttonStyle(.plain).kitchenGlass(in: Capsule())
  }
}

struct WeeklyPlanSummary: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let overview: PlannerOverview
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .firstTextBaseline) {
        Text(
          LocalizedStringKey(
            overview.days.contains(where: \.isToday) ? "this_week" : "weekly_planning")
        ).font(.headline)
        Spacer(minLength: 12)
        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
          .foregroundStyle(.secondary).accessibilityHidden(true)
      }
      Text("planned_slots_count \(overview.plannedSlots) \(overview.totalSlots)")
        .font(.title2.weight(.semibold)).monospacedDigit()
        .contentTransition(.numericText())
        .fixedSize(horizontal: false, vertical: true)
      ProgressView(value: Double(overview.plannedSlots), total: Double(overview.totalSlots))
        .accessibilityHidden(true)
    }.foregroundStyle(.primary).padding(20)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(KitchenStyle.surface, in: RoundedRectangle(cornerRadius: KitchenStyle.radius))
      .contentShape(RoundedRectangle(cornerRadius: KitchenStyle.radius))
      .accessibilityElement(children: .combine)
      .accessibilityHint(Text("view_in_calendar"))
      .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: overview.plannedSlots)
  }
}

struct FeaturedMealView: View {
  @Environment(AppModel.self) private var model
  let item: MealOccurrence
  var body: some View {
    let imageID = model.recipe(item.meal.recipeID)?.imageID
    VStack(alignment: .leading, spacing: 0) {
      if let imageID {
        RecipePhotoView(imageID: imageID).aspectRatio(3 / 2, contentMode: .fit)
          .overlay(alignment: .topLeading) {
            category.foregroundStyle(.primary)
              .padding(.horizontal, 14).padding(.vertical, 10)
              .kitchenGlass(in: Capsule()).padding(14)
          }
      }
      VStack(alignment: .leading, spacing: 10) {
        if imageID == nil { category.foregroundStyle(.secondary) }
        Text(model.title(item.meal)).font(.title2.weight(.semibold)).foregroundStyle(.primary)
          .fixedSize(horizontal: false, vertical: true)
        HStack {
          if item.meal.leftoverID != nil { Text("leftovers") }
          if item.meal.cooked { Label("cooked_meal", systemImage: "checkmark") }
          Spacer(minLength: 4)
          Label("view_recipe", systemImage: "arrow.up.right")
        }.font(.caption).foregroundStyle(.secondary)
      }.padding(20)
    }.background(KitchenStyle.surface)
      .clipShape(RoundedRectangle(cornerRadius: KitchenStyle.radius))
      .contentShape(RoundedRectangle(cornerRadius: KitchenStyle.radius))
      .accessibilityElement(children: .combine)
  }
  private var category: some View {
    Label(
      LocalizedStringKey(item.meal.category),
      systemImage: KitchenStyle.symbol(for: item.meal.category)
    ).font(.subheadline.weight(.medium))
  }
}

/// Used by both planning entry points. A save always uses the existing local
/// database + mutation transaction; offline mode never calls a separate API path.
struct MealAssignmentView: View {
  @Environment(AppModel.self) private var model
  let date: String
  let category: String
  let finished: () -> Void
  @State private var search = ""
  @State private var saving = false
  private var recipes: [LocalEntity] {
    model.recipes.filter {
      search.isEmpty
        || ((try? $0.decode(Recipe.self).title.localizedCaseInsensitiveContains(search)) ?? false)
    }
  }
  var body: some View {
    NavigationStack {
      List {
        Section {
          Label(LocalizedStringKey(category), systemImage: KitchenStyle.symbol(for: category))
          Text(KitchenDate.label(date, format: .dateTime.weekday(.wide).day().month(.wide)))
            .foregroundStyle(.secondary)
        }
        if recipes.isEmpty {
          if model.recipes.isEmpty {
            ContentUnavailableView(
              "recipe_library_empty", systemImage: "book.closed",
              description: Text("recipe_library_empty_hint"))
            NavigationLink("import_recipe") { ImportView() }
          } else {
            ContentUnavailableView.search(text: search)
          }
        }
        Section("recipes") {
          ForEach(recipes) { row in
            if let recipe = try? row.decode(Recipe.self) {
              Button {
                guard !saving else { return }
                saving = true
                let meal = Meal(
                  recipeID: row.id, date: date, category: category, servings: recipe.servings)
                Task {
                  if await model.save(kind: .meal, value: meal) { finished() }
                  saving = false
                }
              } label: {
                RecipeListRow(recipe: recipe)
              }.disabled(saving).buttonStyle(.plain)
            }
          }
        }
        Section("leftovers") {
          ForEach(model.leftovers.filter { model.canScheduleLeftover($0) }) { row in
            if let leftover = try? row.decode(Leftover.self) {
              NavigationLink {
                LeftoverScheduleView(row: row, initialDate: date, initialCategory: category)
              } label: {
                VStack(alignment: .leading, spacing: 6) {
                  Text(
                    model.recipe(leftover.recipeID)?.title
                      ?? String(localized: "recipe_unavailable"))
                  Text("available_portions \(model.availablePortions(row))").font(.caption)
                    .foregroundStyle(.secondary)
                }
              }.disabled(saving)
            }
          }
        }
      }.searchable(text: $search).navigationTitle("choose_recipe")
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("cancel") { finished() }.disabled(saving)
          }
        }
    }.safeAreaInset(edge: .bottom) { OperationErrorNotice() }
      .interactiveDismissDisabled(saving)
  }
}

struct RecipeListRow: View {
  let recipe: Recipe
  var body: some View {
    HStack(spacing: 14) {
      RecipePhotoView(imageID: recipe.imageID).frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 12))
      VStack(alignment: .leading, spacing: 6) {
        Text(recipe.title).font(.headline).foregroundStyle(.primary)
          .fixedSize(horizontal: false, vertical: true)
        ViewThatFits(in: .horizontal) {
          HStack(spacing: 12) { details }
          VStack(alignment: .leading, spacing: 4) { details }
        }.font(.caption).foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
    }.padding(.vertical, 4).contentShape(Rectangle())
      .accessibilityElement(children: .combine)
  }
  @ViewBuilder private var details: some View {
    Text("ingredient_count \(recipe.ingredients.count)")
    if let rating = recipe.rating {
      Label("recipe_rating \(rating)", systemImage: "star.fill")
    }
  }
}
