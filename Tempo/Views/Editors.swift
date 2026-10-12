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
            Text("\(level)").font(.body.weight(.semibold))
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
    }.navigationTitle(existing == nil ? "Record sleep" : "Correct sleep").toolbar {
      ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
      ToolbarItem(placement: .confirmationAction) {
        Button("Save") {
          model.mutate {
            var s = SleepSession(
              start: start, end: end, timeZoneID: TimeZone.current.identifier, origin: .manual)
            s.isNap = nap
            if let existing { s.id = existing.id }
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
struct SleepDetailView: View {
  @Environment(AppModel.self) var model
  let sleep: SleepSession
  @State private var edit = false
  @State private var newSleep = false
  @State private var placementDescription = "No band measurements to associate"
  var body: some View {
    List {
      Section {
        MetricRow(label: "Duration", value: durationText(sleep.duration))
        Text("\(sleep.start.formatted()) – \(sleep.end.formatted())")
        Text("Timezone: \(sleep.timeZoneID)")
        Text("Source: \(sleep.origin.rawValue)")
        Text("Reported placement: \(placementDescription)")
      }
      Section("Overnight evidence") {
        let inputs = model.nightInputs(sleep)
        MetricRow(
          label: "Resting HR estimate",
          value: inputs["rhr"].map { String(format: "%.0f bpm", $0) } ?? "Insufficient coverage")
        MetricRow(
          label: "RMSSD",
          value: inputs["rmssd"].map { String(format: "%.0f ms", $0) } ?? "Insufficient valid RR")
        Text(
          "Sleep staging, respiratory rate and oxygen saturation are unavailable. Sensor presence alone does not establish a measurement."
        ).font(.caption).foregroundStyle(.secondary)
      }
      Section {
        Button("Correct timing") { edit = true }
        Button("Add another sleep session") { newSleep = true }
        Button("Delete sleep", role: .destructive) {
          model.mutate { try await model.delete(id: sleep.id, kind: "sleep") }
        }
      }
    }.navigationTitle("Sleep").task(id: model.placements) {
      if let store = model.store,
        let samples = try? await store.measurements(
          from: sleep.start, to: sleep.end, kinds: [.heartRate])
      {
        placementDescription = PlacementTimeline.description(
          samples: CanonicalTimeline.select(samples, sourceSegments: model.sourceSegments),
          records: model.placements)
      }
    }.sheet(isPresented: $edit) {
      NavigationStack { SleepEditor(existing: sleep) }
    }.sheet(isPresented: $newSleep) {
      NavigationStack { SleepEditor() }
    }
  }
}
