import Charts
import SwiftUI
import TempoCore

struct BandStatusControl: View {
  @Environment(AppModel.self) var model
  @State private var details = false
  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      let fresh = SampleFreshness(timestamp: model.lastSample?.timestamp, now: context.date)
      Button {
        details = true
      } label: {
        HStack(spacing: 10) {
          Image(systemName: fresh == .fresh ? "waveform.path.ecg" : "sensor.tag.radiowaves.forward")
            .foregroundStyle(.teal).accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 3) {
            Text(model.collectionDevice?.name ?? "Your bands").font(.subheadline.weight(.semibold))
            Text(status(fresh, now: context.date)).font(.caption).foregroundStyle(.secondary)
          }
          Spacer()
          Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }.padding(.vertical, 4).contentShape(Rectangle())
      }.buttonStyle(.plain).accessibilityIdentifier("band-status-control")
    }.sheet(isPresented: $details) {
      NavigationStack { BandStatusSheet() }.presentationDetents(
        [.large])
    }
  }
  func status(_ freshness: SampleFreshness, now: Date) -> String {
    if model.demo { return "Synthetic sample · no band connection" }
    let device = model.collectionDevice
    let reading = model.collectionReading(at: now)
    let connection =
      device.map { model.bluetooth.bandStatus($0.id, now: now) } ?? "No band selected"
    guard let sample = reading.sample else { return "\(connection) · no heart rate yet" }
    switch reading.state {
    case .live, .recent:
      let age = max(0, Int(now.timeIntervalSince(sample.timestamp)))
      let receipt = age < 60 ? "\(age)s ago" : "\(age / 60) min ago"
      return "\(reading.state == .live ? "Live" : connection) · HR received \(receipt)"
    case .stale: return "\(connection) · reading stale"
    case .waiting: return "\(connection) · no heart rate yet"
    }
  }

}
struct BandStatusSheet: View {
  @Environment(AppModel.self) var model
  @Environment(\.dismiss) var dismiss
  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      List {
        Section("Collection") {
          Text(
            model.demo
              ? "Synthetic demonstration" : model.collectionReading(at: context.date).statusTitle
          ).font(.subheadline)
          if let sample = model.collectionReading(at: context.date).sample {
            LabeledContent("Last heart rate", value: "\(Int(sample.value)) bpm")
            LabeledContent(
              "HR received", value: sample.timestamp.formatted(date: .abbreviated, time: .standard))
          }
          NavigationLink("Live dashboard") { LiveDashboardView() }
        }
        Section("Your bands") {
          ForEach(model.devices) { device in
            VStack(alignment: .leading, spacing: 8) {
              HStack {
                Text(device.name).font(.headline)
                Spacer()
                if model.selector.activeID == device.id {
                  Text("Selected source").font(.caption).foregroundStyle(.secondary)
                }
              }
              LabeledContent(
                "Connection",
                value: model.demo ? "Demo · not connected" : model.bluetooth.bandStatus(device.id))
              LabeledContent(
                "Wear evidence",
                value: model.demo
                  ? "Not available in demo"
                  : model.bluetooth.wearStatus(device.id, now: context.date))
              let placement = PlacementTimeline.resolve(
                deviceID: device.id, at: context.date, records: model.placements)
              NavigationLink("Placement · \(placement.title)") { PlacementView(device: device) }
              HStack {
                if model.bluetooth.state(device.id) == .disconnected {
                  Button("Reconnect") { model.bluetooth.connect(deviceID: device.id) }
                    .disabled(model.demo).accessibilityLabel("Reconnect \(device.name)")
                } else {
                  Button("Disconnect") {
                    model.mutate { try await model.disconnectBand(device.id) }
                  }
                  .disabled(model.demo || model.bluetooth.state(device.id) == .disconnecting)
                  .accessibilityLabel("Disconnect \(device.name)")
                }
                Spacer()
                NavigationLink("Details") { DeviceDetailView(device: device) }
                  .accessibilityLabel("Details for \(device.name)")
              }.buttonStyle(.bordered)
            }.font(.subheadline).padding(.vertical, 4)
          }
          Text(
            "Wear not reported means the contact flag is unavailable, not off-body. Heart rate and wear evidence are separate."
          )
          .font(.caption).foregroundStyle(.secondary)
          NavigationLink("Manage and reconnect bands") { DevicesView() }
        }
        Section("History retrieval") {
          LabeledContent("Band history retrieval", value: "Unavailable in this build")
          Text("Live receipt is separate from retrieving stored band history.")
            .font(.caption).foregroundStyle(.secondary)
        }
        Section("iCloud") { SyncStatusRow() }
        Section { NavigationLink("Collection health") { CollectionHealthView() } }
      }.navigationTitle("Band status").toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
      }
    }
  }
}

extension AppModel {
  var collectionDevice: RegisteredDevice? {
    activeDevice ?? lastSample.flatMap { sample in devices.first { $0.id == sample.deviceID } }
      ?? devices.first { bluetooth.isConnected($0.id) }
  }
  func collectionReading(at now: Date) -> CollectionPresentation {
    let sample = lastSample.flatMap { sample in
      devices.contains { $0.id == sample.deviceID } ? sample : nil
    }
    let id = collectionDevice?.id ?? sample?.deviceID
    let connected = id.map { bluetooth.isConnected($0) } ?? false
    let wear =
      id.map { WearEvidence.current(bluetooth.lastSamples[$0], connected: connected, now: now) }
      ?? .unknown
    return CollectionPresentation(
      sample: sample, connected: connected, wear: wear, now: now, allowSynthetic: demo,
      selectedDeviceID: id)
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
  @ScaledMetric(relativeTo: .largeTitle) private var readingSize = 60
  @State private var confirmFinish = false
  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      let reading = model.collectionReading(at: context.date)
      let sample = reading.sample
      let sourceID = model.collectionDevice?.id
      let recent = CanonicalTimeline.select(
        model.measurements.filter {
          $0.kind == .heartRate && $0.valid && (25...240).contains($0.value)
            && ($0.origin == .measured || (model.demo && $0.origin == .synthetic))
            && $0.timestamp >= context.date.addingTimeInterval(-300) && $0.timestamp <= context.date
            && sourceID != nil && $0.deviceID == sourceID
        }, sourceSegments: model.sourceSegments)
      let load = CardiovascularLoad.calculate(recent, maxHeartRate: model.maxHeartRate)
      List {
        Section {
          VStack(alignment: .leading, spacing: 10) {
            Text(model.demo ? "Synthetic demonstration" : reading.statusTitle)
              .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
              Text(reading.displayedBPM.map { $0.formatted() } ?? "—")
                .font(.system(size: readingSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .accessibilityIdentifier("live-primary-reading")
              Text("bpm").foregroundStyle(.secondary)
            }.accessibilityElement(children: .combine)
            if let sample {
              if reading.state == .stale {
                Text("Last recorded: \(Int(sample.value)) bpm · stale")
                  .font(.subheadline).foregroundStyle(.secondary)
              }
              Text("Received \(sample.timestamp.formatted(date: .omitted, time: .standard))")
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("live-received-time")
              if reading.state == .live && !model.demo {
                let live = WorkoutLiveReading(
                  sample: sample, connected: true, wear: .unknown,
                  now: context.date, maximumHeartRate: model.maxHeartRate)
                Text(live.zone.map { "Zone \($0) · estimate" } ?? "Below configured training zones")
                  .font(.subheadline).foregroundStyle(.secondary)
              }
            } else {
              Text("Waiting for a heart-rate measurement").font(.subheadline).foregroundStyle(
                .secondary)
            }
          }.padding(.vertical, 8)
          if reading.state != .live && !model.demo {
            Text(
              "A connection alone does not guarantee readings. Check the band’s heart-rate broadcast setting where supported."
            )
            .font(.caption).foregroundStyle(.secondary)
          }
        }
        Section("Last five minutes") {
          if !recent.isEmpty {
            liveChart(recent)
          } else {
            ContentUnavailableView(
              "No recent readings", systemImage: "waveform.path.ecg",
              description: Text("Your history stays available. Missing periods remain gaps."))
          }
          ViewThatFits(in: .horizontal) {
            HStack {
              liveStatistic("Covered", value: durationText(load?.coveredSeconds ?? 0))
              Spacer()
              liveStatistic("Average", value: load?.average.map { "\(Int($0)) bpm" } ?? "—")
              Spacer()
              liveStatistic("Range", value: observedRange(recent))
            }
            VStack(alignment: .leading, spacing: 12) {
              liveStatistic("Covered", value: durationText(load?.coveredSeconds ?? 0))
              liveStatistic("Average", value: load?.average.map { "\(Int($0)) bpm" } ?? "—")
              liveStatistic("Range", value: observedRange(recent))
            }
          }
          Text("Average uses covered time. Gaps are excluded.").font(.caption).foregroundStyle(
            .secondary)
        }
        Section {
          if let device = model.collectionDevice {
            LabeledContent("Source", value: device.name)
            LabeledContent(
              "Connection",
              value: model.demo ? "Demo · not connected" : model.bluetooth.bandStatus(device.id))
          }
          DisclosureGroup("Source and measurement evidence") {
            if let sample {
              LabeledContent("Origin", value: model.demo ? "Synthetic" : "Direct measurement")
              Text(
                sample.timestamp, format: .dateTime.year().month().day().hour().minute().second())
              LabeledContent(
                "Wear evidence",
                value: model.demo
                  ? "Unavailable in demo" : model.bluetooth.wearStatus(sample.deviceID))
              Text(
                "Wear not reported means no usable contact flag. A plausible pulse is separate from confirmed wear."
              )
              .font(.caption).foregroundStyle(.secondary)
              if !sample.rrMilliseconds.isEmpty {
                LabeledContent(
                  "Latest band-supplied R–R",
                  value:
                    "\(sample.rrMilliseconds.prefix(8).map { Int($0).formatted() }.joined(separator: ", ")) ms"
                )
                Text("Intervals are not an overnight HRV result.").font(.caption).foregroundStyle(
                  .secondary)
              }
            }
            Text(
              "Battery, oxygen and temperature remain unavailable until a supported data path is verified."
            )
            .font(.caption).foregroundStyle(.secondary)
          }
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
            Button("Finish workout") { confirmFinish = true }
          }
        }
        Section("iCloud") { SyncStatusRow() }
      }.navigationTitle("Live dashboard")
    }.alert("Finish this workout?", isPresented: $confirmFinish) {
      Button("Finish workout", role: .destructive) {
        model.mutate { try await model.finishWorkout() }
      }
      Button("Cancel", role: .cancel) {}
    }
  }
  private func liveChart(_ samples: [TempoCore.Measurement]) -> some View {
    let points = LiveChartSeries.points(samples)
    let low = max(25, (samples.map(\.value).min() ?? 60) - 8)
    let high = min(240, (samples.map(\.value).max() ?? 100) + 8)
    return Chart(points) { point in
      LineMark(
        x: .value("Time", point.sample.timestamp), y: .value("Heart rate", point.sample.value),
        series: .value("Coverage", point.segment)
      ).foregroundStyle(.teal)
      PointMark(
        x: .value("Time", point.sample.timestamp), y: .value("Heart rate", point.sample.value)
      )
      .symbolSize(8).foregroundStyle(.teal)
    }.chartLegend(.hidden).chartYScale(domain: low...high).chartYAxisLabel("bpm")
      .frame(height: 180).accessibilityLabel(
        "Heart rate over the last five minutes; gaps represent missing readings")
  }
  private func liveStatistic(_ title: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
      Text(title).font(.caption).foregroundStyle(.secondary)
    }.accessibilityElement(children: .combine)
  }
  private func observedRange(_ samples: [TempoCore.Measurement]) -> String {
    guard let low = samples.map(\.value).min(), let high = samples.map(\.value).max() else {
      return "—"
    }
    return "\(Int(low))–\(Int(high)) bpm"
  }

}

struct TodayCollectionPanel: View {
  @Environment(AppModel.self) var model
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 12) {
        NavigationLink {
          LiveDashboardView()
        } label: {
          HStack(spacing: 10) {
            Image(systemName: "waveform.path.ecg").font(.title3).foregroundStyle(.teal)
              .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
              Text("Live dashboard").font(.headline)
              Text("Heart rate & recent coverage").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
              .accessibilityHidden(true)
          }.contentShape(Rectangle()).frame(minHeight: 44)
        }.buttonStyle(.plain).accessibilityLabel("Live dashboard")
        Button {
          Task { await model.refreshToday() }
        } label: {
          Group {
            if model.refreshingToday {
              ProgressView()
            } else {
              Image(systemName: "arrow.clockwise")
            }
          }.frame(minWidth: 44, minHeight: 44)
        }.buttonStyle(.bordered).buttonBorderShape(.circle)
          .accessibilityLabel("Refresh collection and iCloud")
          .disabled(model.refreshingToday)
      }
      Divider()
      BandStatusControl()
      TimelineView(.periodic(from: .now, by: 15)) { context in
        VStack(alignment: .leading, spacing: 3) {
          if let sample = model.lastSample,
            model.collectionReading(at: context.date).state == .stale
          {
            HStack(spacing: 4) {
              Text("Last reading")
              Text(sample.timestamp, style: .relative)
            }
          }
          if model.demo {
            Text("Demo · real integrations off")
          } else if !model.syncEnabled {
            Text("On this iPhone · iCloud off")
          } else if let date = model.lastCloudSync {
            HStack(spacing: 4) {
              Text("Last iCloud sync")
              Text(date, style: .relative)
              if model.pendingCloudChanges > 0 { Text("· \(model.pendingCloudChanges) pending") }
            }
          } else {
            Text("iCloud · no successful sync yet")
          }
          if let result = model.refreshOutcome {
            Text(result.message).accessibilityIdentifier("today-refresh-result")
          }
        }.font(.caption).foregroundStyle(.secondary)
      }
    }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
      .background(
        Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20)
      )

  }
}
