import SwiftUI
import TempoCore

struct PlacementView: View {
  @Environment(AppModel.self) var model
  let device: RegisteredDevice
  @State private var editor = false
  var history: [PlacementRecord] {
    Dictionary(grouping: model.placements.filter { $0.deviceID == device.id }, by: \.id).values
      .compactMap {
        $0.min { $0.effectiveFrom < $1.effectiveFrom }
      }.sorted { $0.effectiveFrom > $1.effectiveFrom }
  }
  var body: some View {
    List {
      Section("Reported placement") {
        Text(
          PlacementTimeline.resolve(deviceID: device.id, at: Date(), records: model.placements)
            .title
        ).font(.title2)
        Text(
          "Choose where this band is now whenever you move it. This is your report; Tempo cannot detect its body location from Bluetooth or contact flags."
        )
        ForEach([BodyPlacement.wrist, .upperArm, .underwear], id: \.self) { placement in
          Button("Now: \(placement.title)") {
            model.mutate {
              try await model.recordPlacement(
                deviceID: device.id, placement: placement, effectiveFrom: Date())
            }
          }
        }
        Button("Record an earlier change") { editor = true }
      }
      Section("Placement history · this band") {
        ForEach(history) { record in
          NavigationLink {
            PlacementEditor(device: device, existing: record)
          } label: {
            VStack(alignment: .leading) {
              Text(
                model.conflictEntities.contains(record.id)
                  ? "Conflicting reports · placement unknown" : record.placement.title)
              Text(record.effectiveFrom.formatted()).font(.caption).foregroundStyle(.secondary)
            }
          }.disabled(model.conflictEntities.contains(record.id))
        }
        if !model.placements.contains(where: { $0.deviceID == device.id }) {
          Text("No placement recorded. Earlier measurements remain unknown.")
        }
      }
      Section("What changes") {
        Text(
          "Resolve conflicting reports through Settings → Concurrent edits. Until then the affected period remains unknown."
        )
        Text(
          "Heart-rate zones and RMSSD keep their defined formulas. Placement can affect sensor quality; no unverified correction factor is applied. Overnight placement changes lower readiness confidence conservatively, without resetting your baseline."
        )
        Text(
          "Motion-based step counts and muscular-load models need placement-specific validation. Tempo does not offer those algorithms. Its potential-workout detector uses available heart rate and still requires confirmation at every placement."
        )
        Button("Mark placement unknown") {
          model.mutate {
            try await model.recordPlacement(
              deviceID: device.id, placement: .unknown, effectiveFrom: Date())
          }
        }
      }
    }.navigationTitle("Wearing placement").sheet(isPresented: $editor) {
      NavigationStack { PlacementEditor(device: device) }
    }
  }
}
struct PlacementEditor: View {
  @Environment(AppModel.self) var model
  @Environment(\.dismiss) var dismiss
  let device: RegisteredDevice
  let existing: PlacementRecord?
  @State private var placement: BodyPlacement
  @State private var date: Date
  init(device: RegisteredDevice, existing: PlacementRecord? = nil) {
    self.device = device
    self.existing = existing
    _placement = State(initialValue: existing?.placement ?? .unknown)
    _date = State(initialValue: existing?.effectiveFrom ?? Date())
  }
  var body: some View {
    Form {
      Picker("Placement", selection: $placement) {
        ForEach(BodyPlacement.allCases, id: \.self) { Text($0.title).tag($0) }
      }
      DatePicker("Effective from", selection: $date, in: ...Date())
      Text(
        "Applies from this instant until the next recorded change for this band. Measurements remain immutable; correcting context does not change recorded heart rate."
      )
      Button("Save placement") {
        model.mutate {
          try await model.recordPlacement(
            deviceID: device.id, placement: placement, effectiveFrom: date, existing: existing)
          dismiss()
        }
      }
    }.navigationTitle(existing == nil ? "Record placement" : "Correct placement")
  }
}
