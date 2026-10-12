import SwiftUI
import TempoCore

struct TodayView: View {
  @Environment(AppModel.self) var model
  @State private var journal = false
  @State private var sleep = false
  @ScaledMetric(relativeTo: .largeTitle) private var scoreSize = 48
  var body: some View {
    let readiness = model.readiness
    let lastSleep = SleepPresentation(sessions: model.sleeps, now: Date())
    let today = model.canonical.filter { Calendar.current.isDateInToday($0.timestamp) }
    let load = CardiovascularLoad.calculate(today, maxHeartRate: model.maxHeartRate)
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        ViewThatFits(in: .horizontal) {
          HStack(spacing: 8) {
            brand
            Spacer()
            dateLabel.fixedSize()
          }
          VStack(alignment: .leading, spacing: 6) {
            brand
            dateLabel
          }
        }
        Text(headline(readiness)).font(.title2.weight(.semibold)).fixedSize(
          horizontal: false, vertical: true)
        VStack(alignment: .leading, spacing: 12) {
          ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
              Text("Readiness").font(.headline).fixedSize()
              Spacer()
              Text("Tempo estimate").font(.caption).foregroundStyle(.secondary).fixedSize()
            }
            VStack(alignment: .leading, spacing: 4) {
              Text("Readiness").font(.headline)
              Text("Tempo estimate").font(.caption).foregroundStyle(.secondary)
            }
          }
          ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 20) {
              score(readiness)
              evidence(readiness).fixedSize()
            }
            VStack(alignment: .leading, spacing: 8) {
              score(readiness)
              evidence(readiness)
            }
          }
          NavigationLink("See inputs and calculation") { ReadinessDetailView() }.font(.subheadline)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(
          Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
        TodayCollectionPanel()
        VStack(spacing: 14) {
          VStack(alignment: .leading, spacing: 6) {
            if let last = lastSleep.session {
              NavigationLink {
                SleepDetailView(sleep: last)
              } label: {
                VStack(alignment: .leading, spacing: 5) {
                  ViewThatFits(in: .horizontal) {
                    HStack {
                      Text(lastSleep.title).font(.headline).accessibilityIdentifier(
                        "today-sleep-summary")
                      Spacer()
                      Text(durationText(last.duration)).font(.title3.weight(.medium))
                        .monospacedDigit()
                    }
                    VStack(alignment: .leading, spacing: 4) {
                      Text(lastSleep.title).font(.headline).accessibilityIdentifier(
                        "today-sleep-summary")
                      Text(durationText(last.duration)).font(.title3.weight(.medium))
                        .monospacedDigit()
                    }
                  }
                  Text(
                    "\(last.end.formatted(date: .abbreviated, time: .omitted)) · \(last.start.formatted(date: .omitted, time: .shortened))–\(last.end.formatted(date: .omitted, time: .shortened)) · \(last.origin == .manual ? "Entered" : last.origin.rawValue.capitalized)"
                  )
                  .font(.caption).foregroundStyle(.secondary)
                }.contentShape(Rectangle())
              }.tint(.primary)
            } else {
              Text(lastSleep.title).font(.headline).accessibilityIdentifier("today-sleep-summary")
              Text("Add sleep to begin your overnight history.").font(.subheadline).foregroundStyle(
                .secondary)
              Button("Add sleep") { sleep = true }.font(.subheadline)
            }
          }.frame(maxWidth: .infinity, alignment: .leading)
          Divider()
          VStack(alignment: .leading, spacing: 6) {
            Text("Today's movement").font(.headline).accessibilityIdentifier(
              "today-movement-summary")
            MetricRow(
              label: "Cardiovascular load",
              value: (load?.coveredSeconds ?? 0) > 60
                ? String(format: "%.0f", load?.points ?? 0) : "Not enough data",
              detail:
                "\(model.workouts.filter { Calendar.current.isDateInToday($0.start) }.count) workouts · HR-based estimate"
            )
          }.frame(maxWidth: .infinity, alignment: .leading)
        }
        Button {
          journal = true
        } label: {
          Label("How do you feel?", systemImage: "square.and.pencil").frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }.buttonStyle(.bordered)
      }.padding(20)
    }.refreshable { await model.refreshToday() }
      .background(Color(uiColor: .systemGroupedBackground)).navigationTitle("Today")
      .navigationBarTitleDisplayMode(.inline)
      .sheet(isPresented: $journal) { NavigationStack { JournalEditor() } }
      .sheet(isPresented: $sleep) { NavigationStack { SleepEditor() } }
  }
  var brand: some View {
    HStack(spacing: 8) {
      Image("TempoMark").resizable().scaledToFit().foregroundStyle(.teal).frame(
        width: 24, height: 24
      ).accessibilityHidden(true)
      Text("Tempo").font(.subheadline.weight(.semibold)).accessibilityIdentifier("tempo-brand-name")
    }.fixedSize()
  }
  var dateLabel: some View {
    Text(Date(), format: .dateTime.weekday(.abbreviated).month(.abbreviated).day()).font(
      .subheadline
    ).foregroundStyle(.secondary)
  }
  func headline(_ result: ReadinessResult) -> String {
    if result.baselineDays < 7 { return "Building your baseline" }
    guard let score = result.score else { return "More overnight data needed" }
    return score < 50 ? "A lighter day may suit you" : "Close to your usual range"
  }
  func score(_ result: ReadinessResult) -> some View {
    Text(result.score.map(String.init) ?? "—").font(
      .system(size: scoreSize, weight: .semibold, design: .rounded)
    ).monospacedDigit().accessibilityLabel(
      result.score.map { "Readiness \($0)" } ?? "Readiness unavailable")
  }
  func evidence(_ result: ReadinessResult) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(EvidenceLevel(confidence: result.confidence).title).font(.subheadline.weight(.medium))
      Text(
        result.baselineDays < 7
          ? "\(result.baselineDays) of 7 nights to begin"
          : "\(result.baselineDays) personal baseline nights"
      ).font(.caption).foregroundStyle(.secondary)
    }
  }
}
struct ReadinessDetailView: View {
  @Environment(AppModel.self) var model
  var body: some View {
    let readiness = model.readiness
    List {
      Section("Evidence") {
        Text(EvidenceLevel(confidence: readiness.confidence).title).font(.headline)
        Text(
          "Evidence categories describe available inputs and comparability. They are conservative heuristics, not a calibrated probability of accuracy."
        )
        LabeledContent("Baseline nights", value: String(readiness.baselineDays))
        if let sleep = model.readinessSleep {
          LabeledContent("Sleep used", value: sleep.end.formatted())
        } else {
          Text(
            "No qualifying sleep within the last 36 hours. Older inputs remain in your history but do not supply today’s score."
          )
        }
      }
      Section("Your inputs") {
        ForEach(readiness.factors, id: \.self) { Text($0) }
        if readiness.factors.isEmpty {
          Text("Collect overnight measurements to build your personal baseline.")
        }
      }
      Section("How Tempo calculates it") {
        Text(
          "A 28-night personal window compares log RMSSD, resting heart rate and sleep duration against median and robust deviation. At least 7 prior nights and 2 available inputs are required. Scores are rounded to 5 points; 21 nights establish the baseline."
        )
        Text(
          "Resting heart rate is an overnight estimate requiring 70% sample coverage. HRV requires valid beat-to-beat intervals in a sufficiently covered window. Missing measurements are not filled in."
        )
        Text(
          "Band and reported placement changes can reduce evidence strength. Uncalibrated offsets are not applied to your measurements. This is personal training guidance, without medical validation."
        )
      }
      Section("Algorithm") { Text(readiness.algorithmVersion) }
    }.navigationTitle("Readiness explained")
  }
}
