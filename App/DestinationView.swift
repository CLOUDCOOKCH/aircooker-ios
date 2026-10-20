import AirCookerCore
import SwiftUI

struct DestinationView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  let destination: AppDestination
  var body: some View {
    NavigationStack {
      Group {
        switch destination {
        case .recipe(let id): RecipeDetail(id: id)
        case .calendar(let date): CalendarView(initialDate: date)
        case .meal(let id, let date):
          if let row = model.meals.first(where: { $0.id == id }),
            let meal = try? row.decode(Meal.self),
            (try? MealPlanning.occurrences(meal, from: date, through: date)) == [date]
          {
            RecipeDetail(id: meal.recipeID)
              .toolbar {
                NavigationLink("view_in_calendar") { CalendarView(initialDate: date) }
              }
          } else {
            ContentUnavailableView {
              Label("meal_unavailable", systemImage: "calendar.badge.exclamationmark")
            } actions: {
              NavigationLink("view_in_calendar") { CalendarView(initialDate: date) }
            }
          }
        }
      }.toolbar { ToolbarItem(placement: .cancellationAction) { Button("done") { dismiss() } } }
    }
  }
}
