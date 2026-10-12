import SwiftUI
import TempoCore

struct TodayView: View {
  @Environment(AppModel.self) var model
  @State private var journal = false
  @State private var sleep = false
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text(Date(), format: .dateTime.weekday(.wide).month().day()).font(.subheadline)
          .foregroundStyle(.secondary)
        Text(model.readiness.headline).font(.largeTitle.weight(.semibold)).fixedSize(
          horizontal: false, vertical: true)
        ContentSection(
          "Readiness", subtitle: "Tempo estimate · \(model.readiness.algorithmVersion)"
        ) {
          HStack(alignment: .firstTextBaseline) {
            Text(model.readiness.score.map { String($0) } ?? "—").font(
              .system(size: 56, weight: .semibold, design: .rounded)
            ).accessibilityLabel(
              model.readiness.score.map { "Readiness \($0)" } ?? "Readiness unavailable")
            Spacer()
            VStack(alignment: .trailing) {
              Text(
                model.readiness.baselineDays < 7
                  ? "Building baseline"
                  : (model.readiness.baselineDays < 21 ? "Provisional" : "Personal baseline"))
              Text("\(Int(model.readiness.confidence*100))% confidence").font(.caption)
                .foregroundStyle(.secondary)
            }
          }
          NavigationLink("See inputs and calculation") { ReadinessDetailView() }
        }
        ContentSection(
          "Last night",
          subtitle:
            "Sleep is entered or imported; automatic detection is unavailable without validated inputs."
        ) {
          if let last = model.sleeps.first {
            MetricRow(
              label: "Sleep", value: durationText(last.duration),
              detail: last.origin == .manual
                ? "Manually entered / corrected" : "\(last.origin.rawValue.capitalized) measurement"
            )
            Text(
              "\(last.start.formatted(date:.omitted,time:.shortened)) – \(last.end.formatted(date:.omitted,time:.shortened))"
            ).foregroundStyle(.secondary)
            NavigationLink("Inspect sleep") { SleepDetailView(sleep: last) }
          } else {
            Label("No sleep session yet", systemImage: "moon.zzz").foregroundStyle(.secondary)
          }
          Button("Add or correct sleep") { sleep = true }
        }
        ContentSection(
          "Today's movement", subtitle: "Derived cardiovascular load · Edwards zone minutes"
        ) {
          let today = model.canonical.filter { Calendar.current.isDateInToday($0.timestamp) }
          let load = CardiovascularLoad.calculate(today, maxHeartRate: model.maxHeartRate)
          MetricRow(
            label: "Cardiovascular load",
            value: (load?.coveredSeconds ?? 0) > 60
              ? String(format: "%.0f", load?.points ?? 0) : "Unavailable",
            detail: "Requires measured heart rate; gaps are excluded")
          MetricRow(
            label: "Recorded workouts",
            value: String(model.workouts.filter { Calendar.current.isDateInToday($0.start) }.count))
        }
        ContentSection("Your band") {
          Text(model.activeDevice?.name ?? "No active band").font(.headline)
          Text(model.demo ? "Synthetic demonstration" : model.bluetooth.status).font(.subheadline)
            .foregroundStyle(.secondary)
          if let sample = model.lastSample {
            TimelineView(.periodic(from: .now, by: 15)) { context in
              MetricRow(
                label: "Last heart rate",
                value: context.date.timeIntervalSince(sample.timestamp) > 90
                  ? "Stale" : "\(Int(sample.value)) bpm",
                detail:
                  "\(sample.timestamp.formatted(date:.abbreviated,time:.standard)) · \(sample.origin.rawValue)"
              )
            }
          } else {
            Text("Pair a band to begin collecting your own measurements.").foregroundStyle(
              .secondary)
          }
          MetricRow(
            label: "Battery", value: "Unavailable",
            detail: "Authoritative battery reading has not been validated")
        }
        Button {
          journal = true
        } label: {
          Label("How do you feel?", systemImage: "square.and.pencil").frame(maxWidth: .infinity)
            .padding(12)
        }.buttonStyle(.bordered)
      }.padding(20)
    }.background(Color(uiColor: .systemGroupedBackground)).navigationTitle("Today")
      .navigationBarTitleDisplayMode(.inline)
      .sheet(isPresented: $journal) { NavigationStack { JournalEditor() } }
      .sheet(isPresented: $sleep) { NavigationStack { SleepEditor() } }
  }
}
struct ReadinessDetailView: View {
  @Environment(AppModel.self) var model
  var body: some View {
    List {
      Section("Your inputs") {
        ForEach(model.readiness.factors, id: \.self) { Text($0) }
        if model.readiness.factors.isEmpty { Text("No qualifying overnight inputs yet.") }
      }
      Section("How Tempo calculates it") {
        Text(
          "A 28-night personal window compares log RMSSD, resting heart rate and sleep duration against median and robust deviation. At least 7 prior nights and 2 available inputs are required. Scores are rounded to 5 points; 21 nights establish the baseline."
        )
        Text(
          "Resting heart rate here is the overnight 10th percentile estimate and requires 70% sample coverage. HRV requires a contiguous five-minute RR window with at least 240 accepted intervals and under 10% rejection."
        )
        Text(
          "Changing bands may change measurement distributions. This version does not calibrate device offsets; compare source history before treating a change as physiological."
        )
        Text("This is personal training guidance, without medical validation.")
      }
      Section("Version") { Text(model.readiness.algorithmVersion) }
    }.navigationTitle("Readiness explained")
  }
}
