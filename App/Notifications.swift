import MealfCore
import Foundation
import UserNotifications

actor MealReminders {
  private let center = UNUserNotificationCenter.current()
  private var desired: [PlannedReminder] = []
  private var includeNames = false
  private var generation = 0
  private var running = false

  func requestPermission() async throws -> Bool {
    try await center.requestAuthorization(options: [.alert, .sound])
  }
  func permission() async -> String {
    switch await center.notificationSettings().authorizationStatus {
    case .authorized, .provisional, .ephemeral: return "authorized"
    case .denied: return "denied"
    case .notDetermined: return "not_determined"
    @unknown default: return "unknown"
    }
  }
  func count() async -> Int {
    await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix("mealf.meal.") }
      .count
  }
  func reconcile(_ plan: [PlannedReminder], showRecipeNames: Bool) async throws {
    desired = plan
    includeNames = showRecipeNames
    generation += 1
    guard !running else { return }
    running = true
    defer { running = false }
    while true {
      let current = generation
      let items = desired
      let names = includeNames
      let permitted = await permission() == "authorized"
      let pending = await center.pendingNotificationRequests()
      let owned = pending.filter { $0.identifier.hasPrefix("mealf.meal.") }
      let ids = permitted ? Set(items.map(\.id)) : []
      center.removePendingNotificationRequests(
        withIdentifiers: owned.filter { !ids.contains($0.identifier) }.map(\.identifier))
      if permitted {
        for item in items {
          let content = UNMutableNotificationContent()
          content.title = String(localized: "meal_reminder")
          content.body =
            names && !item.recipeTitles.isEmpty
            ? item.recipeTitles.prefix(3).joined(separator: ", ")
            : String(localized: "meal_reminder_body")
          content.sound = .default
          content.userInfo = [
            "url": item.destination.url.absoluteString,
            "fire_date": item.fireDate.timeIntervalSince1970,
          ]
          let existing = owned.first { $0.identifier == item.id }
          if existing?.content.title == content.title, existing?.content.body == content.body,
            existing?.content.userInfo["fire_date"] as? Double
              == item.fireDate.timeIntervalSince1970,
            existing?.content.userInfo["url"] as? String == item.destination.url.absoluteString
          {
            continue
          }
          // Use absolute UTC components so a repeated autumn clock hour fires once,
          // at the exact instant selected by the household-zone planner.
          var calendar = Calendar(identifier: .gregorian)
          calendar.timeZone = TimeZone(secondsFromGMT: 0)!
          var components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: item.fireDate)
          components.calendar = calendar
          components.timeZone = calendar.timeZone
          let request = UNNotificationRequest(
            identifier: item.id, content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
          try await center.add(request)
        }
      }
      if current == generation { break }
    }
  }
}

final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
  private let open: @MainActor @Sendable (URL) -> Void
  init(open: @escaping @MainActor @Sendable (URL) -> Void) { self.open = open }
  func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
  ) async {
    guard let raw = response.notification.request.content.userInfo["url"] as? String,
      let url = URL(string: raw), AppDestination(url: url) != nil
    else { return }
    await open(url)
  }
  func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .sound]
  }
}
