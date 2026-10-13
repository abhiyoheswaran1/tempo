import SwiftUI
import TempoCore

private struct StoredCoverage: Sendable {
  let value: CollectionCoverage
  let truncated: Bool
  let store: ObjectIdentifier
  let demo: Bool
  let seconds: Int
}
@MainActor private func readCoverage(_ model: AppModel, seconds: Int) async throws -> StoredCoverage? {
  guard let store = model.store, !model.transitioningDataset else { return nil }
  let demo = model.demo, now = Date(), from = now.addingTimeInterval(Double(-seconds))
  let records = try await store.measurements(from: from, to: now.addingTimeInterval(0.001), kinds: [.heartRate])
  try Task.checkCancellation()
  let calculation = Task.detached(priority: .utility) {
    try Task.checkCancellation()
    return CollectionCoverage(samples: records, from: from, to: now, allowSynthetic: demo)
  }
  let value = try await withTaskCancellationHandler { try await calculation.value }
    onCancel: { calculation.cancel() }
  guard !Task.isCancelled, model.store === store, model.demo == demo, !model.transitioningDataset else { return nil }
  return StoredCoverage(value: value, truncated: records.count >= 100000,
    store: ObjectIdentifier(store), demo: demo, seconds: seconds)
}

struct RecordedCoverageSummary: View {
  @Environment(AppModel.self) private var model
  @Environment(\.scenePhase) private var phase
  @State private var visible = false
  @State private var snapshot: StoredCoverage?
  var body: some View {
    TimelineView(.periodic(from: .now, by: 300)) { context in
      NavigationLink { RecordedCoverageView() } label: {
        HStack(spacing: 4) {
          if snapshot?.store == model.store.map(ObjectIdentifier.init), snapshot?.demo == model.demo,
            let latest = snapshot?.value.latestRecord {
            Text("Recorded through")
            Text(latest, format: .dateTime.hour().minute())
          } else { Text("Check recorded coverage") }
          Image(systemName: "chevron.right").font(.caption2)
        }
      }.buttonStyle(.plain).accessibilityIdentifier("today-recorded-coverage")
        .task(id: "\(model.store.map(ObjectIdentifier.init)?.hashValue ?? 0)-\(model.demo)-\(model.historyGeneration)-\(Int(context.date.timeIntervalSince1970/300))-\(visible)-\(phase == .active)") {
          guard visible, phase == .active else { return }
          do { snapshot = try await readCoverage(model, seconds: 12*3600) } catch { /* Detail has retry and the actionable error. */ }
        }
    }.onAppear { visible = true }.onDisappear { visible = false }
  }
}

struct RecordedCoverageView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.scenePhase) private var phase
  @State private var visible = false
  @State private var request = UUID()
  @State private var seconds = 12*3600
  @State private var snapshot: StoredCoverage?
  @State private var error: String?
  var body: some View {
    TimelineView(.periodic(from: .now, by: 300)) { context in
      List {
        Section {
          Picker("Coverage range", selection: $seconds) {
            Text("12 hours").tag(12*3600); Text("24 hours").tag(24*3600)
          }.pickerStyle(.segmented)
          if let snapshot, snapshot.store == model.store.map(ObjectIdentifier.init),
            snapshot.demo == model.demo, snapshot.seconds == seconds {
            let coverage = snapshot.value
            Text(durationText(coverage.coveredSeconds)).font(.largeTitle.weight(.semibold))
              .accessibilityIdentifier("coverage-amount")
            Text("Received HR coverage · \(Int(coverage.fraction*100))% of this period")
              .font(.subheadline).foregroundStyle(.secondary)
            ProgressView(value: coverage.fraction).tint(.teal)
            if let latest = coverage.latestRecord {
              LabeledContent("Latest stored record", value: latest.formatted(date: .abbreviated, time: .shortened))
            } else { Text("No band heart-rate records in this period") }
            Text("\(coverage.sampleCount) stored records · \(coverage.historicalCount) from band history")
              .font(.caption).foregroundStyle(.secondary)
            Text("Checked \(coverage.to.formatted(date: .omitted, time: .shortened))")
              .font(.caption).foregroundStyle(.secondary)
            if snapshot.truncated { Text("Record limit reached. Coverage is incomplete.").font(.caption) }
            if coverage.hasUnqualifiedRecords {
              Text("Includes received records with unresolved signal quality. This is separate from coverage used for physiological analytics.")
                .font(.caption).foregroundStyle(.secondary)
            }
          } else if let error {
            Text(error)
            Button("Retry") { Task { await load() } }
          } else { ProgressView("Checking stored records") }
        } footer: { Text("Coverage is estimated between HR receipts at most 10 seconds apart, across your bands. It does not establish sleep, wear status or measurement quality. Imported Health records are excluded.") }
        if let snapshot, snapshot.store == model.store.map(ObjectIdentifier.init),
          snapshot.demo == model.demo, snapshot.seconds == seconds {
          let gaps = snapshot.value.gaps.filter { $0.duration >= 60 }
          Section {
            if gaps.isEmpty { Text("No missing period longer than a minute") }
            ForEach(Array(gaps.prefix(20).enumerated()), id: \.offset) { _, gap in
              VStack(alignment: .leading, spacing: 4) {
                Text("\(gap.start.formatted(date: .abbreviated, time: .shortened))–\(gap.end.formatted(date: .abbreviated, time: .shortened))")
                  .font(.subheadline)
                Text(durationText(gap.duration)).font(.caption).foregroundStyle(.secondary)
              }
            }
            if gaps.count > 20 { Text("Showing 20 of \(gaps.count) periods") }
          } header: { Text("Missing periods · a minute or more") } footer: { Text("A missing record does not identify its cause. Catch-up can fill a period only when the band returns stored records. Your existing observations stay saved.") }
        }
        Section {
          NavigationLink("Overnight reliability") { OvernightReliabilityView() }
          NavigationLink("Band status and history") { BandStatusSheet() }
        }
      }.navigationTitle("Recorded coverage")
        .refreshable { await model.refreshToday(); await load() }
        .task(id: "\(seconds)-\(model.store.map(ObjectIdentifier.init)?.hashValue ?? 0)-\(model.demo)-\(model.historyGeneration)-\(Int(context.date.timeIntervalSince1970/300))-\(visible)-\(phase == .active)") {
          guard visible, phase == .active else { return }; await load()
        }
    }.onAppear { visible = true }.onDisappear { visible = false }
  }
  @MainActor private func load() async {
    guard visible, phase == .active else { return }
    let token = UUID(), range = seconds, store = model.store.map(ObjectIdentifier.init), demo = model.demo
    request = token
    func current() -> Bool {
      request == token && seconds == range && model.store.map(ObjectIdentifier.init) == store
        && model.demo == demo && visible && phase == .active && !Task.isCancelled && !model.transitioningDataset
    }
    do {
      let result = try await readCoverage(model, seconds: range)
      guard current() else { return }
      snapshot = result; error = nil
    } catch { if current() { self.error = "Stored coverage couldn't load. Pull to retry." } }
  }
}

struct OvernightReliabilityView: View {
  @Environment(AppModel.self) private var model
  var body: some View {
    List {
      Section {
        Toggle("Collect reliability reports", isOn: Binding(get: { model.reliability.enabled },
          set: { model.reliability.setEnabled($0) })).disabled(model.demo)
        Text("Off by default. Up to seven CPU/memory reports stay on this iPhone; they contain no sensor readings and are never uploaded.")
          .font(.caption).foregroundStyle(.secondary)
      }
      if model.demo || model.reliability.archive.reports.isEmpty {
        Section {
          ContentUnavailableView("No system reports yet", systemImage: "moon.stars",
            description: Text(model.demo ? "Real reliability reports are disabled in demo mode." : "Enable collection, use Tempo normally and check again after the next reporting period. Delivery may take more than 24 hours."))
        }
      } else {
        ForEach(model.reliability.archive.reports) { report in
          Section {
            LabeledContent("Total CPU time", value: report.cpuSeconds.map { durationText($0) } ?? "Not reported")
            LabeledContent("Peak memory", value: report.peakMemoryMB.map { String(format:"%.1f MB",$0) } ?? "Not reported")
            LabeledContent("Background CPU-limit exits", value: report.backgroundCPUExits.map(String.init) ?? "Not reported")
            if let version = report.appVersion { LabeledContent("App version", value: version) }
            if report.includesMultipleVersions == true { Text("This period includes multiple app versions.").font(.caption) }
          } header: { Text("\(report.start.formatted(date:.abbreviated,time:.shortened))–\(report.end.formatted(date:.abbreviated,time:.shortened))") }
        }
      }
      if let error = model.reliability.error { Section { Text(error) } }
      Section("Tonight") {
        Text("Wear your band normally. Let Tempo connect and request stored history, then lock your iPhone without force-quitting Tempo.")
        Text("In the morning, pull to sync on Today and inspect12-hour coverage. Compare missing periods with the band history status.")
        Text("Check iPhone Settings → Battery → Tempo for app battery use. CPU time is not battery consumption; system reports cover their whole reporting period, including possible earlier builds or demo use.")
      }
      if !model.demo, !model.reliability.archive.reports.isEmpty {
        Section { Button("Clear local reports", role:.destructive) { model.reliability.clear() } }
      }
    }.navigationTitle("Overnight reliability")
  }
}
