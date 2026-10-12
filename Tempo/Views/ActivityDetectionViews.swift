import SwiftUI
import TempoCore

struct ActivityDetectionSettingsView: View {
  @Environment(AppModel.self) var model
  var body: some View {
    Form {
      Section("Experimental · heart-rate-only") {
        Toggle(
          "Suggest potential workouts",
          isOn: Binding(
            get: { model.automaticDetectionEnabled },
            set: { enabled in model.mutate { try await model.setAutomaticDetectionEnabled(enabled) }
            }))
        Text(
          "Tempo looks for sustained heart-rate elevation in collected measurements. It suggests a possible session; you choose the activity and confirm the timing."
        ).font(.subheadline)
      }
      Section("Detection rules") {
        LabeledContent("Minimum activity", value: "10 minutes")
        LabeledContent("Start threshold", value: "65% of maximum HR")
        LabeledContent("Sustain threshold", value: "55% of maximum HR")
        LabeledContent("Required coverage", value: "80% per minute")
        LabeledContent("Recovery period", value: "3 minutes")
        Text(
          "Configured maximum: \(Int(model.maxHeartRate)) bpm. Edit it in Analytics settings; it is a personal assumption unless measured."
        ).font(.caption).foregroundStyle(.secondary)
      }
      Section("Coverage and limits") {
        Text(
          "Heart rate alone does not identify padel, running or strength training. Stress or other causes of elevated heart rate can produce false suggestions. Gentle activity and strength sessions may be missed."
        )
        Text(
          "Only available measurements are analyzed. Missing data splits sessions; Tempo does not fill Bluetooth gaps or guarantee background execution. Confirmation is required before a candidate counts as a workout."
        )
        if model.automaticDetectionEnabled {
          Button(model.demo ? "Scan synthetic demonstration" : "Scan recent measurements") {
            model.mutate { try await model.scanAutomaticActivities() }
          }.disabled(model.activityScanning)
        }
        if let last = model.activityLastScan {
          LabeledContent("Last scan", value: last.formatted())
        }
      }
    }.navigationTitle("Activity detection")
  }
}
struct DetectedActivityReviewView: View {
  @Environment(AppModel.self) var model
  @Environment(\.dismiss) var dismiss
  var decision: DetectedActivityDecision
  @State private var activity: TempoCore.Activity = .other
  @State private var start: Date
  @State private var end: Date
  init(decision: DetectedActivityDecision) {
    self.decision = decision
    _start = State(initialValue: decision.candidate.start)
    _end = State(initialValue: decision.candidate.end)
  }
  var body: some View {
    Form {
      Section("A possible session") {
        Text("This is a heart-rate-only estimate, not an identified sport or a confirmed workout.")
        if decision.candidate.origin == .synthetic {
          Text("Synthetic demonstration · not real activity").font(.caption).foregroundStyle(
            .secondary)
        }
        Picker("Activity", selection: $activity) {
          ForEach(TempoCore.Activity.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
        }
        DatePicker("Start", selection: $start)
        DatePicker("Finish", selection: $end)
      }
      Section("Evidence") {
        LabeledContent("Measured coverage", value: "\(Int(decision.candidate.coverage*100))%")
        LabeledContent("Source bands", value: String(decision.candidate.sourceIDs.count))
        LabeledContent(
          "Activation HR", value: "\(Int(decision.candidate.activationBPM.rounded())) bpm")
        Text(decision.candidate.finishReason)
        Text(
          decision.candidate.confirmedWear
            ? "Device contact flags were present."
            : "Wear status was not established for all measurements."
        ).font(.caption).foregroundStyle(.secondary)
        Text(decision.candidate.algorithmVersion).font(.caption).foregroundStyle(.secondary)
      }
      Section {
        Button("Confirm workout") {
          model.mutate {
            try await model.confirmDetectedActivity(
              decision, activity: activity, start: start, end: end)
            dismiss()
          }
        }.disabled(end <= start || end > Date() || end.timeIntervalSince(start) > 24 * 3600)
        Button("Dismiss suggestion", role: .destructive) {
          model.mutate {
            try await model.dismissDetectedActivity(decision)
            dismiss()
          }
        }
        Text(
          "Dismissals and confirmations are retained across scans, restore and synchronization. Unconfirmed suggestions do not contribute workout counts or Health exports."
        ).font(.caption).foregroundStyle(.secondary)
      }
    }.navigationTitle("Review activity")
  }
}
