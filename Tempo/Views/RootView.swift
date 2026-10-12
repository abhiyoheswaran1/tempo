import SwiftUI
import TempoCore

struct RootView: View {
  @Environment(AppModel.self) var model
  @State private var settings = false
  @State private var activeWorkoutSheet = false
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.dynamicTypeSize) private var textSize
  var body: some View {
    VStack(spacing: 0) {
      if model.demo {
        Text(
          textSize.isAccessibilitySize
            ? "DEMO · Synthetic data" : "DEMO · Synthetic data · Cloud and Health disabled"
        ).font(.caption.weight(.semibold))
          .frame(maxWidth: .infinity).padding(8).background(.yellow.opacity(0.2))
          .accessibilityLabel("DEMO · Synthetic data · Cloud and Health disabled")
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
      }.modifier(
        WorkoutAccessoryModifier(
          enabled: model.activeWorkout != nil, open: { activeWorkoutSheet = true }))
    }
    .tint(.teal)
    .disabled(model.transitioningDataset)
    .sheet(isPresented: $settings) { NavigationStack { SettingsView() } }
    .sheet(isPresented: $activeWorkoutSheet) { NavigationStack { ActiveWorkoutSheet() } }
    .sheet(
      item: Binding(
        get: { activeWorkoutSheet ? nil : model.finishedWorkout },
        set: { model.finishedWorkout = $0 })
    ) { workout in
      NavigationStack {
        WorkoutDetailView(workout: workout, title: "Workout summary").toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") { model.finishedWorkout = nil }
          }
        }
      }
    }
    .alert(
      "Tempo needs attention",
      isPresented: Binding(
        get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    ) {
      Button("OK") { model.errorMessage = nil }
    } message: {
      Text(model.errorMessage ?? "")
    }
    .task(id: scenePhase) {
      guard scenePhase == .active else { return }
      while !Task.isCancelled {
        if !model.demo, !model.transitioningDataset { model.bluetooth.checkCollectionHealth() }
        do { try await Task.sleep(for: .seconds(20)) } catch { return }
      }
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { Task { await model.onForegroundActive() } }
    }
  }
  @ToolbarContentBuilder var statusControl: some ToolbarContent {
    ToolbarItem(placement: .topBarTrailing) {
      TimelineView(.periodic(from: .now, by: 60)) { context in
        Button {
          settings = true
        } label: {
          HStack(spacing: 8) {
            if !model.demo, let device = model.collectionDevice,
              model.bluetooth.isConnected(device.id),
              let battery = model.bluetooth.battery[device.id], battery.isFresh(at: context.date)
            {
              Label(
                "\(battery.percent)%",
                systemImage: battery.percent <= 25
                  ? "battery.25percent"
                  : (battery.percent <= 50
                    ? "battery.50percent"
                    : (battery.percent <= 75 ? "battery.75percent" : "battery.100percent"))
              )
              .font(.caption.weight(.medium)).monospacedDigit()
            }
            Image(
              systemName: model.bluetooth.connected.isEmpty
                ? "person.crop.circle" : "person.crop.circle.badge.checkmark")
          }
        }.accessibilityLabel("Bands, sync and settings")
          .accessibilityValue(batteryAccessibility(at: context.date))
      }
    }
  }
  private func batteryAccessibility(at now: Date) -> String {
    guard !model.demo, let device = model.collectionDevice, model.bluetooth.isConnected(device.id),
      let battery = model.bluetooth.battery[device.id], battery.isFresh(at: now)
    else { return "" }
    return "\(device.name), reported battery \(battery.percent) percent"
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
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .firstTextBaseline) {
        labels
        Spacer(minLength: 16)
        Text(value).font(.headline).monospacedDigit().fixedSize()
      }
      VStack(alignment: .leading, spacing: 4) {
        labels
        Text(value).font(.headline).monospacedDigit()
      }
    }.accessibilityElement(children: .combine)
  }
  var labels: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label)
      if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
    }
  }
}
func durationText(_ seconds: Double) -> String {
  guard seconds.isFinite else { return "Unavailable" }
  let total = Int(max(0, seconds))
  if total < 60 { return "\(total)s" }
  if total < 3600 { return "\(total/60)m" }
  return "\(total/3600)h \((total%3600)/60)m"
}

private struct WorkoutAccessoryModifier: ViewModifier {
  var enabled: Bool
  var open: () -> Void
  @ViewBuilder func body(content: Content) -> some View {
    if #available(iOS 26.1, *) {
      content.tabViewBottomAccessory(isEnabled: enabled) { ActiveWorkoutAccessory(open: open) }
    } else {
      content.tabViewBottomAccessory { if enabled { ActiveWorkoutAccessory(open: open) } }
    }
  }
}
