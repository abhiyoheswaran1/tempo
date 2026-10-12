import SwiftUI
import TempoCore

struct BandStatusControl: View {
  @Environment(AppModel.self) var model
  @State private var details = false
  @Environment(\.dynamicTypeSize) private var textSize
  var body: some View {
    TimelineView(.periodic(from: .now, by: 15)) { context in
      let fresh = SampleFreshness(timestamp: model.lastSample?.timestamp, now: context.date)
      Button {
        details = true
      } label: {
        HStack(spacing: 10) {
          Image(systemName: fresh == .fresh ? "waveform.path.ecg" : "sensor.tag.radiowaves.forward")
            .foregroundStyle(.teal).accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 3) {
            Text(model.activeDevice?.name ?? "Your bands").font(.subheadline.weight(.semibold))
            Text(status(fresh, now: context.date)).font(.caption).foregroundStyle(.secondary)
          }
          Spacer()
          Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }.padding(.vertical, 4).contentShape(Rectangle())
      }.buttonStyle(.plain).accessibilityIdentifier("band-status-control")
    }.sheet(isPresented: $details) {
      NavigationStack { BandStatusSheet() }.presentationDetents(
        textSize.isAccessibilitySize ? [.large] : [.medium, .large])
    }
  }
  func status(_ freshness: SampleFreshness, now: Date) -> String {
    guard let sample = model.lastSample else { return "Connect a band to begin" }
    let placement = PlacementTimeline.resolve(
      deviceID: sample.deviceID, at: now, records: model.placements)
    let location = placement == .unknown ? "Placement unrecorded" : placement.title
    if model.demo { return "Synthetic sample · \(location)" }
    if freshness == .fresh { return "Updated recently · \(location)" }
    return "Data stale · last \(sample.timestamp.formatted(date: .abbreviated, time: .shortened))"
  }
}
struct BandStatusSheet: View {
  @Environment(AppModel.self) var model
  @Environment(\.dismiss) var dismiss
  var body: some View {
    List {
      Section("Collection") {
        Text(model.demo ? "Synthetic demonstration" : model.bluetooth.status)
        if let sample = model.lastSample {
          LabeledContent("Last heart rate", value: "\(Int(sample.value)) bpm")
          LabeledContent("Received", value: sample.timestamp.formatted())
          Text(
            "\(SampleFreshness(timestamp: sample.timestamp, now: Date()) == .fresh ? "Recent measurement" : "Stale measurement") · \(model.devices.first { $0.id == sample.deviceID }?.name ?? "Recorded source")"
          ).font(.caption).foregroundStyle(.secondary)
        }
        NavigationLink("Collection health") { CollectionHealthView() }
      }
      Section("Bands and placement") {
        ForEach(model.devices) { device in
          NavigationLink {
            PlacementView(device: device)
          } label: {
            VStack(alignment: .leading) {
              Text(device.name)
              Text(
                PlacementTimeline.resolve(
                  deviceID: device.id, at: Date(), records: model.placements
                ).title
              ).font(.caption).foregroundStyle(.secondary)
            }
          }
        }
        NavigationLink("Manage and reconnect bands") { DevicesView() }
      }
    }.navigationTitle("Band status").toolbar {
      ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
    }
  }
}
struct ActiveWorkoutAccessory: View {
  @Environment(AppModel.self) var model
  var open: () -> Void
  var body: some View {
    if let workout = model.activeWorkout {
      TimelineView(.periodic(from: .now, by: 1)) { context in
        HStack(spacing: 12) {
          Button(action: open) {
            HStack(spacing: 8) {
              Image(systemName: "figure.run")
              VStack(alignment: .leading) {
                Text(workout.activity.rawValue.capitalized).font(.subheadline.weight(.semibold))
                Text(
                  "\(workout.pausedAt == nil ? "Recording" : "Paused") · \(durationText(workout.activeDuration(at: context.date)))"
                ).font(.caption).monospacedDigit()
              }
            }.frame(maxWidth: .infinity, alignment: .leading)
          }.buttonStyle(.plain).accessibilityLabel("Open active workout")
          Button {
            model.mutate { try await model.pauseResume() }
          } label: {
            Image(systemName: workout.pausedAt == nil ? "pause.fill" : "play.fill").frame(
              minWidth: 44, minHeight: 44)
          }
          .accessibilityLabel(workout.pausedAt == nil ? "Pause workout" : "Resume workout")
        }.padding(.horizontal, 16)
      }
    }
  }
}
struct ActiveWorkoutSheet: View {
  @Environment(AppModel.self) var model
  @Environment(\.dismiss) var dismiss
  var body: some View {
    Group {
      if let finished = model.finishedWorkout {
        WorkoutDetailView(workout: finished, title: "Workout summary")
      } else {
        ActivityView(title: "Active workout")
      }
    }.navigationTitle(model.finishedWorkout == nil ? "Active workout" : "Workout summary")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") {
            model.finishedWorkout = nil
            dismiss()
          }
        }
      }
  }
}
