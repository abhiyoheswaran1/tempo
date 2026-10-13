import Charts
import SwiftUI
import TempoCore

private enum TrendMetric: String, CaseIterable {
  case heartRate, restingHeartRate, rmssd, sdnn, sleep, weight
  var kind: MetricKind? { MetricKind(rawValue: rawValue) }
  var title: String {
    switch self {
    case .heartRate: "Heart rate"
    case .restingHeartRate: "Resting heart rate"
    case .rmssd: "HRV · RMSSD"
    case .sdnn: "HRV · SDNN"
    case .sleep: "Sleep duration"
    case .weight: "Weight"
    }
  }
  var unit: String {
    switch self {
    case .weight: "kg"
    case .rmssd, .sdnn: "ms"
    case .sleep: "hours"
    default: "bpm"
    }
  }
  var method: String {
    switch self {
    case .heartRate: "Average during measured periods, not an all-day or resting heart rate."
    case .weight: "Latest available weight each day."
    case .sleep: "Sessions by end date · naps excluded · overlaps reconciled."
    default: "Daily median of available values; session contexts may differ."
    }
  }
}

struct TrendsView: View {
  @Environment(AppModel.self) var model
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var days = 28
  @State private var metric: TrendMetric = .heartRate
  @State private var selectedDate: Date?
  @State private var summaries: [DailyTrendSummary] = []
  @State private var loading = false
  @State private var loadError: String?
  @State private var request = UUID()
  @State private var loadedMetric: TrendMetric?
  @State private var loadedDays: Int?
  @State private var loadedDemo: Bool?
  @State private var loadedStore: TempoStore?
  private var sameDataset: Bool {
    loadedMetric == metric && loadedDays == days && loadedDemo == model.demo
      && loadedStore === model.store
  }
  private var rangeStart: Date {
    Calendar.current.date(
      byAdding: .day, value: -(days - 1), to: Calendar.current.startOfDay(for: Date()))!
  }
  private var rangeEnd: Date {
    Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))!
  }
  private var sleepSessions: [SleepSession] {
    model.sleeps.filter {
      !$0.isNap && $0.end >= rangeStart && $0.end <= Date() && $0.end > $0.start
    }
    .sorted { $0.end < $1.end }
  }
  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          Picker("Range", selection: $days) {
            Text("7 days").tag(7)
            Text("28 days").tag(28)
            Text("90 days").tag(90)
          }.pickerStyle(.segmented)
          if !dynamicTypeSize.isAccessibilitySize { SleepRhythmCard() }
          Menu {
            Picker("Measurement", selection: $metric) {
              ForEach(TrendMetric.allCases, id: \.self) { Text($0.title).tag($0) }
            }
          } label: {
            HStack {
              Text(metric.title).font(.title2.weight(.semibold))
              Spacer()
              Image(systemName: "chevron.up.chevron.down").font(.subheadline)
            }.contentShape(Rectangle()).frame(minHeight: 44)
          }.tint(.primary).accessibilityLabel("Measurement").accessibilityValue(metric.title)
          if dynamicTypeSize.isAccessibilitySize { SleepRhythmCard() }
          VStack(alignment: .leading, spacing: 14) {
            if metric != .sleep && sameDataset && !summaries.isEmpty {
              periodOverview
            }
            if metric == .sleep {
              Text(metric.method).font(.subheadline).foregroundStyle(.secondary)
              sleepChart
              sleepSelection.id("trend-summary")
              if !sleepSessions.isEmpty {
                DisclosureGroup("Daily values and evidence") {
                  ForEach(Array(sleepSessions.reversed().enumerated()), id: \.element.id) {
                    index, sleep in
                    Button {
                      selectedDate = sleep.end
                      proxy.scrollTo("trend-summary", anchor: .top)
                    } label: {
                      dailyRow(date: sleep.end, value: durationText(sleep.duration))
                    }.buttonStyle(.plain).accessibilityIdentifier("trend-day-\(index)")
                  }
                }.font(.subheadline)
              }
            } else if loading && (!sameDataset || summaries.isEmpty) {
              ProgressView("Loading history")
            } else if let loadError, !sameDataset || summaries.isEmpty {
              Text(loadError)
              Button("Retry") { Task { await refresh() } }
            } else if summaries.isEmpty {
              ContentUnavailableView(
                "No qualifying measurements", systemImage: "chart.xyaxis.line",
                description: Text(
                  "Collect supported band readings or choose an imported Health metric. Missing days remain empty."
                ))
            } else {
              measurementChart
              Text(metric.method).font(.caption).foregroundStyle(.secondary)
              if let loadError {
                Text(loadError).font(.caption).foregroundStyle(.secondary)
                Button("Retry") { Task { await refresh() } }
              }
              Text("Tap or drag on the chart to explore a day.")
                .font(.caption).foregroundStyle(.secondary)
              measurementSelection.id("trend-summary")
              DisclosureGroup("Daily values and evidence") {
                ForEach(Array(summaries.reversed().enumerated()), id: \.element.id) {
                  index, summary in
                  Button {
                    selectedDate = chartDate(summary.date)
                    proxy.scrollTo("trend-summary", anchor: .top)
                  } label: {
                    dailyRow(
                      date: summary.date,
                      value: "\(String(format: "%.1f", summary.value)) \(metric.unit)")
                  }.buttonStyle(.plain).accessibilityIdentifier("trend-day-\(index)")
                }
              }.font(.subheadline)
            }
          }.padding(18).background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 24))
          DisclosureGroup("About these trends") {
            Text("Typical recorded day is the median of daily values, with each recorded day weighted equally. Missing days are excluded.")
            Text("Empty days mean missing qualifying data, not zero. A change in band, wearing placement or recording coverage can change the pattern.")
            Text("Heart rate describes recorded periods. It is not a resting measurement or a full-day average.")
            Text("Journal associations are not available yet. Your entries remain saved for future analysis.")
          }.font(.subheadline).foregroundStyle(.secondary)
        }.padding(20)
      }.background(Color(uiColor: .systemGroupedBackground)).navigationTitle("Trends")
        .refreshable { await refresh() }
        .task(
          id: TrendRefreshIdentity(
            metric: metric.rawValue, days: days, demo: model.demo,
            generation: model.historyGeneration, latestSample: model.measurements.last?.timestamp)
        ) {
          await refresh()
        }
    }
  }
  private var periodOverview: some View {
    let overview = TrendPeriodSummary(summaries, expectedDays: days)
    return VStack(alignment: .leading, spacing: 12) {
      Text("Typical recorded day").font(.subheadline).foregroundStyle(.secondary)
      if let value = overview.typicalValue {
        Text("\(String(format: "%.1f", value)) \(metric.unit)")
          .font(.largeTitle.weight(.semibold)).monospacedDigit()
          .accessibilityIdentifier("trend-period-value")
      }
      HStack {
        Text("\(overview.recordedDays) of \(overview.expectedDays) days recorded")
        Spacer()
        Text("\(Int(Double(overview.recordedDays) / Double(overview.expectedDays) * 100))%")
          .monospacedDigit()
      }.font(.caption).foregroundStyle(.secondary)
      ProgressView(value: Double(overview.recordedDays), total: Double(overview.expectedDays))
        .tint(.teal).accessibilityLabel("Days with qualifying data")
      if let range = overview.range {
        Text("Daily values: \(String(format: "%.1f", range.lowerBound))–\(String(format: "%.1f", range.upperBound)) \(metric.unit)")
          .font(.caption).foregroundStyle(.secondary)
      }
      if overview.incomplete {
        Text("Sample limit reached · incomplete period")
          .font(.caption).foregroundStyle(.secondary)
      }
    }
  }
  private var measurementChart: some View {
    let points = segmented
    let low = summaries.map(\.value).min() ?? 0
    let high = summaries.map(\.value).max() ?? 1
    let padding = max(1, (high - low) * 0.15)
    return Chart(points, id: \.summary.id) { point in
      LineMark(
        x: .value("Date", chartDate(point.summary.date)),
        y: .value(metric.unit, point.summary.value),
        series: .value("Available days", point.segment)
      ).foregroundStyle(.teal)
      PointMark(
        x: .value("Date", chartDate(point.summary.date)),
        y: .value(metric.unit, point.summary.value)
      )
      .foregroundStyle(.teal)
      .accessibilityLabel(point.summary.date.formatted(date: .abbreviated, time: .omitted))
      .accessibilityValue(
        "\(String(format: "%.1f", point.summary.value)) \(metric.unit), \(point.summary.method)")
      if let selectedDate {
        RuleMark(x: .value("Selected day", selectedDate)).foregroundStyle(.secondary.opacity(0.4))
      }
    }.chartLegend(.hidden).chartXSelection(value: $selectedDate)
      .chartXScale(domain: rangeStart...rangeEnd).chartYScale(
        domain: max(0, low - padding)...(high + padding)
      )
      .chartYAxisLabel(metric.unit).frame(height: 220)
      .accessibilityLabel("\(metric.title) over \(days) days; missing days are not connected")
  }
  @ViewBuilder private var measurementSelection: some View {
    if let selectedDate {
      if let index = TrendSelection.index(at: selectedDate, dates: summaries.map(\.date)) {
        trendDetail(summaries[index], heading: "Selected day")
      } else {
        missingSelection(selectedDate)
      }
    } else if let last = summaries.last {
      trendDetail(last, heading: "Latest recorded day")
    }
  }
  private var sleepChart: some View {
    Group {
      if sleepSessions.isEmpty {
        ContentUnavailableView(
          "No sleep in this range", systemImage: "bed.double",
          description: Text("Add sleep or import supported records to explore your history."))
      } else {
        Chart(sleepSessions) { sleep in
          BarMark(x: .value("Sleep end", sleep.end), y: .value("Hours", sleep.duration / 3600))
            .foregroundStyle(.indigo)
            .accessibilityLabel(sleep.end.formatted(date: .abbreviated, time: .omitted))
            .accessibilityValue("\(durationText(sleep.duration)), \(sleep.origin.rawValue)")
          if let selectedDate {
            RuleMark(x: .value("Selected day", selectedDate)).foregroundStyle(
              .secondary.opacity(0.4))
          }
        }.chartXSelection(value: $selectedDate).chartXScale(domain: rangeStart...rangeEnd)
          .chartYAxisLabel("hours").frame(height: 220)
          .accessibilityLabel("Sleep sessions by end date; gaps are missing sessions")
        Text("\(sleepSessions.count) sessions · each bar is one reconciled session")
          .font(.caption).foregroundStyle(.secondary)
      }
    }
  }
  @ViewBuilder private var sleepSelection: some View {
    if let selectedDate {
      let sessions = sleepSessions.filter {
        Calendar.current.isDate($0.end, inSameDayAs: selectedDate)
      }
      if sessions.isEmpty {
        missingSelection(selectedDate)
      } else {
        ForEach(sessions) { sleepEvidence($0) }
      }
    } else if let last = sleepSessions.last {
      sleepEvidence(last)
    }
  }
  private func sleepEvidence(_ sleep: SleepSession) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(sleep.end.formatted(date: .abbreviated, time: .omitted)).font(.subheadline)
        .foregroundStyle(.secondary)
      Text(durationText(sleep.duration)).font(.title2.weight(.semibold))
        .accessibilityIdentifier("trend-selected-value")
      Text(
        "\(sleep.start.formatted(date: .omitted, time: .shortened))–\(sleep.end.formatted(date: .omitted, time: .shortened)) · \(sleep.origin.rawValue.capitalized)"
      )
      .font(.caption).foregroundStyle(.secondary)
      NavigationLink("Session and evidence") { SleepDetailView(sleep: sleep) }
    }
  }
  private func missingSelection(_ date: Date) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(date.formatted(date: .abbreviated, time: .omitted)).font(.subheadline)
      Text("No data for this day").font(.headline)
      Text("Choose a recorded point or a daily value to inspect its evidence.")
        .font(.caption).foregroundStyle(.secondary)
    }
  }
  private func dailyRow(date: Date, value: String) -> some View {
    HStack {
      Text(date.formatted(date: .abbreviated, time: .omitted))
      Spacer()
      Text(value).monospacedDigit()
      Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
    }.font(.subheadline).padding(.vertical, 8).contentShape(Rectangle())
  }
  private func chartDate(_ date: Date) -> Date {
    Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
  }
  private var segmented: [(summary: DailyTrendSummary, segment: Int)] {
    var segment = 0
    var previous: Date?
    return summaries.map { summary in
      if let previous,
        Calendar.current.dateComponents([.day], from: previous, to: summary.date).day ?? 0 > 1
      {
        segment += 1
      }
      previous = summary.date
      return (summary, segment)
    }
  }
  private func trendDetail(_ point: DailyTrendSummary, heading: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("\(heading) · \(point.date.formatted(date: .abbreviated, time: .omitted))")
        .font(.caption).foregroundStyle(.secondary)
      Text("\(String(format: "%.1f", point.value)) \(metric.unit)")
        .font(.title2.weight(.semibold)).monospacedDigit().accessibilityIdentifier(
          "trend-selected-value")
      if let coverage = point.coveredSeconds {
        Text("\(durationText(coverage)) measured · partial-day coverage").font(.caption)
          .foregroundStyle(.secondary)
      }
      if point.truncated {
        Text("Sample limit reached; this summary is incomplete.").font(.caption).foregroundStyle(
          .orange)
      }
      DisclosureGroup("Source and calculation") {
        Text(point.method)
        Text(
          "\(point.inputCount) inputs · \(point.inputOrigins.map { $0.rawValue.capitalized }.joined(separator: ", "))"
        )
        Text(
          point.sourceIDs.map { id in
            if let device = model.devices.first(where: { $0.id == id }) { return device.name }
            if let device = model.archivedDevices.first(where: { $0.id == id }) {
              return "\(device.name) · archived"
            }
            return "Unresolved source"
          }.joined(separator: " · "))
        Text("Derived summary · \(point.algorithmVersion)")
      }.font(.caption).foregroundStyle(.secondary)
    }
  }
  @MainActor private func refresh() async {
    let token = UUID()
    request = token
    loading = true
    loadError = nil
    if !sameDataset { selectedDate = nil; summaries = [] }
    let requestedMetric = metric
    let requestedDays = days
    let requestedDemo = model.demo
    let requestedStore = model.store
    let generation = model.historyGeneration
    guard let kind = requestedMetric.kind else {
      summaries = []
      loadedMetric = requestedMetric
      loadedDays = requestedDays
      loadedDemo = requestedDemo
      loadedStore = requestedStore
      loading = false
      return
    }
    do {
      let values =
        try await requestedStore?.dailySummaries(
          kind: kind, from: rangeStart,
          to: Date().addingTimeInterval(1), sourceSegments: model.sourceSegments) ?? []
      guard !Task.isCancelled, request == token, requestedMetric == metric, requestedDays == days,
        requestedDemo == model.demo, model.store === requestedStore,
        generation == model.historyGeneration
      else { return }
      summaries = values
      loadedMetric = requestedMetric
      loadedDays = requestedDays
      loadedDemo = requestedDemo
      loadedStore = requestedStore
      loading = false
    } catch {
      guard !Task.isCancelled, request == token, requestedMetric == metric, requestedDays == days,
        requestedDemo == model.demo, model.store === requestedStore,
        generation == model.historyGeneration
      else { return }
      loading = false
      loadError = "History couldn't load. Your stored measurements are unchanged."
    }
  }
}
