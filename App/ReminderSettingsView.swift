import AirCookerCore
import SwiftUI
import UIKit

struct ReminderSettingsView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.openURL) private var openURL
  @State private var changingPermission = false
  private let categories = ["breakfast", "lunch", "dinner"]
  var body: some View {
    Form {
      Section {
        Toggle(
          "enable_meal_reminders",
          isOn: Binding(
            get: { model.reminderPreferences.enabled },
            set: { value in
              changingPermission = true
              Task {
                await model.setRemindersEnabled(value)
                changingPermission = false
              }
            })
        ).disabled(changingPermission)
        if model.reminderPermission == "denied" {
          Text("notification_permission_denied")
          Button("open_system_settings") {
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
          }
        }
      } footer: {
        Text("reminder_timezone_hint")
      }
      if model.reminderPreferences.enabled {
        Section("reminder_times") {
          ForEach(categories, id: \.self) { category in
            Toggle(
              LocalizedStringKey(category),
              isOn: Binding(
                get: { model.reminderPreferences.times[category] != nil },
                set: { value in
                  var preferences = model.reminderPreferences
                  preferences.times[category] =
                    value ? ReminderTime(hour: defaultHour(category)) : nil
                  model.updateReminderPreferences(preferences)
                }))
            if model.reminderPreferences.times[category] != nil {
              DatePicker(
                "reminder_time", selection: clockBinding(category),
                displayedComponents: .hourAndMinute)
            }
          }
        }
        Section {
          Toggle(
            "reminder_recipe_names",
            isOn: Binding(
              get: { model.reminderPreferences.showRecipeNames },
              set: { value in
                var preferences = model.reminderPreferences
                preferences.showRecipeNames = value
                model.updateReminderPreferences(preferences)
              }))
          Text("reminder_names_privacy").font(.footnote).foregroundStyle(.secondary)
          LabeledContent("scheduled_reminders", value: String(model.scheduledReminders))
        }
      }
      Section {
        Toggle(
          "widget_meal_names",
          isOn: Binding(
            get: { model.showWidgetNames },
            set: { value in model.setWidgetNames(value) }))
      } footer: {
        Text("widget_names_privacy")
      }
    }.navigationTitle("reminders_widgets")
      .safeAreaInset(edge: .bottom) { OperationErrorNotice() }
      .environment(\.timeZone, TimeZone(identifier: model.householdTimeZone) ?? .current)
      .task { await model.refreshReminderStatus() }
  }
  private func defaultHour(_ category: String) -> Int {
    category == "breakfast" ? 8 : category == "lunch" ? 12 : 18
  }
  private func clockBinding(_ category: String) -> Binding<Date> {
    Binding(
      get: {
        let time =
          model.reminderPreferences.times[category] ?? ReminderTime(hour: defaultHour(category))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: model.householdTimeZone) ?? .current
        return calendar.date(
          from: DateComponents(year: 2001, month: 1, day: 1, hour: time.hour, minute: time.minute))
          ?? Date()
      },
      set: { date in
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: model.householdTimeZone) ?? .current
        let components = calendar.dateComponents([.hour, .minute], from: date)
        var preferences = model.reminderPreferences
        preferences.times[category] = ReminderTime(
          hour: components.hour ?? 8, minute: components.minute ?? 0)
        model.updateReminderPreferences(preferences)
      })
  }
}
