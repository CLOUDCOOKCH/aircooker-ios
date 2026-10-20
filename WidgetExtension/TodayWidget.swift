import AirCookerCore
import SwiftUI
import WidgetKit

private struct Entry: TimelineEntry {
  let date: Date
  let snapshot: MealWidgetSnapshot?
  var day: WidgetDay? { snapshot?.day(at: date) }
}
private struct Provider: TimelineProvider {
  func placeholder(in context: Context) -> Entry { Entry(date: Date(), snapshot: nil) }
  func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
    completion(Entry(date: Date(), snapshot: read()))
  }
  func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
    let now = Date()
    let snapshot = read()
    let dates = (try? snapshot?.timelineDates(after: now)) ?? [now]
    completion(
      Timeline(
        entries: dates.map { Entry(date: $0, snapshot: snapshot) },
        policy: .after(now.addingTimeInterval(6 * 3600))))
  }
  private func read() -> MealWidgetSnapshot? {
    guard let group = Bundle.main.object(forInfoDictionaryKey: "AirCookerAppGroup") as? String,
      let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    else { return nil }
    let file = directory.appending(path: "meals-widget-v1.json")
    guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
      size <= 1_048_576, let data = try? Data(contentsOf: file)
    else { return nil }
    return try? MealWidgetSnapshot.decode(data)
  }
}
private struct TodayView: View {
  let entry: Entry
  @Environment(\.widgetFamily) private var family
  var body: some View {
    VStack(alignment: .leading, spacing: family == .systemSmall ? 4 : 8) {
      Text("aircooker").font(.headline)
      if let day = entry.day {
        if family == .systemMedium {
          HStack(alignment: .top, spacing: 12) {
            ForEach(day.slots) { slot in
              slotView(slot).frame(maxWidth: .infinity, alignment: .leading)
            }
          }
        } else {
          ForEach(day.slots) { slot in slotView(slot) }
        }
      } else {
        Text("widget_open_app").font(.caption).foregroundStyle(.secondary)
      }
    }.frame(maxWidth: .infinity, alignment: .leading)
      .widgetURL(entry.day.map { AppDestination.calendar(date: $0.date).url })
      .containerBackground(.fill.tertiary, for: .widget)
  }
  @ViewBuilder private func slotView(_ slot: WidgetSlot) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(LocalizedStringKey(slot.category)).font(.caption2).foregroundStyle(.secondary)
      if slot.meals.isEmpty { Text("widget_unplanned").font(.caption) }
      ForEach(Array(slot.meals.prefix(family == .systemLarge ? 3 : 1))) { meal in
        if family == .systemSmall {
          Text(meal.title ?? String(localized: "widget_meal_planned")).font(.caption).lineLimit(1)
        } else {
          Link(destination: meal.destination.url) {
            Text(meal.title ?? String(localized: "widget_meal_planned"))
              .font(.subheadline).lineLimit(2)
          }
        }
      }
      let remaining =
        slot.additionalCount + max(0, slot.meals.count - (family == .systemLarge ? 3 : 1))
      if remaining > 0 {
        Text("widget_more_count \(remaining)").font(.caption2).foregroundStyle(.secondary)
      }
    }
  }
}
@main struct TodayWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "aircooker.today", provider: Provider()) { TodayView(entry: $0) }
      .configurationDisplayName("widget_name").description("widget_description")
      .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}
