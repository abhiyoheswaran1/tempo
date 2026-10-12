import SwiftUI
import TempoCore

struct RootView: View {
  @Environment(AppModel.self) var model
  @State private var settings = false
  @Environment(\.scenePhase) private var scenePhase
  var body: some View {
    VStack(spacing: 0) {
      if model.demo {
        Text("DEMO · Synthetic data · Cloud and Health disabled").font(.caption.weight(.semibold))
          .frame(maxWidth: .infinity).padding(8).background(.yellow.opacity(0.2))
      }
      TabView {
        Tab("Today", systemImage: "sun.max") {
          NavigationStack { TodayView().toolbar { statusControl } }
        }
        Tab("Activity", systemImage: "figure.run") {
          NavigationStack { ActivityView().toolbar { statusControl } }
        }
        Tab("Trends", systemImage: "chart.xyaxis.line") {
          NavigationStack { TrendsView().toolbar { statusControl } }
        }
      }
    }
    .tint(.teal)
    .disabled(model.transitioningDataset)
    .sheet(isPresented: $settings) { NavigationStack { SettingsView() } }
    .alert(
      "Tempo needs attention",
      isPresented: Binding(
        get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    ) {
      Button("OK") { model.errorMessage = nil }
    } message: {
      Text(model.errorMessage ?? "")
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active && model.syncEnabled { Task { await model.sync() } }
    }
  }
  @ToolbarContentBuilder var statusControl: some ToolbarContent {
    ToolbarItem(placement: .topBarTrailing) {
      Button {
        settings = true
      } label: {
        Image(
          systemName: model.bluetooth.connected.isEmpty
            ? "person.crop.circle" : "person.crop.circle.badge.checkmark")
      }.accessibilityLabel("Bands, sync and settings")
    }
  }
}
struct ContentSection<Content: View>: View {
  var title: String
  var subtitle: String?
  @ViewBuilder var content: Content
  init(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
    self.title = title
    self.subtitle = subtitle
    self.content = content()
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text(title).font(.title3.weight(.semibold))
        if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
      }
      content
    }.frame(maxWidth: .infinity, alignment: .leading).padding(20).background(
      Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
  }
}
struct MetricRow: View {
  var label: String
  var value: String
  var detail: String? = nil
  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      VStack(alignment: .leading, spacing: 4) {
        Text(label)
        if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
      }
      Spacer()
      Text(value).font(.headline).monospacedDigit()
    }.accessibilityElement(children: .combine)
  }
}
func durationText(_ seconds: Double) -> String {
  let minutes = Int(max(0, seconds) / 60)
  return "\(minutes/60)h \(minutes%60)m"
}
