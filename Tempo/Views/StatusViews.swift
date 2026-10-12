import Charts
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
    if model.bluetooth.isConnected(sample.deviceID), freshness == .fresh {
      return "Connected · \(model.bluetooth.wearStatus(sample.deviceID)) · \(location)"
    }
    return
      "\(model.bluetooth.isConnected(sample.deviceID) ? "Data stale" : "Disconnected") · last \(sample.timestamp.formatted(date: .abbreviated, time: .shortened))"
  }
}
struct BandStatusSheet: View {
  @Environment(AppModel.self) var model
  @Environment(\.dismiss) var dismiss
  var body: some View {
    List {
      Section("Collection") {
        NavigationLink("Live dashboard") { LiveDashboardView() }
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
      Section("History continuity") { SyncStatusRow() }
      Section("Bands and placement") {
        ForEach(model.devices) { device in
          NavigationLink {
            PlacementView(device: device)
          } label: {
            VStack(alignment: .leading) {
              Text(device.name)
              Text(
                "\(model.bluetooth.bandStatus(device.id)) · \(model.bluetooth.wearStatus(device.id))\(model.selector.activeID == device.id ? " · Selected source" : "")"
              ).font(.caption).foregroundStyle(.secondary)
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

struct SyncStatusRow: View {
  @Environment(AppModel.self) var model
  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      if model.demo {
        Text("Demo · iCloud disabled")
      } else if !model.syncEnabled {
        Text("Stored on this iPhone")
        Text("iCloud sync is off").font(.caption).foregroundStyle(.secondary)
      } else {
        if let date = model.lastCloudSync {
          HStack {
            Text("Last iCloud sync")
            Spacer()
            Text(date, style: .relative)
          }
        } else {
          Text("iCloud · no successful sync yet")
        }
        Text(
          model.pendingCloudChanges == 0
            ? "No pending uploads" : "\(model.pendingCloudChanges) pending uploads"
        )
        .font(.caption).foregroundStyle(.secondary)
        if let error = model.cloud?.errorMessage {
          Text(error).font(.caption).foregroundStyle(.secondary)
        }
      }
    }.font(.subheadline).accessibilityIdentifier("sync-status")
  }
}

struct LiveDashboardView: View {
  @Environment(AppModel.self) var model
  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      let sample =
        model.activeDevice.flatMap { model.bluetooth.lastSamples[$0.id] }.flatMap {
          $0.valid ? $0 : nil
        } ?? model.lastSample
      let state = LiveReadingState(
        timestamp: sample?.timestamp,
        connected: sample.map {
          model.bluetooth.isConnected($0.deviceID)
            && WearEvidence.current(
              model.bluetooth.lastSamples[$0.deviceID], connected: true, now: context.date)
              != .offBody
        } ?? false,
        now: context.date)
      let recent = CanonicalTimeline.select(
        model.measurements.filter {
          $0.kind == .heartRate && $0.valid && $0.timestamp >= context.date.addingTimeInterval(-300)
            && $0.timestamp <= context.date && (sample == nil || $0.deviceID == sample?.deviceID)
        }, sourceSegments: model.sourceSegments)
      let load = CardiovascularLoad.calculate(recent, maxHeartRate: model.maxHeartRate)
      List {
        Section {
          VStack(alignment: .leading, spacing: 8) {
            Text(model.demo ? "Synthetic demonstration" : label(state)).font(.subheadline)
              .foregroundStyle(.secondary)
            if let sample {
              HStack(alignment: .firstTextBaseline) {
                Text(Int(sample.value).formatted()).font(
                  .system(.largeTitle, design: .rounded).weight(.semibold)
                ).monospacedDigit()
                Text("bpm").foregroundStyle(.secondary)
              }.accessibilityElement(children: .combine)
              Text(sample.timestamp, format: .dateTime.hour().minute().second()).font(.caption)
                .foregroundStyle(.secondary)
              if state == .live && !model.demo {
                Text(
                  sample.value / model.maxHeartRate < 0.5
                    ? "Below training zones"
                    : "Zone \(max(1, min(5, Int(floor((sample.value / model.maxHeartRate - 0.5) * 10)) + 1))) · estimate"
                )
              }
            } else {
              Text("Waiting for a heart-rate measurement").font(.headline)
            }
          }.padding(.vertical, 8)
          if state != .live && !model.demo {
            Text(
              "A connection alone does not guarantee measurements. Enable heart-rate broadcast on the band where supported."
            ).font(.caption).foregroundStyle(.secondary)
          }
        }
        Section("Last five minutes") {
          if recent.count >= 2 {
            Chart {
              ForEach(Array(recent.enumerated()), id: \.element.id) { index, point in
                // A separate series after each gap avoids drawing through missing observations.
                let segment = recent.prefix(index + 1).enumerated().filter { i, p in
                  i > 0 && p.timestamp.timeIntervalSince(recent[i - 1].timestamp) > 10
                }.count
                LineMark(
                  x: .value("Time", point.timestamp), y: .value("Heart rate", point.value),
                  series: .value("Coverage", segment)
                ).foregroundStyle(.teal)
              }
            }.chartLegend(.hidden).chartYScale(domain: 25...240).frame(height: 180)
              .accessibilityLabel(
                "Heart rate over the last five minutes; gaps represent missing readings")
          } else {
            Text("Recent coverage is still building.").foregroundStyle(.secondary)
          }
          LabeledContent("Covered time", value: durationText(load?.coveredSeconds ?? 0))
          if let average = load?.average {
            LabeledContent("Covered-time average", value: "\(Int(average)) bpm")
          }
          if let minimum = recent.map(\.value).min(), let maximum = recent.map(\.value).max() {
            LabeledContent("Observed range", value: "\(Int(minimum))–\(Int(maximum)) bpm")
          }
          Text(
            "Direct heart rate; zones depend on your configured maximum heart rate. Missing periods are excluded."
          ).font(.caption).foregroundStyle(.secondary)
        }
        Section("Source and collection") {
          if let sample {
            Text(model.devices.first { $0.id == sample.deviceID }?.name ?? "Recorded source")
            Text(
              model.demo
                ? "Synthetic data · no band connection"
                : model.bluetooth.bandStatus(sample.deviceID))
            Text(
              model.demo
                ? "Wear status unavailable in demo" : model.bluetooth.wearStatus(sample.deviceID))
            if !sample.rrMilliseconds.isEmpty {
              LabeledContent(
                "Latest band-supplied R–R",
                value:
                  "\(sample.rrMilliseconds.map { Int($0).formatted() }.joined(separator: ", ")) ms")
              Text("Intervals are not an overnight HRV result.").font(.caption).foregroundStyle(
                .secondary)
            }
          }
          Text(
            "Battery, oxygen and temperature remain unavailable until a supported data path is verified."
          ).font(.caption).foregroundStyle(.secondary)
          NavigationLink("Manage bands") { DevicesView() }
          NavigationLink("Collection health") { CollectionHealthView() }
        }
        if let workout = model.activeWorkout {
          Section("Active workout") {
            LabeledContent(
              workout.activity.rawValue.capitalized,
              value: durationText(workout.activeDuration(at: context.date)))
            Button(workout.pausedAt == nil ? "Pause workout" : "Resume workout") {
              model.mutate { try await model.pauseResume() }
            }
            Button("Finish workout") { model.mutate { try await model.finishWorkout() } }
          }
        }
        Section("History continuity") { SyncStatusRow() }
      }.navigationTitle("Live dashboard")
    }
  }
  private func label(_ state: LiveReadingState) -> String {
    switch state {
    case .live: "Receiving live heart rate"
    case .recent: "Recent reading · not confirmed live"
    case .stale: "Stale reading"
    case .waiting: "No reading yet"
    }
  }
}
