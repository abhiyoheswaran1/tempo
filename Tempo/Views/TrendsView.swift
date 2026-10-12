import Charts
import SwiftUI
import TempoCore

struct TrendsView: View {
  @Environment(AppModel.self) var model
  @State private var days = 28
  @State private var metric: MetricKind = .heartRate
  @State private var selectedDate: Date?
  @State private var summaries: [DailyTrendSummary] = []
  @State private var loading = false
  @State private var loadError: String?
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Picker("Range", selection: $days) {
          Text("7 days").tag(7)
          Text("28 days").tag(28)
          Text("90 days").tag(90)
        }.pickerStyle(.segmented)
        Picker("Measurement", selection: $metric) {
          ForEach([MetricKind.heartRate, .restingHeartRate, .rmssd, .sdnn, .weight], id: \.self) {
            Text(title($0)).tag($0)
          }
        }
        VStack(alignment: .leading, spacing: 12) {
          Text(title(metric)).font(.title2.weight(.semibold))
          Text(methodDescription).font(.subheadline).foregroundStyle(.secondary)
          if summaries.count >= 7, let low = summaries.map(\.value).min(),
            let high = summaries.map(\.value).max()
          {
            Text(
              "Your recorded daily range: \(String(format: "%.1f", low))–\(String(format: "%.1f", high)) \(unit)"
            ).font(.caption).foregroundStyle(.secondary)
          }
          if loading {
            ProgressView("Loading history")
          } else if let loadError {
            Text(loadError)
            Button("Retry") { Task { await refresh() } }
          } else if summaries.isEmpty {
            ContentUnavailableView(
              "No qualifying measurements", systemImage: "chart.xyaxis.line",
              description: Text(
                "Collect supported band measurements or choose an imported Health metric. Missing days remain empty."
              ))
          } else {
            let points = segmented
            Chart(points, id: \.summary.id) { point in
              LineMark(
                x: .value("Date", point.summary.date), y: .value(unit, point.summary.value),
                series: .value("Available days", point.segment)
              ).foregroundStyle(.teal)
              PointMark(x: .value("Date", point.summary.date), y: .value(unit, point.summary.value))
                .foregroundStyle(.teal)
                .accessibilityLabel(
                  point.summary.date.formatted(date: .abbreviated, time: .omitted)
                )
                .accessibilityValue(
                  "\(String(format: "%.1f", point.summary.value)) \(unit), \(point.summary.method)")
            }.chartXSelection(value: $selectedDate).chartYAxisLabel(unit).frame(height: 220)
              .accessibilityLabel(
                "\(title(metric)) over \(days) days; missing days are not connected")
            Text("\(summaries.count) days with data · gaps preserved").font(.caption)
              .foregroundStyle(.secondary)
            let point =
              selectedDate.flatMap { date in
                summaries.min {
                  abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
                }
              } ?? summaries.last!
            trendDetail(point)
            DisclosureGroup("Daily values and evidence") {
              ForEach(summaries.reversed()) { summary in trendDetail(summary).padding(.vertical, 6)
              }
            }.font(.subheadline)
          }
        }
        Divider()
        VStack(alignment: .leading, spacing: 12) {
          Text("Sleep duration").font(.title3.weight(.semibold))
          let recent = model.sleeps.filter {
            !$0.isNap && $0.end > Date().addingTimeInterval(Double(-days) * 86400)
          }
          if recent.isEmpty {
            Text("Add sleep to explore your history.").foregroundStyle(.secondary)
          } else {
            Chart(recent) { sleep in
              BarMark(x: .value("Sleep end", sleep.end), y: .value("Hours", sleep.duration / 3600))
                .foregroundStyle(.indigo)
                .accessibilityLabel(sleep.end.formatted(date: .abbreviated, time: .omitted))
                .accessibilityValue("\(durationText(sleep.duration)), \(sleep.origin.rawValue)")
            }.chartYAxisLabel("hours").frame(height: 150).accessibilityLabel(
              "Sleep duration; entered and imported sessions")
            Text("Sessions by end date · naps excluded · overlapping sessions reconciled").font(
              .caption
            ).foregroundStyle(.secondary)
          }
        }
        Divider()
        VStack(alignment: .leading, spacing: 8) {
          Text("Personal patterns").font(.title3.weight(.semibold))
          Text("Keep a journal to build context for your measurements.").foregroundStyle(.secondary)
          Text("\(model.journals.count) entries · insights need enough paired observations").font(
            .caption
          ).foregroundStyle(.secondary)
        }
      }.padding(20)
    }.background(Color(uiColor: .systemGroupedBackground)).navigationTitle("Trends").refreshable {
      await refresh()
    }
    .task(
      id:
        "\(days)-\(metric.rawValue)-\(model.demo)-\(model.historyGeneration)-\(Int(model.measurements.last?.timestamp.timeIntervalSince1970 ?? 0)/300)"
    ) {
      await refresh()
    }
  }
  var unit: String {
    metric == .weight ? "kg" : (metric == .rmssd || metric == .sdnn ? "ms" : "bpm")
  }
  var methodDescription: String {
    if metric == .heartRate {
      return "Average during measured periods, not an all-day or resting heart rate."
    }
    if metric == .weight { return "Latest available weight each day." }
    return "Daily median of available values; session contexts may differ."
  }
  var segmented: [(summary: DailyTrendSummary, segment: Int)] {
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
  func trendDetail(_ point: DailyTrendSummary) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      MetricRow(
        label: point.date.formatted(date: .abbreviated, time: .omitted),
        value: "\(String(format: "%.1f", point.value)) \(unit)", detail: point.method)
      if let coverage = point.coveredSeconds {
        Text("Measured exposure: \(durationText(coverage)) · partial-day coverage").font(.caption)
      }
      Text(
        "\(point.inputCount) inputs · \(point.inputOrigins.map { $0.rawValue.capitalized }.joined(separator: ", "))"
      ).font(.caption).foregroundStyle(.secondary)
      Text(
        point.sourceIDs.map { id in model.devices.first { $0.id == id }?.name ?? "Imported source" }
          .joined(separator: " · ")
      ).font(.caption).foregroundStyle(.secondary)
      if point.truncated {
        Text("Sample limit reached; this summary is incomplete.").font(.caption).foregroundStyle(
          .orange)
      }
      Text("Derived summary · \(point.algorithmVersion)").font(.caption).foregroundStyle(.secondary)
    }.accessibilityElement(children: .combine)
  }
  @MainActor func refresh() async {
    loading = true
    loadError = nil
    selectedDate = nil
    let requestedMetric = metric
    let requestedDays = days
    let requestedDemo = model.demo
    do {
      let from = Calendar.current.date(
        byAdding: .day, value: -(days - 1), to: Calendar.current.startOfDay(for: Date()))!
      let values =
        try await model.store?.dailySummaries(
          kind: metric, from: from, to: Date().addingTimeInterval(1),
          sourceSegments: model.sourceSegments) ?? []
      guard !Task.isCancelled, requestedMetric == metric, requestedDays == days,
        requestedDemo == model.demo
      else { return }
      summaries = values
      loading = false
    } catch {
      guard !Task.isCancelled else { return }
      summaries = []
      loading = false
      loadError = "History couldn't load. Your stored measurements are unchanged."
    }
  }
  func title(_ kind: MetricKind) -> String {
    switch kind {
    case .heartRate: return "Heart rate"
    case .restingHeartRate: return "Resting heart rate"
    case .rmssd: return "HRV · RMSSD"
    case .sdnn: return "HRV · SDNN"
    case .weight: return "Weight"
    default: return kind.rawValue
    }
  }
}
