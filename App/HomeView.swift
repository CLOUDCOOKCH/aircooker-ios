import AirCookerCore
import SwiftUI

struct HomeView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.horizontalSizeClass) private var sizeClass
  @Environment(\.dynamicTypeSize) private var typeSize
  @Environment(\.scenePhase) private var phase
  @Environment(\.locale) private var locale
  @State private var newRecipe = false
  @State private var selectedDate: String?
  @State private var now = Date()
  @State private var overview: PlannerOverview?
  @State private var overviewFailed = false
  @State private var assigning: MealSlotSelection?
  @ScaledMetric(relativeTo: .body) private var recipeWidth: CGFloat = 240
  private var refreshKey: String {
    "\(selectedDate ?? "today"):\(model.photoRevision):\(model.householdTimeZone):\(now.timeIntervalSince1970)"
  }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        if let overview {
          PlannerWeekStrip(overview: overview, select: { selectedDate = $0 }, shift: shift)
          if sizeClass == .regular && !typeSize.isAccessibilitySize {
            HStack(alignment: .top, spacing: 28) {
              dailyPlan(overview).frame(maxWidth: .infinity, alignment: .leading)
              kitchen(overview).frame(width: 300)
            }
          } else {
            dailyPlan(overview)
            kitchen(overview)
          }
        } else if overviewFailed {
          ContentUnavailableView {
            Label("planning_unavailable", systemImage: "calendar.badge.exclamationmark")
          } description: {
            Text("planning_retry_hint")
          } actions: {
            Button("retry") { now = Date() }.buttonStyle(.bordered)
          }
        } else {
          ProgressView("loading_plan").frame(maxWidth: .infinity).padding(.vertical, 32)
        }
      }.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 32)
        .frame(maxWidth: 1100, alignment: .leading).frame(maxWidth: .infinity)
    }.background(KitchenStyle.background).navigationTitle("your_kitchen")
      .toolbar {
        ToolbarItemGroup(placement: .topBarTrailing) {
          NavigationLink {
            ImportView()
          } label: {
            Label("import_recipe", systemImage: "square.and.arrow.down")
          }
          Button("create_recipe", systemImage: "plus") { newRecipe = true }
        }
      }
      .refreshable { await model.synchronise() }
      .sheet(isPresented: $newRecipe) { RecipeEditor() }
      .sheet(item: $assigning) { slot in
        MealAssignmentView(date: slot.date, category: slot.category) { assigning = nil }
      }
      .task(id: refreshKey) {
        do {
          overview = try PlannerOverview.build(
            meals: model.meals, now: now,
            timeZone: model.householdTimeZone, selectedDate: selectedDate)
          overviewFailed = false
        } catch {
          overviewFailed = true
          model.report(error)
        }
      }
      .task {
        while !Task.isCancelled {
          now = Date()
          do { try await Task.sleep(for: .seconds(60)) } catch { return }
        }
      }
      .onChange(of: phase) { _, phase in if phase == .active { now = Date() } }
  }
  @ViewBuilder private func dailyPlan(_ overview: PlannerOverview) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 5) {
          Text(
            LocalizedStringKey(
              overview.selectedDate == overview.today ? "today_meals" : "on_your_menu")
          )
          .font(.title2.weight(.semibold))
          Text(
            KitchenDate.label(
              overview.selectedDate,
              format: .dateTime.weekday(.wide).day().month(.wide).locale(locale))
          )
          .font(.subheadline).foregroundStyle(.secondary)
        }
        Spacer(minLength: 4)
        NavigationLink {
          CalendarView(initialDate: overview.selectedDate)
        } label: {
          Image(systemName: "calendar").frame(minWidth: 44, minHeight: 44)
        }.accessibilityLabel(Text("calendar"))
      }
      if let featured = overview.selectedMeals.first(where: { !$0.meal.cooked })
        ?? overview.selectedMeals.first
      {
        NavigationLink {
          RecipeDetail(id: featured.meal.recipeID)
        } label: {
          FeaturedMealView(item: featured)
        }.buttonStyle(.plain)
        ForEach(overview.selectedMeals.filter { $0.id != featured.id }) { item in
          NavigationLink {
            RecipeDetail(id: item.meal.recipeID)
          } label: {
            MealRow(item: item)
          }
          .buttonStyle(.plain)
        }
      }
      let occupied = Set(overview.selectedMeals.map { $0.meal.category })
      VStack(spacing: 0) {
        ForEach(PlannerOverview.categories.filter { !occupied.contains($0) }, id: \.self) {
          category in
          Button {
            assigning = MealSlotSelection(date: overview.selectedDate, category: category)
          } label: {
            HStack(spacing: 12) {
              Image(systemName: KitchenStyle.symbol(for: category)).frame(width: 24)
              Text(LocalizedStringKey(category)).foregroundStyle(.primary)
              Spacer(minLength: 8)
              Image(systemName: "plus").foregroundStyle(.secondary)
            }.padding(.vertical, 18).contentShape(Rectangle())
          }.buttonStyle(.plain).accessibilityLabel(Text(LocalizedStringKey(category)))
            .accessibilityHint(Text("plan_meal"))
          if category != PlannerOverview.categories.last(where: { !occupied.contains($0) }) {
            Divider()
          }
        }
      }.padding(.horizontal, 18)
        .background(KitchenStyle.surface, in: RoundedRectangle(cornerRadius: KitchenStyle.radius))
      if !overview.selectedMeals.isEmpty {
        Menu {
          ForEach(PlannerOverview.categories, id: \.self) { category in
            Button(LocalizedStringKey(category)) {
              assigning = MealSlotSelection(date: overview.selectedDate, category: category)
            }
          }
        } label: {
          Label("add_meal", systemImage: "plus").frame(minHeight: 44)
        }
      }
    }
  }
  private func kitchen(_ overview: PlannerOverview) -> some View {
    VStack(alignment: .leading, spacing: 28) {
      VStack(alignment: .leading, spacing: 14) {
        NavigationLink {
          CalendarView(initialDate: overview.selectedDate)
        } label: {
          WeeklyPlanSummary(overview: overview)
        }.buttonStyle(.plain)
        NavigationLink {
          SuggestionsView(week: overview.monday)
        } label: {
          Label("weekly_suggestions", systemImage: "sparkles").frame(maxWidth: .infinity)
        }.buttonStyle(.bordered).controlSize(.large)
        NavigationLink {
          LeftoversView()
        } label: {
          Label("leftovers", systemImage: "takeoutbag.and.cup.and.straw").frame(minHeight: 44)
        }
      }
      Divider()
      VStack(alignment: .leading, spacing: 16) {
        HStack {
          Text("from_your_recipes").font(.title2.weight(.semibold))
          Spacer(minLength: 4)
          NavigationLink {
            RecipesView()
          } label: {
            Image(systemName: "arrow.up.right").frame(minWidth: 44, minHeight: 44)
          }.accessibilityLabel(Text("recipes"))
        }
        if model.recipes.isEmpty {
          Text("recipe_library_empty_hint").foregroundStyle(.secondary)
          Button("create_recipe", systemImage: "plus") { newRecipe = true }
            .buttonStyle(.bordered).controlSize(.large)
        } else {
          ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 14) {
              ForEach(Array(model.recipes.prefix(6))) { row in
                if let recipe = try? row.decode(Recipe.self) {
                  NavigationLink {
                    RecipeDetail(id: row.id)
                  } label: {
                    RecipeCard(recipe: recipe).frame(width: recipeWidth)
                  }.buttonStyle(.plain)
                }
              }
            }.padding(.vertical, 4)
          }.scrollIndicators(.hidden)
        }
      }
    }
  }
  private func shift(_ offset: Int) {
    guard let overview else { return }
    do { selectedDate = try PlanningDate.adding(offset, to: overview.selectedDate) } catch {
      model.report(error)
    }
  }
}
