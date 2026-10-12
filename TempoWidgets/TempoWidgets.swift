import ActivityKit
import SwiftUI
import WidgetKit

struct SummaryEntry: TimelineEntry {
  let date: Date
  let updated: Date?
  let readiness: Int?
  let sleep: Double?
  let privateMode: Bool
}
struct SummaryProvider: TimelineProvider {
  func placeholder(in context: Context) -> SummaryEntry {
    SummaryEntry(date: Date(), updated: nil, readiness: nil, sleep: nil, privateMode: true)
  }
  func getSnapshot(in context: Context, completion: @escaping (SummaryEntry) -> Void) {
    completion(read())
  }
  func getTimeline(in context: Context, completion: @escaping (Timeline<SummaryEntry>) -> Void) {
    completion(Timeline(entries: [read()], policy: .after(Date().addingTimeInterval(1800))))
  }
  private func read() -> SummaryEntry {
    let group =
      Bundle.main.object(forInfoDictionaryKey: "TempoAppGroup") as? String
      ?? "group.app.tempo.personal"
    let d = UserDefaults(suiteName: group)
    let timestamp = d?.double(forKey: "updated") ?? 0
    let readiness = d?.integer(forKey: "readiness") ?? -1
    let sleep = d?.double(forKey: "sleep") ?? -1
    return SummaryEntry(
      date: Date(), updated: timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil,
      readiness: readiness >= 0 ? readiness : nil, sleep: sleep > 0 ? sleep : nil,
      privateMode: d?.object(forKey: "private") as? Bool ?? true)
  }
}
struct SummaryWidgetView: View {
  var entry: SummaryEntry
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label {
        Text("Tempo")
      } icon: {
        Image("TempoMark").resizable().scaledToFit().frame(width: 28, height: 28)
      }.font(.headline).foregroundStyle(.teal)
      if entry.privateMode {
        Text("Your day, at a glance").font(.subheadline)
        Text("Open Tempo to see your measurements").font(.caption).foregroundStyle(.secondary)
      } else {
        Text(entry.readiness.map { "Readiness \($0)" } ?? "Baseline building").font(.title3)
        if let sleep = entry.sleep {
          Text("Sleep \(Int(sleep/3600))h \(Int(sleep/60)%60)m").font(.subheadline)
        }
      }
      if let updated = entry.updated {
        Text("Updated \(updated.formatted(date:.omitted,time:.shortened))").font(.caption2)
          .foregroundStyle(.secondary)
      } else {
        Text("No summary yet").font(.caption2)
      }
    }.containerBackground(.background, for: .widget).privacySensitive(!entry.privateMode)
  }
}
struct TempoSummaryWidget: Widget {
  let kind = "TempoSummary"
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: SummaryProvider()) { SummaryWidgetView(entry: $0) }
      .configurationDisplayName("Tempo daily summary").description(
        "A quiet summary with timestamp and privacy control."
      ).supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
  }
}
struct TempoWorkoutActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: TempoActivityAttributes.self) { context in
      HStack {
        VStack(alignment: .leading) {
          Text(context.attributes.activity).font(.headline)
          Text(context.state.paused ? "Paused" : "Workout in progress").font(.caption)
          Text("Updated \(context.state.updatedAt.formatted(date:.omitted,time:.shortened))").font(
            .caption2)
        }
        Spacer()
        Text(context.isStale ? "HR stale" : context.state.heartRate.map { "\($0) bpm" } ?? "No HR")
          .monospacedDigit()
      }.padding().activityBackgroundTint(Color(uiColor: .secondarySystemBackground))
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) { Text(context.attributes.activity).font(.headline) }
        DynamicIslandExpandedRegion(.trailing) {
          Text(context.isStale ? "Stale" : context.state.heartRate.map { "\($0) bpm" } ?? "—")
        }
        DynamicIslandExpandedRegion(.bottom) {
          HStack {
            Text(context.state.source).font(.caption)
            Spacer()
            Link(
              context.state.paused ? "Resume in Tempo" : "Open workout",
              destination: URL(string: "tempo://workout")!)
          }
        }
      } compactLeading: {
        Image(systemName: "figure.run")
      } compactTrailing: {
        Text(context.isStale ? "—" : context.state.heartRate.map { String($0) } ?? "—")
      } minimal: {
        Image(systemName: "figure.run")
      }.widgetURL(URL(string: "tempo://workout"))
    }
  }
}
@main struct TempoWidgetBundle: WidgetBundle {
  var body: some Widget {
    TempoSummaryWidget()
    TempoWorkoutActivity()
  }
}
