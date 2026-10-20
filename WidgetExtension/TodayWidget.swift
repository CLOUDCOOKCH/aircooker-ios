import SwiftUI
import WidgetKit

private struct CachedMeal: Decodable, Identifiable {
  var id: String
  var category: String
  var title: String
}
private struct Snapshot: Decodable {
  var date: String
  var meals: [CachedMeal]
}
private struct Entry: TimelineEntry {
  let date: Date
  let snapshot: Snapshot?
}
private struct Provider: TimelineProvider {
  func placeholder(in context: Context) -> Entry { Entry(date: Date(), snapshot: nil) }
  func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
    completion(read())
  }
  func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
    completion(Timeline(entries: [read()], policy: .after(Date().addingTimeInterval(3600))))
  }
  private func read() -> Entry {
    guard let group = Bundle.main.object(forInfoDictionaryKey: "AirCookerAppGroup") as? String,
      let directory = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: group),
      let data = try? Data(contentsOf: directory.appending(path: "today.json")),
      let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
    else { return Entry(date: Date(), snapshot: nil) }
    return Entry(date: Date(), snapshot: snapshot)
  }
}
private struct TodayView: View {
  let entry: Entry
  @Environment(\.widgetFamily) var family
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("aircooker", systemImage: "fork.knife").font(.headline)
      if let snapshot = entry.snapshot {
        Text(snapshot.date).font(.caption).foregroundStyle(.secondary)
        if snapshot.meals.isEmpty { Text("nothing_planned").font(.caption) }
        ForEach(Array(snapshot.meals.prefix(family == .systemSmall ? 1 : 3))) { meal in
          Link(destination: URL(string: "aircooker://meal/" + meal.id)!) {
            VStack(alignment: .leading) {
              Text(LocalizedStringKey(meal.category)).font(.caption2).foregroundStyle(.secondary)
              Text(meal.title).font(.subheadline).lineLimit(2)
            }
          }
        }
      } else {
        Text("widget_open_app").font(.caption).foregroundStyle(.secondary)
      }
    }.frame(maxWidth: .infinity, alignment: .leading).containerBackground(
      .fill.tertiary, for: .widget)
  }
}
@main struct TodayWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "aircooker.today", provider: Provider()) { TodayView(entry: $0) }
      .configurationDisplayName("widget_name").description("widget_description").supportedFamilies([
        .systemSmall, .systemMedium, .systemLarge,
      ])
  }
}
