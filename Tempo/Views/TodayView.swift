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
          movementSummary()
        } else {
          HStack(alignment: .top, spacing: 12) {
            sleepSummary(latestSleep, fillHeight: true)
            movementSummary(fillHeight: true)
          }.fixedSize(horizontal: false, vertical: true)
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
  private func sleepSummary(_ value: SleepPresentation, fillHeight: Bool = false) -> some View {
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
          }.frame(maxWidth: .infinity, maxHeight: fillHeight ? .infinity : nil, alignment: .topLeading).contentShape(Rectangle())
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
    }.padding(16).frame(maxWidth: .infinity, maxHeight: fillHeight ? .infinity : nil, alignment: .topLeading).background(
      cardBackground, in: RoundedRectangle(cornerRadius: 22))
  }
  private func movementSummary(fillHeight: Bool = false) -> some View {
    NavigationLink {
      TodayMovementDetailView()
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
      }.frame(maxWidth: .infinity, maxHeight: fillHeight ? .infinity : nil, alignment: .topLeading).contentShape(Rectangle())
    }.buttonStyle(.plain).tint(.primary)
      .padding(16).frame(maxWidth: .infinity, maxHeight: fillHeight ? .infinity : nil, alignment: .topLeading)
      .background(cardBackground, in: RoundedRectangle(cornerRadius: 22))
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


/// Descriptive daily evidence, separate from the manual workout workflow.
struct TodayMovementDetailView: View {
  @Environment(AppModel.self) var model
  var body: some View {
    List {
      if let load = model.todayLoad, load.coveredSeconds > 60 {
        Section {
          VStack(alignment: .leading, spacing: 8) {
            Label("Cardiovascular load", systemImage: "figure.walk")
              .font(.subheadline).foregroundStyle(.teal)
            Text(String(format: "%.0f points", load.points))
              .font(.largeTitle.weight(.semibold)).monospacedDigit()
            Text("Today's accumulated estimate from recorded heart rate")
              .font(.subheadline).foregroundStyle(.secondary)
          }.padding(.vertical, 8)
          MetricRow(label: "Recorded coverage", value: durationText(load.coveredSeconds))
          if let average = load.average {
            MetricRow(label: "Recorded average", value: String(format: "%.0f bpm", average))
          }
          if let maximum = load.maximum {
            MetricRow(label: "Recorded high", value: String(format: "%.0f bpm", maximum))
          }
        } footer: {
          Text("Describes recorded periods, not your entire day. Gaps and unqualified readings do not contribute.")
        }
        Section("Recorded intensity") {
          let below = max(0, load.coveredSeconds - load.zones.reduce(0, +))
          if below > load.coveredSeconds / 2 {
            Text("Most covered time was below your training zones.").font(.headline)
          } else {
            Text("\(durationText(load.zones.reduce(0, +))) recorded within your training zones.")
              .font(.headline)
          }
          MetricRow(label: "Below 50% of maximum HR", value: durationText(below))
          MetricRow(label: "At or above 70% of maximum HR",
            value: durationText(load.zones.dropFirst(2).reduce(0, +)))
          Text("These are descriptions of the recorded data, not activity classification or training advice.")
            .font(.caption).foregroundStyle(.secondary)
        }
        Section {
          ForEach(0..<5, id: \.self) { index in
            VStack(alignment: .leading, spacing: 6) {
              MetricRow(label: "Zone \(index + 1) · \(50 + index * 10)–\(index == 4 ? 100 : 60 + index * 10)%",
                value: durationText(load.zones[index]))
              ProgressView(value: load.zones[index], total: max(1, load.coveredSeconds))
                .tint(.teal).accessibilityLabel("Zone \(index + 1) share of covered time")
            }.padding(.vertical, 4)
          }
        } header: { Text("Time in zones") } footer: {
          Text("Zone 5 includes readings above 100%. Zones use your configured maximum HR of \(Int(model.maxHeartRate)) bpm.")
        }
        Section {
          DisclosureGroup("How load is calculated") {
            Text("Edwards load: minutes in zones 1–5 weighted by 1–5, then added together. Time below 50% of maximum HR contributes no points.")
            Text("Only reconciled, quality-eligible HR contributes. Intervals longer than ten seconds are excluded; overlapping sources are not added twice.")
            Text("Heart rate does not capture muscular load. This is separate from readiness and does not reproduce Whoop's proprietary strain score.")
          }.font(.subheadline).foregroundStyle(.secondary)
          NavigationLink("Inspect recorded heart rate") { LiveDashboardView() }
        }
      } else {
        Section {
          ContentUnavailableView("Building today's picture", systemImage: "figure.walk",
            description: Text("More than a minute of qualifying heart rate is needed. Unsupported or missing measurements are not treated as zero movement."))
          NavigationLink("Inspect recorded heart rate") { LiveDashboardView() }
        }
      }
    }.navigationTitle("Today's movement")
      .refreshable { await model.refreshToday() }
  }
}
