import Charts
import SwiftUI
import TempoCore

struct DailyObservationCard: View {
  @Environment(AppModel.self) private var model
  private var observation: DailyObservation {
    DailyObservation.sleep(observationSessions(model), now: Date(), allowSynthetic: model.demo)
  }
  var body: some View {
    let observation = self.observation
    return NavigationLink { DailyObservationDetailView() } label: {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Label("What stands out", systemImage: "sparkle").font(.subheadline.weight(.semibold))
          Spacer()
          Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
        }
        Text(observation.headline).font(.headline)
        Text(observation.kind == .building
          ? "\(min(7, observation.referenceCount)) of 7 prior nights · tap for context"
          : "Compared with \(observation.referenceCount) prior recorded nights")
          .font(.caption).foregroundStyle(.secondary)
      }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
    }.buttonStyle(.plain).tint(.primary).accessibilityIdentifier("daily-observation")
  }
}

private extension DailyObservation {
  var headline: String {
    switch kind {
    case .building: return currentSessionID == nil ? "A sleep comparison isn't available yet." : "Your sleep history is taking shape."
    case .usualSleep: return "Your sleep duration is close to your usual duration."
    case .shorterSleep, .longerSleep:
      let minutes = Int((abs(differenceSeconds ?? 0) / 900).rounded()) * 15
      return "You slept about \(minutes) minutes \(kind == .shorterSleep ? "less" : "more") than usual."
    }
  }
}

struct DailyObservationDetailView: View {
  @Environment(AppModel.self) private var model
  private var observation: DailyObservation {
    DailyObservation.sleep(observationSessions(model), now: Date(), allowSynthetic: model.demo)
  }
  var body: some View {
    let observation = self.observation
    return List {
      Section {
        Text(observation.headline).font(.title2.weight(.semibold))
        if let current = observation.currentSeconds {
          MetricRow(label: "Latest sleep today", value: durationText(current))
        }
        if let reference = observation.referenceSeconds {
          MetricRow(label: "Your usual duration", value: durationText(reference))
        }
        Text("\(observation.referenceCount) prior recorded nights in the preceding 28 calendar days")
          .font(.subheadline).foregroundStyle(.secondary)
      }
      Section {
        DisclosureGroup("Calculation and coverage") {
          Text("This compares saved sleep timing, not sleep quality or medical recovery. It describes history rather than prescribing a day.")
          Text("A comparison needs today's saved sleep and seven distinct prior wake dates. Typical duration is their median; differences under 30 minutes are close to usual. Headlines round differences to 15 minutes.")
          Text("Naps, unconfirmed estimates and fragmented imports are excluded. One primary saved session per date contributes; missing nights are not zero.")
          Text("Derived comparison · \(observation.algorithmVersion)")
        }.font(.subheadline).foregroundStyle(.secondary)
      }
      Section("Contributing sleep") {
        if let id = observation.currentSessionID,
          let session = model.sleeps.first(where: { $0.id == id }) {
          NavigationLink("Today's saved sleep · \(durationText(session.duration))") { SleepDetailView(sleep: session) }
        }
        DisclosureGroup("\(observation.referenceCount) reference nights") {
        ForEach(observation.referenceSessionIDs.reversed(), id: \.self) { id in
          if let session = model.sleeps.first(where: { $0.id == id }) {
            NavigationLink {
              SleepDetailView(sleep: session)
            } label: {
              MetricRow(label: session.end.formatted(date: .abbreviated, time: .omitted),
                value: durationText(session.duration))
            }
          }
        }
        }
        if observation.referenceCount == 0 { Text("No eligible prior nights yet").foregroundStyle(.secondary) }
      }
      Section {
        NavigationLink("Explore your days") { DayExplorerView() }
        NavigationLink("Sleep rhythm") { SleepRhythmView() }
      }
    }.navigationTitle("What stands out")
  }
}

private struct DayQueryIdentity: Hashable {
  let day: Date
  let store: ObjectIdentifier?
  let demo: Bool
}
private struct DayEvidence: Sendable {
  let receipt: LiveHistorySnapshot
  let load: LoadResult?
  let metrics: [DailyTrendSummary]
  let truncated: Bool
}

struct DayExplorerView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.scenePhase) private var scenePhase
  @State private var day = Calendar.current.startOfDay(for: Date())
  @State private var journal: JournalEntry?
  @State private var addSleep = false
  @State private var evidence: DayEvidence?
  @State private var loadedIdentity: DayQueryIdentity?
  @State private var loadedAt: Date?
  @State private var error: String?
  @State private var request = UUID()
  @State private var scheduledRefresh: Task<Void, Never>?
  @State private var isVisible = false
  private var identity: DayQueryIdentity {
    DayQueryIdentity(day: Calendar.current.startOfDay(for: day),
      store: model.store.map { ObjectIdentifier($0) }, demo: model.demo)
  }
  private var sessions: [SleepSession] {
    let window = DayHistory.window(for: day)
    // AppModel has globally reconciled these sessions before publishing them.
    let nearby = model.sleeps.filter { $0.end >= window.start.addingTimeInterval(-86400) && $0.end < window.end }
    return DayHistory.sessions(nearby, on: day, now: Date(), allowSynthetic: model.demo)
  }
  private var entry: JournalEntry? {
    let window = DayHistory.window(for: day)
    return model.journals.filter { window.contains($0.date) }.sorted {
      $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date > $1.date
    }.first
  }
  var body: some View {
    List {
      Section {
        HStack {
          Button { move(-1) } label: { Image(systemName: "chevron.left").frame(minWidth: 32, minHeight: 44) }
            .accessibilityLabel("Previous day").accessibilityIdentifier("day-previous")
            .disabled(day <= Date(timeIntervalSince1970: 86400))
          DatePicker("Date", selection: $day, in: Date(timeIntervalSince1970: 0)...Date(), displayedComponents: .date)
            .labelsHidden().frame(maxWidth: .infinity).accessibilityLabel("History date")
          Button { move(1) } label: { Image(systemName: "chevron.right").frame(minWidth: 32, minHeight: 44) }
            .accessibilityLabel("Next day").accessibilityIdentifier("day-next")
            .disabled(Calendar.current.isDateInToday(day))
        }.buttonStyle(.borderless)
        Text(day.formatted(date: .complete, time: .omitted)).font(.subheadline).foregroundStyle(.secondary)
      }
      Section("Sleep ending this day") {
        if sessions.isEmpty {
          Text("No saved sleep for this day").foregroundStyle(.secondary)
          Button("Record sleep for this day") { addSleep = true }
        } else {
          ForEach(sessions) { session in
            NavigationLink { SleepDetailView(sleep: session) } label: {
              VStack(alignment: .leading, spacing: 4) {
                Text("\(session.origin == .imported ? "Imported sleep interval" : session.isNap ? "Nap" : "Sleep") · \(durationText(session.duration))").font(.headline)
                Text("\(session.origin.rawValue.capitalized) · tap for timing and measurements")
                  .font(.caption).foregroundStyle(.secondary)
              }
            }
          }
        }
        NavigationLink("Sleep rhythm") { SleepRhythmView() }
      }
      if let evidence, loadedIdentity == identity {
        dayMeasurements(evidence)
      } else if let error {
        Section { Text(error); Button("Retry") { Task { await loadDay() } } }
      } else {
        Section { ProgressView("Loading this day's measurements") }
      }
      Section {
        if let entry {
          MetricRow(label: "Energy", value: entry.energy.map { "\($0)/5" } ?? "Not answered")
          MetricRow(label: "Mood", value: entry.mood.map { "\($0)/5" } ?? "Not answered")
          MetricRow(label: "Soreness", value: entry.soreness.map { "\($0)/5" } ?? "Not answered")
          DisclosureGroup("Sleep & behaviours") {
            MetricRow(label: "Sleep quality", value: entry.sleepQuality.map { "\($0)/5" } ?? "Not answered")
            MetricRow(label: "Feeling unwell", value: entry.unwell.map { $0 ? "Yes" : "No" } ?? "Not answered")
            MetricRow(label: "Alcohol", value: entry.alcohol.map { $0 ? "Yes" : "No" } ?? "Not answered")
            MetricRow(label: "Late meal", value: entry.lateMeal.map { $0 ? "Yes" : "No" } ?? "Not answered")
            if let time = entry.caffeineTime {
              MetricRow(label: "Last caffeine", value: time.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened,
                timeZone: TimeZone(identifier: entry.timeZoneID) ?? .current)))
            } else { MetricRow(label: "Last caffeine", value: "Not answered") }
          }.font(.subheadline)
          if !entry.note.isEmpty { Text(entry.note) }
          Button("Edit check-in") { journal = entry }
        } else {
          Text("No check-in recorded").foregroundStyle(.secondary)
          Button("Add check-in") {
            journal = JournalEntry(date: Calendar.current.date(bySettingHour: 12, minute: 0,
              second: 0, of: day) ?? day)
          }
        }
      } header: { Text("Your check-in") } footer: { Text("Unanswered questions stay unknown, never “no”.") }
      if let loadedAt, loadedIdentity == identity {
        Section {
          Text("Measurements loaded \(loadedAt.formatted(date: .omitted, time: .shortened)). Pull down to refresh.")
            .font(.caption).foregroundStyle(.secondary)
          if let error { Text(error).font(.caption).foregroundStyle(.secondary) }
        }
      }
    }.navigationTitle("Your days")
      .task(id: identity) { await loadDay() }
      .onAppear { isVisible = true; scheduleRefresh(delay: .zero) }
      .onChange(of: model.historyGeneration) { _, _ in scheduleRefresh() }
      .onChange(of: identity) { _, _ in scheduledRefresh?.cancel(); scheduledRefresh = nil }
      .onChange(of: scenePhase) { _, phase in
        if phase == .active { scheduleRefresh(delay: .zero) }
        else { scheduledRefresh?.cancel(); scheduledRefresh = nil }
      }
      .onDisappear { isVisible = false; scheduledRefresh?.cancel(); scheduledRefresh = nil }
      .refreshable { await model.refreshToday(); await loadDay() }
      .sheet(item: $journal) { entry in NavigationStack { JournalEditor(entry: entry) } }
      .sheet(isPresented: $addSleep) { NavigationStack { SleepEditor(initialDay: day) } }
  }
  @ViewBuilder private func dayMeasurements(_ value: DayEvidence) -> some View {
    Section("Recorded heart rate") {
      if value.receipt.sampleCount > 0 {
        MetricRow(label: "Recorded coverage", value: durationText(value.receipt.coveredSeconds))
        MetricRow(label: "Covered-time average", value: value.receipt.average.map { String(format: "%.0f bpm", $0) } ?? "Insufficient continuous readings")
        Text("\(value.receipt.sampleCount) reconciled readings · gaps excluded").font(.caption).foregroundStyle(.secondary)
        if value.truncated { Text("Sample cap reached; this day's view may be incomplete.").font(.caption).foregroundStyle(.secondary) }
        DisclosureGroup("Sources and quality") {
          Text(value.receipt.sourceIDs.map { id in model.devices.first { $0.id == id }?.name
            ?? model.archivedDevices.first { $0.id == id }?.name ?? "Imported or unresolved source" }.joined(separator: " · "))
          Text("Recorded coverage may include imported HR. Unknown quality flags can be displayed but do not qualify for load or recovery.")
        }.font(.caption).foregroundStyle(.secondary)
      } else { Text("No qualifying heart rate for this day").foregroundStyle(.secondary) }
    }
    Section("Movement estimate") {
      if let load = value.load, load.coveredSeconds > 60 {
        MetricRow(label: "Cardiovascular load", value: String(format: "%.0f points", load.points))
        Text("From \(durationText(load.coveredSeconds)) of quality-eligible HR · Edwards estimate")
          .font(.caption).foregroundStyle(.secondary)
      } else { Text("Insufficient qualifying coverage").foregroundStyle(.secondary) }
    }
    if !value.metrics.isEmpty {
      Section {
        ForEach(value.metrics) { summary in
          VStack(alignment: .leading, spacing: 4) {
            MetricRow(label: metricTitle(summary.kind), value: String(format: "%.1f %@", summary.value, summary.kind == .weight ? "kg" : summary.kind == .restingHeartRate ? "bpm" : "ms"))
            Text("\(summary.method) · \(summary.inputCount) inputs · \(summary.inputOrigins.map { $0.rawValue.capitalized }.joined(separator: ", "))")
              .font(.caption).foregroundStyle(.secondary)
            if summary.truncated {
              Text("Sample cap reached · this daily value is incomplete")
                .font(.caption).foregroundStyle(.secondary)
            }
          }
        }
      } header: { Text("Other recorded measurements") } footer: { Text("HRV contexts may differ. These daily values are not necessarily overnight measurements.") }
    }
  }
  private func metricTitle(_ kind: MetricKind) -> String {
    switch kind {
    case .restingHeartRate: "Resting heart rate"
    case .rmssd: "HRV · RMSSD"
    case .sdnn: "HRV · SDNN"
    case .weight: "Weight"
    default: kind.rawValue
    }
  }
  private func move(_ direction: Int) {
    if let date = Calendar.current.date(byAdding: .day, value: direction, to: day) {
      day = min(date, Calendar.current.startOfDay(for: Date()))
    }
  }
  @MainActor private func scheduleRefresh(delay: Duration = .seconds(2)) {
    scheduledRefresh?.cancel()
    guard isVisible, scenePhase == .active else { scheduledRefresh = nil; return }
    let expected = identity
    scheduledRefresh = Task {
      do { try await Task.sleep(for: delay) } catch { return }
      guard !Task.isCancelled, identity == expected, isVisible, scenePhase == .active else { return }
      await loadDay()
      if !Task.isCancelled { scheduledRefresh = nil }
    }
  }
  @MainActor private func loadDay() async {
    let requested = identity
    let token = UUID(); request = token
    let store = model.store
    guard let store else { error = "Local history is not available yet."; return }
    if loadedIdentity != requested { evidence = nil; loadedAt = nil }
    error = nil
    let window = DayHistory.window(for: requested.day)
    let until = min(window.end, Date())
    let segments = model.sourceSegments
    let maximum = model.maxHeartRate
    do {
      try await Task.sleep(for: .milliseconds(150))
      try Task.checkCancellation()
      let hr = try await store.measurements(from: window.start, to: until, kinds: [.heartRate])
      let kinds: [MetricKind] = [.restingHeartRate, .rmssd, .sdnn, .weight]
      let other = try await store.measurements(from: window.start, to: until, kinds: kinds, limit: 2000)
      try Task.checkCancellation()
      let result = await Task.detached(priority: .utility) {
        let canonical = CanonicalTimeline.select(hr, sourceSegments: segments)
        var metrics = kinds.flatMap { DailyTrendSummary.calculate(other, kind: $0,
          sourceSegments: segments, allowSynthetic: requested.demo) }
        if other.count >= 2000 { for i in metrics.indices { metrics[i].truncated = true } }
        return DayEvidence(receipt: LiveHistorySnapshot(samples: hr, from: window.start, to: until,
          sourceSegments: segments, maximumHeartRate: maximum, allowSynthetic: requested.demo, includeImported: true),
          load: CardiovascularLoad.calculate(canonical, maxHeartRate: maximum),
          metrics: metrics, truncated: hr.count >= 100_000)
      }.value
      guard !Task.isCancelled, identity == requested, request == token else { return }
      evidence = result; loadedIdentity = requested; loadedAt = Date()
    } catch is CancellationError { return }
    catch {
      guard identity == requested, request == token else { return }
      self.error = "This day's measurements couldn't load. Stored history is unchanged."
    }
  }
}

struct SleepRhythmView: View {
  @Environment(AppModel.self) private var model
  @State private var days = 14
  private var start: Date {
    Calendar.current.date(byAdding: .day, value: -(days - 1), to: Calendar.current.startOfDay(for: Date()))!
  }
  private var entries: [SleepRhythmEntry] {
    DayHistory.primarySleeps(model.sleeps.filter { $0.end >= start }, now: Date(), allowSynthetic: model.demo)
      .compactMap { SleepRhythmEntry(session: $0) }
  }
  var body: some View {
    let entries = self.entries
    return List {
      Section {
        Picker("Sleep rhythm range", selection: $days) {
          Text("14 days").tag(14); Text("28 days").tag(28)
        }.pickerStyle(.segmented)
        Text("When you sleep").font(.title2.weight(.semibold))
        Text("\(entries.count) of \(days) wake dates recorded")
          .font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("sleep-rhythm-coverage")
        if entries.isEmpty {
          ContentUnavailableView("No saved nights yet", systemImage: "bed.double",
            description: Text("Save or confirm your sleep timing to see its rhythm. Missing nights remain empty."))
        } else {
          Chart(entries) { entry in
            BarMark(xStart: .value("Fell asleep", entry.startHour), xEnd: .value("Woke up", entry.endHour),
              y: .value("Wake day", Calendar.current.startOfDay(for: entry.session.end)))
              .foregroundStyle(.indigo).cornerRadius(3)
              .accessibilityLabel(entry.session.end.formatted(date: .abbreviated, time: .omitted))
              .accessibilityValue("\(durationText(entry.session.duration)), \(entry.session.origin.rawValue)")
          }.chartXScale(domain: min(-12, entries.map(\.startHour).min() ?? -12)...24)
            .chartYScale(domain: start...Calendar.current.startOfDay(for: Date()).addingTimeInterval(12 * 3600))
            .chartXAxis {
              AxisMarks(values: [-12.0, -6, 0, 6, 12, 18, 24]) { value in
                AxisGridLine()
                AxisValueLabel {
                  if let hour = value.as(Double.self) { Text(clockLabel(hour)) }
                }
              }
            }.chartYAxis { AxisMarks(format: .dateTime.day().month(.abbreviated), values: .stride(by: .day, count: days == 14 ? 2 : 4)) }
            .frame(height: 280).accessibilityLabel("Saved sleep clock timings; missing wake dates remain empty")
        }
      } footer: {
        Text("Dates use this iPhone's calendar. Clock times use each session's recorded timezone, so travel can shift the pattern. Bar width is clock timing; elapsed duration can differ across daylight-saving changes.")
      }
      Section {
        ForEach(entries.reversed()) { entry in
          NavigationLink { SleepDetailView(sleep: entry.session) } label: {
            MetricRow(label: entry.session.end.formatted(date: .abbreviated, time: .omitted),
              value: durationText(entry.session.duration))
          }
        }
      } header: { Text("Recorded nights") } footer: {
        Text("One primary saved session per wake date; naps, unconfirmed estimates and fragmented imports are excluded. This view does not establish sleep stages or sleep quality.")
      }
    }.navigationTitle("Sleep rhythm")
  }
  private func clockLabel(_ hour: Double) -> String {
    let h = (Int(hour) % 24 + 24) % 24
    return h == 0 ? "00:00" : String(format: "%02d:00", h)
  }
}

/// AppModel publishes reconciled sessions; bound repeated UI projections to their visible window.
@MainActor private func observationSessions(_ model: AppModel) -> [SleepSession] {
  let from = Calendar.current.date(byAdding: .day, value: -29,
    to: Calendar.current.startOfDay(for: Date()))!
  return model.sleeps.filter { $0.end >= from }
}

/// A visible entry into sleep timing, using the same saved-night projection as the detail.
struct SleepRhythmCard: View {
  @Environment(AppModel.self) private var model
  var body: some View {
    let start = Calendar.current.date(byAdding: .day, value: -13,
      to: Calendar.current.startOfDay(for: Date()))!
    let entries = DayHistory.primarySleeps(model.sleeps.filter { $0.end >= start },
      now: Date(), allowSynthetic: model.demo).compactMap { SleepRhythmEntry(session: $0) }
    NavigationLink { SleepRhythmView() } label: {
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          Label("Sleep rhythm", systemImage: "moon.zzz.fill")
            .font(.headline).foregroundStyle(.primary)
          Spacer()
          Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }
        Text(entries.isEmpty ? "See when you sleep and wake" : "\(entries.count) of 14 nights recorded")
          .font(.subheadline).foregroundStyle(.secondary)
        if !entries.isEmpty {
          Chart(entries) { entry in
            BarMark(x: .value("Wake date", Calendar.current.startOfDay(for: entry.session.end)),
              yStart: .value("Bedtime", entry.startHour), yEnd: .value("Wake time", entry.endHour))
              .foregroundStyle(.indigo).cornerRadius(2)
          }.chartXScale(domain: start...Calendar.current.startOfDay(for: Date()).addingTimeInterval(12 * 3600))
            .chartXAxis(.hidden).chartYAxis(.hidden).frame(height: 54)
            .accessibilityHidden(true)
        } else {
          Text("Save or confirm a night to build your timing picture.")
            .font(.caption).foregroundStyle(.secondary)
        }
        Text("View sleep rhythm").font(.subheadline.weight(.medium)).foregroundStyle(.indigo)
      }.padding(18).background(Color(uiColor: .secondarySystemGroupedBackground),
        in: RoundedRectangle(cornerRadius: 24)).contentShape(Rectangle())
    }.buttonStyle(.plain).accessibilityIdentifier("trends-sleep-rhythm")
  }
}
