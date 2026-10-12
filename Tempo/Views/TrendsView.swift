import Charts
import SwiftUI
import TempoCore

struct TrendsView: View {
  @Environment(AppModel.self) var model
  @State private var days = 28
  @State private var metric: MetricKind = .heartRate
  @State private var selectedDate: Date?
  @State private var historical: [TempoCore.Measurement] = []
  var samples: [TempoCore.Measurement] {
    model.canonical.filter {
      $0.kind == metric && $0.timestamp > Date().addingTimeInterval(Double(-days) * 86400)
    }
  }
  var points: [TempoCore.Measurement] { historical }
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
        ContentSection(
          title(metric), subtitle: "Daily latest observation · tap to inspect its source"
        ) {
          if points.isEmpty {
            ContentUnavailableView(
              "No qualifying measurements", systemImage: "chart.xyaxis.line",
              description: Text(
                "Tempo only shows values from supported, measured or imported inputs."))
          } else {
            Chart(points) { p in
              LineMark(x: .value("Date", p.timestamp), y: .value("Value", p.value)).foregroundStyle(
                .teal)
              PointMark(x: .value("Date", p.timestamp), y: .value("Value", p.value))
                .foregroundStyle(.teal)
            }.chartXSelection(value: $selectedDate).frame(height: 220)
            if let date = selectedDate,
              let p = points.min(by: {
                abs($0.timestamp.timeIntervalSince(date))
                  < abs($1.timestamp.timeIntervalSince(date))
              })
            {
              VStack(alignment: .leading) {
                Text(p.timestamp, format: .dateTime.month().day())
                Text(String(format: "%.1f", p.value)).font(.title2)
                Text(
                  "\(p.origin.rawValue.capitalized) · \(model.devices.first{$0.id==p.deviceID}?.name ?? p.transport)"
                )
                Text(
                  "Quality: \(p.quality.isEmpty ? "accepted; wear \(p.wear.rawValue)":p.quality.joined(separator:", "))"
                ).font(.caption)
              }
            }
          }
        }
        ContentSection(
          "Sleep duration",
          subtitle: "Entered and imported sessions; overlapping sessions are not added"
        ) {
          let recent = model.sleeps.filter {
            $0.end > Date().addingTimeInterval(Double(-days) * 86400)
          }
          if recent.isEmpty {
            Text("Record sleep to explore its timing and duration.").foregroundStyle(.secondary)
          } else {
            Chart(recent) { s in
              BarMark(x: .value("Night", s.end, unit: .day), y: .value("Hours", s.duration / 3600))
                .foregroundStyle(.indigo)
            }.frame(height: 150)
          }
        }
        ContentSection("Personal patterns") {
          Text(
            "Associations need at least 30 paired observations. Unanswered journal items remain unknown."
          ).foregroundStyle(.secondary)
          Text("Journal entries: \(model.journals.count)")
          Text("No supported association yet. Correlation does not establish causation.").font(
            .caption
          ).foregroundStyle(.secondary)
        }
      }.padding(20)
    }.background(Color(uiColor: .systemGroupedBackground)).navigationTitle("Trends").task(
      id: "\(days)-\(metric.rawValue)-\(model.demo)"
    ) {
      historical =
        (try? await model.store?.dailyRepresentatives(
          kind: metric, from: Date().addingTimeInterval(Double(-days) * 86400),
          to: Date().addingTimeInterval(1))) ?? []
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
