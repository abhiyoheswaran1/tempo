import Charts
import SwiftUI
import TempoCore

struct JournalEditor: View {
  @Environment(AppModel.self) var model
  @Environment(\.dismiss) var dismiss
  @State var entry = JournalEntry()
  @State private var showContext = false
  var body: some View {
    Form {
      Section("A quick check-in") {
        rating("Energy", $entry.energy)
        rating("Soreness", $entry.soreness)
        rating("Mood", $entry.mood)
      }
      Section {
        DisclosureGroup("Sleep & behaviours · optional", isExpanded: $showContext) {
          rating("Perceived sleep quality", $entry.sleepQuality)
          answer("Feeling unwell", $entry.unwell)
          answer("Alcohol", $entry.alcohol)
          answer("Late meal", $entry.lateMeal)
          Toggle(
            "Add caffeine timing",
            isOn: Binding(
              get: { entry.caffeineTime != nil }, set: { entry.caffeineTime = $0 ? Date() : nil }))
          if entry.caffeineTime != nil {
            DatePicker(
              "Last caffeine",
              selection: Binding(
                get: { entry.caffeineTime ?? Date() }, set: { entry.caffeineTime = $0 }),
              displayedComponents: [.hourAndMinute])
          }
        }.accessibilityIdentifier("journal-optional-context")
      }
      Section("Notes · optional") {
        TextField("Anything else?", text: $entry.note, axis: .vertical)
          .accessibilityIdentifier("journal-note")
      }
      Section {
        Text("Every field is optional. A blank answer is unknown, never “no”.").font(.caption)
          .foregroundStyle(.secondary)
      }
    }.navigationTitle("Your journal").toolbar {
      ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
      ToolbarItem(placement: .confirmationAction) {
        Button("Save") {
          model.mutate {
            try await model.save(entry, kind: "journal")
            dismiss()
          }
        }
      }
    }
  }
  func rating(_ label: String, _ value: Binding<Int?>) -> some View {
    let identifier = label.lowercased().replacingOccurrences(of: " ", with: "-")
    return VStack(alignment: .leading, spacing: 8) {
      Text(label).font(.headline)
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], spacing: 8) {
        ForEach(1...5, id: \.self) { level in
          Button { value.wrappedValue = level } label: {
            Text("\(level)").font(.body.weight(.semibold)).foregroundStyle(.primary)
              .frame(maxWidth: .infinity, minHeight: 44)
          }
          .buttonStyle(.bordered)
          .tint(value.wrappedValue == level ? .teal : .secondary)
          .accessibilityLabel("\(label), \(level) of 5")
          .accessibilityAddTraits(value.wrappedValue == level ? .isSelected : [])
          .accessibilityIdentifier("journal-\(identifier)-\(level)")
        }
      }
      Text("1 = low · 5 = high").font(.caption).foregroundStyle(.secondary)
      HStack {
        Text(value.wrappedValue.map { "\($0) of 5" } ?? "Not entered")
          .font(.subheadline).foregroundStyle(.secondary)
        Spacer()
        Button("Clear") { value.wrappedValue = nil }
          .buttonStyle(.borderless).frame(minHeight: 44)
          .disabled(value.wrappedValue == nil)
          .accessibilityLabel("Clear \(label.lowercased())")
          .accessibilityIdentifier("journal-\(identifier)-clear")
      }
    }.padding(.vertical, 4)
  }
  func answer(_ label: String, _ value: Binding<Bool?>) -> some View {
    Picker(label, selection: value) {
      Text("Not entered").tag(Bool?.none)
      Text("No").tag(Bool?.some(false))
      Text("Yes").tag(Bool?.some(true))
    }
  }
}
struct SleepEditor: View {
  @Environment(AppModel.self) var model
  @Environment(\.dismiss) var dismiss
  var existing: SleepSession?
  @State private var start = Date().addingTimeInterval(-8 * 3600)
  @State private var end = Date()
  @State private var nap = false
  var body: some View {
    Form {
      Section("Sleep timing") {
        DatePicker("Fell asleep", selection: $start)
        DatePicker("Woke up", selection: $end)
        Toggle("Nap", isOn: $nap)
      }
      Section {
        Text(
          "Manual corrections retain their own revision and survive recomputation. Duration uses elapsed UTC time; local timezone is retained."
        ).font(.caption).foregroundStyle(.secondary)
      }
    }.navigationTitle(existing?.origin == .derived ? "Review possible sleep" : existing == nil ? "Record sleep" : "Correct sleep").toolbar {
      ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
      ToolbarItem(placement: .confirmationAction) {
        Button("Save") {
          model.mutate {
            var s = SleepSession(
              start: start, end: end, timeZoneID: TimeZone.current.identifier, origin: .manual)
            s.isNap = nap
            if let existing {
              s.id = existing.id
              s.algorithmVersion = existing.algorithmVersion
              s.detectionInputDigest = existing.detectionInputDigest
              s.detectionInputCount = existing.detectionInputCount
              s.detectionCoverage = existing.detectionCoverage
            }
            try await model.save(s, kind: "sleep")
            dismiss()
          }
        }.disabled(end <= start || end.timeIntervalSince(start) > 24 * 3600)
      }
    }.onAppear {
      if let existing {
        start = existing.start
        end = existing.end
        nap = existing.isNap
      }
    }
  }
}
private struct SleepEvidenceIdentity: Hashable {
  let id: UUID
  let start: Date
  let end: Date
  let generation: Int
  let demo: Bool
  let store: ObjectIdentifier?
}

struct SleepDetailView: View {
  @Environment(AppModel.self) var model
  @Environment(\.dismiss) var dismiss
  let sleep: SleepSession
  @State private var edit = false
  @State private var newSleep = false
  @State private var confirmDelete = false
  @State private var placementDescription = "No band measurements to associate"
  @State private var snapshot: LiveHistorySnapshot?
  @State private var coverageIncomplete = false
  @State private var evidenceError = false
  private var current: SleepSession { model.sleeps.first { $0.id == sleep.id } ?? sleep }
  private var identity: SleepEvidenceIdentity {
    SleepEvidenceIdentity(id: current.id, start: current.start, end: current.end,
      generation: model.historyGeneration, demo: model.demo,
      store: model.store.map { ObjectIdentifier($0) })
  }
  private var originLabel: String {
    switch current.origin {
    case .manual: "Manually entered"
    case .imported: "Imported measurement"
    case .derived: "Estimated sleep"
    case .synthetic: "Synthetic demo"
    case .measured: "Measured session"
    }
  }
  var body: some View {
    List {
      Section {
        VStack(alignment: .leading, spacing: 10) {
          Label(current.isNap ? "Nap" : "Sleep", systemImage: "bed.double.fill")
            .font(.subheadline).foregroundStyle(.indigo)
          Text(durationText(current.duration))
            .font(.largeTitle.weight(.semibold)).monospacedDigit()
            .accessibilityIdentifier("sleep-duration")
          Text(originLabel).font(.subheadline).foregroundStyle(.secondary)
        }.padding(.vertical, 8)
        MetricRow(label: "Fell asleep", value: timing(current.start))
        MetricRow(label: "Woke up", value: timing(current.end))
        Button("Correct timing") { edit = true }
      } footer: {
        Text("Times shown in \(current.timeZoneID). Duration uses elapsed time, including clock changes.")
      }
      Section("Heart rate during sleep") {
        if let snapshot, snapshot.sampleCount > 0 {
          MetricRow(label: "Recorded average", value: snapshot.average.map { String(format: "%.0f bpm", $0) } ?? "Insufficient continuous readings")
          let segments = Dictionary(grouping: snapshot.points, by: \.segment)
          Chart(snapshot.points) { point in
            LineMark(x: .value("Time", point.sample.timestamp),
              y: .value("Heart rate", point.sample.value),
              series: .value("Recorded segment", point.segment))
              .foregroundStyle(.indigo)
            if segments[point.segment]?.count == 1 {
              PointMark(x: .value("Time", point.sample.timestamp),
                y: .value("Heart rate", point.sample.value)).foregroundStyle(.indigo)
            }
          }.chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
              AxisGridLine()
              AxisTick()
              AxisValueLabel {
                if let date = value.as(Date.self) { Text(timing(date, includeDate: false)) }
              }
            }
          }.chartLegend(.hidden).chartXScale(domain: current.start...current.end)
            .chartYScale(domain: max(25, (snapshot.minimum ?? 25) - 10)...max(26, (snapshot.maximum ?? 240) + 10))
            .chartYAxisLabel("bpm").frame(height: 160)
            .accessibilityLabel("Heart rate during this sleep session; gaps remain empty")
          MetricRow(label: "Recorded coverage", value: durationText(snapshot.coveredSeconds))
          Text("\(snapshot.sampleCount) readings · gaps excluded")
            .font(.caption).foregroundStyle(.secondary)
          if coverageIncomplete {
            Text("Sample limit reached. This view covers only part of the stored readings.")
              .font(.caption).foregroundStyle(.secondary)
          }
          if snapshot.hasUnqualifiedReadings {
            Text("Some readings have unresolved quality flags. They are shown here but excluded from recovery calculations.")
              .font(.caption).foregroundStyle(.secondary)
          }
        } else {
          Text(evidenceError ? "Measurements could not load" : snapshot == nil ? "Loading measurements" : "No qualifying heart rate recorded")
            .foregroundStyle(.secondary)
          Text("Sleep timing can be recorded even when overnight measurements are unavailable.")
            .font(.caption).foregroundStyle(.secondary)
        }
      }
      Section("Recovery inputs") {
        let inputs = model.nightInputs(current)
        MetricRow(label: "Resting HR estimate",
          value: inputs["rhr"].map { String(format: "%.0f bpm", $0) } ?? "Insufficient coverage")
        MetricRow(label: "HRV · RMSSD",
          value: inputs["rmssd"].map { String(format: "%.0f ms", $0) } ?? "Insufficient valid RR")
        DisclosureGroup("Source and calculation") {
          Text("Reported placement: \(placementDescription)")
          if let snapshot {
            Text(snapshot.sourceIDs.map { id in
              model.devices.first { $0.id == id }?.name
                ?? model.archivedDevices.first { $0.id == id }?.name ?? "Unresolved source"
            }.joined(separator: " · "))
          }
          Text("Recorded average describes available heart rate within these timings; it is separate from the resting HR estimate.")
          Text("RMSSD requires valid beat-to-beat intervals. Heart rate alone cannot establish HRV.")
          if let version = current.algorithmVersion { Text("Detection algorithm: \(version)") }
          Text("Sleep stages, respiratory rate and oxygen saturation are unavailable.")
        }.font(.caption).foregroundStyle(.secondary)
      }
      Section {
        Button("Add another sleep session") { newSleep = true }
        Button("Delete sleep", role: .destructive) { confirmDelete = true }
      }
    }.navigationTitle("Sleep")
      .task(id: identity) { await loadEvidence() }
      .sheet(isPresented: $edit) {
        NavigationStack { SleepEditor(existing: current) }
      }.sheet(isPresented: $newSleep) {
        NavigationStack { SleepEditor() }
      }.alert("Delete this sleep session?", isPresented: $confirmDelete) {
        Button("Delete sleep", role: .destructive) {
          model.mutate {
            try await model.delete(id: current.id, kind: "sleep")
            dismiss()
          }
        }
        Button("Cancel", role: .cancel) {}
      } message: { Text("The session will be removed. Original band measurements are retained.") }
  }
  private func timing(_ date: Date, includeDate: Bool = true) -> String {
    let formatter = DateFormatter()
    formatter.timeZone = TimeZone(identifier: current.timeZoneID) ?? .current
    formatter.dateStyle = includeDate ? .medium : .none
    formatter.timeStyle = .short
    return formatter.string(from: date)
  }
  @MainActor private func loadEvidence() async {
    let requested = identity
    let session = current
    let store = model.store
    let segments = model.sourceSegments
    let demo = model.demo
    snapshot = nil
    evidenceError = false
    do {
      let samples = try await store?.measurements(from: session.start, to: session.end,
        kinds: [.heartRate], limit: 100_000) ?? []
      let summary = await Task.detached(priority: .utility) {
        LiveHistorySnapshot(samples: samples, from: session.start, to: session.end,
          sourceSegments: segments, maximumHeartRate: 190, allowSynthetic: demo)
      }.value
      guard !Task.isCancelled, identity == requested else { return }
      snapshot = summary
      coverageIncomplete = samples.count >= 100_000
      placementDescription = PlacementTimeline.description(
        samples: CanonicalTimeline.select(samples, sourceSegments: segments), records: model.placements)
    } catch {
      guard !Task.isCancelled, identity == requested else { return }
      evidenceError = true
    }
  }
}
