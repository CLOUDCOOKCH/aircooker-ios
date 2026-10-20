import AirCookerCore
import Foundation
import UserNotifications

actor MealReminders {
  func schedule(
    meals: [LocalEntity], timeZone: TimeZone, hour: Int, minute: Int, enabledCategories: Set<String>
  ) async throws {
    let center = UNUserNotificationCenter.current()
    guard try await center.requestAuthorization(options: [.alert, .sound]) else { return }
    let existing = await center.pendingNotificationRequests()
    center.removePendingNotificationRequests(
      withIdentifiers: existing.filter { $0.identifier.hasPrefix("aircooker.meal.") }.map(
        \.identifier))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    // Leave room under iOS's pending request limit and do not promise exact background execution.
    for row in meals.sorted(by: { $0.id.uuidString < $1.id.uuidString }).prefix(50) {
      guard let meal = try? row.decode(Meal.self), enabledCategories.contains(meal.category) else {
        continue
      }
      let parts = meal.date.split(separator: "-").compactMap { Int($0) }
      guard parts.count == 3 else { continue }
      var components = DateComponents()
      components.calendar = calendar
      components.timeZone = timeZone
      components.year = parts[0]
      components.month = parts[1]
      components.day = parts[2]
      components.hour = hour
      components.minute = minute
      guard let fireDate = calendar.date(from: components), fireDate > Date() else { continue }
      let content = UNMutableNotificationContent()
      content.title = String(localized: "meal_reminder")
      content.body = String(localized: "meal_reminder_body")
      content.sound = .default
      content.userInfo = ["meal_id": row.id.uuidString]
      let request = UNNotificationRequest(
        identifier: "aircooker.meal." + row.id.uuidString, content: content,
        trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
      try await center.add(request)
    }
  }
  func disable() async {
    let center = UNUserNotificationCenter.current()
    let pending = await center.pendingNotificationRequests()
    center.removePendingNotificationRequests(
      withIdentifiers: pending.filter { $0.identifier.hasPrefix("aircooker.meal.") }.map(
        \.identifier))
  }
}
