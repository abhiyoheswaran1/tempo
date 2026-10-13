import SwiftUI
import TempoCore

struct TodayView: View {
  @Environment(AppModel.self) var model
  @Environment(\.dynamicTypeSize) private var textSize
  @State private var journal: JournalEntry?
  @State private var sleep = false
  @State private var proposedSleep: SleepSession?
  @ScaledMetric(relativeTo: .largeTitle) private var scoreSize = 42
  var body: some View {
    TimelineView(.periodic(from: .now, by: 60)) { _ in todayContent }
  }
  private var todayContent: some View {
    let readiness = model.todayReadiness
    let latestSleep = SleepPresentation(sessions: model.sleeps, now: Date())
    return ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        let headerLayout =
          textSize.isAccessibilitySize
          ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
          : AnyLayout(HStackLayout())
        headerLayout {
          HStack {
            Image("TempoMark").resizable().scaledToFit().frame(width: 22, height: 22)
              .foregroundStyle(.teal).accessibilityHidden(true)
            Text("Tempo").font(.subheadline.weight(.semibold)).accessibilityIdentifier(
              "tempo-brand-name")
          }
          if !textSize.isAccessibilitySize { Spacer() }
          Text(Date(), format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
            .font(.subheadline).foregroundStyle(.secondary)
        }
        if (!model.demo || ProcessInfo.processInfo.arguments.contains("--battery-ui-demo")),
          let device = model.collectionDevice, let battery = model.bluetooth.battery[device.id],
          battery.isFresh(at: Date()) {
          Label("Band \(battery.percent)%", systemImage: "battery.75percent")
            .font(.subheadline.weight(.medium)).monospacedDigit().foregroundStyle(.teal)
            .accessibilityIdentifier("today-header-battery-percent")
            .accessibilityLabel("Reported band battery \(battery.percent) percent")
        }
        Text(readiness.score == nil ? "Your day, at a glance" : headline(readiness))
          .font(.title2.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
        if let score = readiness.score {
          VStack(alignment: .leading, spacing: 10) {
            let readinessLayout =
              textSize.isAccessibilitySize
              ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
              : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
            readinessLayout {
              Text(score.formatted()).font(
                .system(size: scoreSize, weight: .semibold, design: .rounded)
              )
              .monospacedDigit().accessibilityLabel("Readiness \(score)")
              VStack(alignment: .leading, spacing: 4) {
                Text("Readiness").font(.headline)
                Text(EvidenceLevel(confidence: readiness.confidence).title).font(.subheadline)
                  .foregroundStyle(.secondary)
                Text("Tempo estimate · personal baseline").font(.caption).foregroundStyle(
                  .secondary)
              }
            }
            calculationLink
          }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(
            cardBackground, in: RoundedRectangle(cornerRadius: 22))
        }
        TodayCollectionPanel()
        if textSize.isAccessibilitySize {
          sleepSummary(latestSleep)
          movementSummary
        } else {
          HStack(alignment: .top, spacing: 12) {
            sleepSummary(latestSleep)
            movementSummary
          }
        }
        if let candidate = model.sleepCandidates.first {
          VStack(alignment: .leading, spacing: 12) {
            Label("Possible sleep", systemImage: "moon.zzz").font(.headline)
            Text(durationText(candidate.session.duration)).font(.title2.weight(.semibold))
            Text("\(candidate.session.start.formatted(date: .abbreviated, time: .shortened)) – \(candidate.session.end.formatted(date: .omitted, time: .shortened))")
              .font(.subheadline).foregroundStyle(.secondary)
            Text("Experimental HR-based estimate · \(Int(candidate.coverage * 100))% coverage. Quiet wakefulness may look similar. Confirm your sleep timing before it contributes to readiness.")
              .font(.caption).foregroundStyle(.secondary)
            HStack {
              Button("Review sleep") { proposedSleep = candidate.session }
                .buttonStyle(.borderedProminent).accessibilityIdentifier("review-possible-sleep")
              Button("Not sleep") { model.mutate { try await model.dismissSleepCandidate(candidate) } }
                .buttonStyle(.bordered)
            }
          }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 22))
        }
        if readiness.score == nil { baselineProgress(readiness) }
        Button {
          journal = todayJournal ?? JournalEntry()
        } label: {
          HStack {
            Image(systemName: "square.and.pencil")
            VStack(alignment: .leading, spacing: 4) {
              Text(todayJournal == nil ? "How do you feel?" : "Journal check-in saved")
              if todayJournal != nil {
                Text("Edit").font(.subheadline).foregroundStyle(.teal)
              }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption)
          }.frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).tint(.teal).padding(.horizontal, 4)
          .accessibilityIdentifier("today-journal-check-in")
      }.padding(20)
    }.refreshable { await model.refreshToday() }
      .background(Color(uiColor: .systemGroupedBackground)).navigationTitle("Today")
      .navigationBarTitleDisplayMode(.large)
      .sheet(item: $journal) { entry in NavigationStack { JournalEditor(entry: entry) } }
      .sheet(isPresented: $sleep) { NavigationStack { SleepEditor() } }
      .sheet(item: $proposedSleep) { session in NavigationStack { SleepEditor(existing: session) } }
  }
  private var todayJournal: JournalEntry? {
    model.journals.filter { Calendar.current.isDateInToday($0.date) }
      .max { $0.date < $1.date }
  }
  private var cardBackground: Color { Color(uiColor: .secondarySystemGroupedBackground) }
  private var calculationLink: some View {
    NavigationLink("See inputs and calculation") { ReadinessDetailView() }.font(.subheadline)
  }
  private func sleepSummary(_ value: SleepPresentation) -> some View {
    Group {
      if let last = value.session {
        NavigationLink {
          SleepDetailView(sleep: last)
        } label: {
          VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "bed.double").foregroundStyle(.indigo).accessibilityHidden(true)
            Text(value.title).font(.subheadline.weight(.semibold)).accessibilityIdentifier(
              "today-sleep-summary")
            Text(durationText(last.duration)).font(.title2.weight(.semibold)).monospacedDigit()
            Text(
              "\(last.start.formatted(date: .omitted, time: .shortened))–\(last.end.formatted(date: .omitted, time: .shortened))"
            )
            .font(.caption).foregroundStyle(.secondary)
            Text(
              "\(last.end.formatted(date: .abbreviated, time: .omitted)) · \(last.origin == .manual ? "Entered" : last.origin.rawValue.capitalized)"
            )
            .font(.caption).foregroundStyle(.secondary)
          }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).tint(.primary)
      } else {
        VStack(alignment: .leading, spacing: 8) {
          Image(systemName: "bed.double").foregroundStyle(.indigo).accessibilityHidden(true)
          Text(value.title).font(.subheadline.weight(.semibold)).accessibilityIdentifier(
            "today-sleep-summary")
          Text("No sleep recorded").font(.subheadline).foregroundStyle(.secondary)
          Text(model.sleepDetectionStatus.message).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("sleep-collection-explanation")
          Button("Add sleep") { sleep = true }.font(.subheadline)
        }.frame(maxWidth: .infinity, alignment: .leading)
      }
    }.padding(16).frame(maxWidth: .infinity, alignment: .topLeading).background(
      cardBackground, in: RoundedRectangle(cornerRadius: 22))
  }
  private var movementSummary: some View {
    NavigationLink {
      ActivityView()
    } label: {
      VStack(alignment: .leading, spacing: 8) {
        Image(systemName: "figure.walk").foregroundStyle(.teal).accessibilityHidden(true)
        Text("Today's movement").font(.subheadline.weight(.semibold)).accessibilityIdentifier(
          "today-movement-summary")
        if let load = model.todayLoad, load.coveredSeconds > 60 {
          Text(String(format: "%.0f", load.points)).font(.title2.weight(.semibold))
            .monospacedDigit()
          Text("Cardiovascular load").font(.caption).foregroundStyle(.secondary)
        } else {
          Text("Building coverage").font(.subheadline).foregroundStyle(.secondary)
        }
        Text("\(model.workouts.filter { Calendar.current.isDateInToday($0.start) }.count) workouts")
          .font(.caption).foregroundStyle(.secondary)
        if let load = model.todayLoad, load.coveredSeconds > 60 {
          Text("From \(durationText(load.coveredSeconds)) of HR · estimate").font(.caption)
            .foregroundStyle(.secondary)
        } else {
          Text("More HR needed").font(.caption).foregroundStyle(.secondary)
        }
      }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        .padding(16).background(cardBackground, in: RoundedRectangle(cornerRadius: 22))
    }.buttonStyle(.plain).tint(.primary)
  }
  private func baselineProgress(_ result: ReadinessResult) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      ViewThatFits(in: .horizontal) {
        HStack {
          Text("Readiness").font(.subheadline.weight(.semibold)).fixedSize()
          Spacer()
          Text("\(min(7, result.baselineDays)) of 7 nights").font(.caption).foregroundStyle(
            .secondary
          ).fixedSize()
        }
        VStack(alignment: .leading, spacing: 4) {
          Text("Readiness").font(.subheadline.weight(.semibold))
          Text("\(min(7, result.baselineDays)) of 7 nights").font(.caption).foregroundStyle(
            .secondary)
        }
      }
      Text(headline(result)).font(.subheadline).accessibilityIdentifier("baseline-progress")
      if result.baselineDays < 7 {
        ProgressView(value: Double(result.baselineDays), total: 7).accessibilityLabel(
          "Personal baseline progress"
        )
        .accessibilityValue("\(result.baselineDays) of 7 qualifying nights")
      }
      calculationLink
    }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
      .background(cardBackground, in: RoundedRectangle(cornerRadius: 22))
  }
  private func headline(_ result: ReadinessResult) -> String {
    if result.baselineDays < 7 { return "Building your baseline" }
    guard let score = result.score else { return "More overnight data needed" }
    return score < 50 ? "A lighter day may suit you" : "Close to your usual range"
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
