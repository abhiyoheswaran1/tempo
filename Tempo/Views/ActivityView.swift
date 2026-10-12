import Charts
import SwiftUI
import TempoCore

struct ActivityView: View {
  @Environment(AppModel.self) var model
  var title = "Activity"
  @State private var selected: TempoCore.Activity = .padel
  @State private var confirmFinish = false
  @ScaledMetric(relativeTo: .largeTitle) private var timerSize = 48
  private var completed: [Workout] { model.workouts.filter { $0.end != nil } }
  var body: some View {
    List {
      if let workout = model.activeWorkout {
        Section {
          TimelineView(.periodic(from: .now, by: 1)) { context in
            let sample = model.lastSample
            let wear =
              sample.map {
                WearEvidence.current(
                  model.bluetooth.lastSamples[$0.deviceID],
                  connected: model.bluetooth.isConnected($0.deviceID), now: context.date)
              } ?? .unknown
            let reading = WorkoutLiveReading(
              sample: sample,
              connected: sample.map { model.bluetooth.isConnected($0.deviceID) } ?? false,
              wear: wear, now: context.date, maximumHeartRate: model.maxHeartRate,
              allowSynthetic: model.demo)
            VStack(alignment: .leading, spacing: 16) {
              HStack {
                Label(workout.activity.rawValue.capitalized, systemImage: workout.activity.symbol)
                  .font(.headline)
                Spacer()
                Label(
                  workout.pausedAt == nil ? "Recording" : "Paused",
                  systemImage: workout.pausedAt == nil ? "record.circle" : "pause.circle"
                ).font(.caption).foregroundStyle(.secondary)
              }
              Text(
                Duration.seconds(workout.activeDuration(at: context.date)).formatted(
                  .time(pattern: .hourMinuteSecond))
              )
              .font(.system(size: timerSize, weight: .semibold, design: .rounded)).monospacedDigit()
              .accessibilityLabel("Active workout duration")
              .accessibilityValue(
                Duration.seconds(workout.activeDuration(at: context.date)).formatted(
                  .time(pattern: .hourMinuteSecond)))
              HStack(spacing: 12) {
                Button(workout.pausedAt == nil ? "Pause" : "Resume") {
                  model.mutate { try await model.pauseResume() }
                }
                .buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
                Button("Finish") { confirmFinish = true }.buttonStyle(.bordered).controlSize(.large)
                  .tint(.primary)
              }
              Divider()
              ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                  heartRate(reading)
                  Spacer()
                  readingLabel(reading, sample: sample)
                }
                VStack(alignment: .leading, spacing: 6) {
                  heartRate(reading)
                  readingLabel(reading, sample: sample)
                }
              }
              if let zone = reading.zone {
                Text("Zone \(zone) · estimate").font(.caption).foregroundStyle(.secondary)
              }
              if reading.state == .waiting || reading.state == .stale {
                Text("Your timer keeps going. Missing heart-rate periods remain gaps.").font(
                  .caption
                ).foregroundStyle(.secondary)
              }
              let observations = CanonicalTimeline.select(
                model.measurements.filter {
                  $0.kind == .heartRate && $0.timestamp >= workout.start
                    && $0.timestamp <= context.date
                    && ($0.origin == .measured || (model.demo && $0.origin == .synthetic))
                }, sourceSegments: model.sourceSegments)
              let load = CardiovascularLoad.calculate(
                observations, maxHeartRate: model.maxHeartRate, workout: workout)
              if let load, load.coveredSeconds > 0 {
                ViewThatFits(in: .horizontal) {
                  HStack(spacing: 24) {
                    average(load)
                    maximum(load)
                    coverage(load)
                  }
                  VStack(alignment: .leading, spacing: 10) {
                    average(load)
                    maximum(load)
                    coverage(load)
                  }
                }
              } else {
                Text("Session averages need recorded heart rate.").font(.caption).foregroundStyle(
                  .secondary)
              }
            }.padding(.vertical, 8)
          }
        }
        Section("Source & readings") {
          BandStatusControl()
          NavigationLink("Live dashboard") { LiveDashboardView() }
        }
      } else {
        Section {
          VStack(alignment: .leading, spacing: 16) {
            Text("What are you doing?").font(.title2.weight(.semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 125), spacing: 10)], spacing: 10) {
              ForEach(WorkoutPresentation.orderedActivities(model.workouts), id: \.self) {
                activity in
                Button {
                  selected = activity
                } label: {
                  HStack(spacing: 8) {
                    Image(systemName: activity.symbol).accessibilityHidden(true)
                    Text(activity.rawValue.capitalized).font(.subheadline.weight(.medium))
                    Spacer(minLength: 0)
                    if selected == activity {
                      Image(systemName: "checkmark").accessibilityHidden(true)
                    }
                  }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(
                    .horizontal, 10
                  )
                  .background(
                    selected == activity
                      ? Color.teal.opacity(0.12) : Color(uiColor: .tertiarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain).accessibilityLabel(activity.rawValue.capitalized)
                  .accessibilityAddTraits(selected == activity ? [.isSelected] : [])
              }
            }
            Button {
              model.mutate { try await model.startWorkout(selected) }
            } label: {
              Text("Start \(selected.rawValue.capitalized)").frame(
                maxWidth: .infinity, minHeight: 32)
            }.buttonStyle(.borderedProminent).controlSize(.large)
            Text("Record time even without a band. Heart-rate metrics need measurements.").font(
              .caption
            ).foregroundStyle(.secondary)
          }.padding(.vertical, 8)
        }
      }
      if !model.pendingDetectedActivities.isEmpty {
        Section("Suggested sessions") {
          ForEach(model.pendingDetectedActivities) { decision in
            NavigationLink {
              DetectedActivityReviewView(decision: decision)
            } label: {
              VStack(alignment: .leading, spacing: 4) {
                Text("Potential workout").font(.headline)
                Text(
                  "\(decision.candidate.start.formatted(date: .abbreviated, time: .shortened)) · \(durationText(decision.candidate.end.timeIntervalSince(decision.candidate.start)))"
                )
                .font(.caption).foregroundStyle(.secondary)
                Text("Heart-rate estimate · review required").font(.caption).foregroundStyle(
                  .secondary)
              }
            }
          }
        }
      }
      Section("Recent workouts") {
        ForEach(completed) { workout in
          NavigationLink {
            WorkoutDetailView(workout: workout)
          } label: {
            HStack(spacing: 12) {
              Image(systemName: workout.activity.symbol).foregroundStyle(.teal).accessibilityHidden(
                true)
              VStack(alignment: .leading, spacing: 4) {
                Text(workout.activity.rawValue.capitalized).font(.headline)
                Text(workout.start.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                  .foregroundStyle(.secondary)
                if workout.detectionID != nil {
                  Text("Confirmed activity estimate").font(.caption).foregroundStyle(.secondary)
                }
              }
              Spacer()
              Text(durationText(workout.activeDuration(at: workout.end ?? Date()))).font(
                .subheadline
              ).monospacedDigit()
            }
          }
        }.onDelete { indices in
          let rows = completed
          for i in indices {
            model.mutate { try await model.delete(id: rows[i].id, kind: "workout") }
          }
        }
        if completed.isEmpty {
          Text("Your finished sessions will appear here.").font(.subheadline).foregroundStyle(
            .secondary)
        }
      }
      Section {
        NavigationLink {
          ActivityDetectionSettingsView()
        } label: {
          VStack(alignment: .leading, spacing: 4) {
            Text("Automatic detection")
            Text(model.automaticDetectionEnabled ? "Experimental · on" : "Optional · off").font(
              .caption
            ).foregroundStyle(.secondary)
          }
        }
        if model.automaticDetectionEnabled {
          Button("Scan recent measurements") {
            model.mutate { try await model.scanAutomaticActivities() }
          }.disabled(model.activityScanning)
          Text("Suggestions need confirmation. Heart rate does not identify the activity type.")
            .font(.caption).foregroundStyle(.secondary)
        }
      }
    }.navigationTitle(title).onAppear {
      selected = WorkoutPresentation.orderedActivities(model.workouts).first ?? .padel
    }
    .alert(
      "Finish this workout?", isPresented: $confirmFinish
    ) {
      Button("Finish workout", role: .destructive) {
        model.mutate { try await model.finishWorkout() }
      }
      .accessibilityIdentifier("confirm-finish-workout")
      Button("Cancel", role: .cancel) {}
    }
  }
  private func heartRate(_ reading: WorkoutLiveReading) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 4) {
      Text(reading.bpm.map(String.init) ?? "—").font(.title.weight(.semibold)).monospacedDigit()
      if reading.bpm != nil { Text("bpm").font(.subheadline).foregroundStyle(.secondary) }
    }.accessibilityElement(children: .combine)
  }
  private func readingLabel(_ reading: WorkoutLiveReading, sample: TempoCore.Measurement?)
    -> some View
  {
    VStack(alignment: .leading, spacing: 4) {
      Text(
        model.demo && reading.bpm != nil
          ? "Demo reading"
          : reading.state == .live
            ? "Live heart rate" : reading.state == .recent ? "Recent reading" : "No live reading"
      )
      .font(.subheadline).foregroundStyle(.secondary)
      if let sample {
        Text(sample.timestamp, style: .relative).font(.caption).foregroundStyle(.secondary)
      }
    }
  }
  private func average(_ load: LoadResult) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text("Average HR").font(.caption).foregroundStyle(.secondary)
      Text(load.average.map { "\(Int($0)) bpm" } ?? "—").font(.subheadline.weight(.medium))
        .monospacedDigit()
    }
  }
  private func maximum(_ load: LoadResult) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text("Maximum HR").font(.caption).foregroundStyle(.secondary)
      Text(load.maximum.map { "\(Int($0)) bpm" } ?? "—").font(.subheadline.weight(.medium))
        .monospacedDigit()
    }
  }
  private func coverage(_ load: LoadResult) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text("HR coverage").font(.caption).foregroundStyle(.secondary)
      Text(durationText(load.coveredSeconds)).font(.subheadline.weight(.medium)).monospacedDigit()
    }
  }
}
extension TempoCore.Activity {
  fileprivate var symbol: String {
    switch self {
    case .padel: "sportscourt"
    case .cycling: "bicycle"
    case .running: "figure.run"
    case .strength: "dumbbell"
    case .walking: "figure.walk"
    case .other: "figure.mixed.cardio"
    }
  }
}

struct WorkoutDetailView: View {
  @Environment(AppModel.self) var model
  let workout: Workout
  var title: String? = nil
  @State private var note = ""
  @State private var effort = 5
  @State private var effortEnabled = false
  @State private var historical: [TempoCore.Measurement] = []
  var observations: [TempoCore.Measurement] {
    (workout.end == nil ? model.canonical : historical).filter {
      $0.kind == .heartRate && $0.timestamp >= workout.start
        && $0.timestamp <= (workout.end ?? Date())
    }
  }
  var body: some View {
    let chartPoints = ChartProjection.points(observations)
    let load = CardiovascularLoad.calculate(
      observations, maxHeartRate: model.maxHeartRate, workout: workout)
    let activeDuration = workout.activeDuration(at: workout.end ?? Date())
    return List {
      Section("Session") {
        Label(workout.activity.rawValue.capitalized, systemImage: workout.activity.symbol)
          .font(.headline)
        MetricRow(label: "Active duration", value: durationText(activeDuration))
        MetricRow(
          label: "Heart rate coverage",
          value: "\(Int(min(1, (load?.coveredSeconds ?? 0) / max(1, activeDuration)) * 100))%",
          detail: "Of active workout time · pauses excluded")
        if observations.isEmpty {
          Text("No measured heart rate during this workout. Heart rate averages, zones and cardiovascular load are unavailable.")
            .font(.subheadline).foregroundStyle(.secondary)
        }
      }
      Section("Your experience") {
        TextField("Notes", text: $note, axis: .vertical)
          .accessibilityLabel("Workout notes")
          .accessibilityIdentifier("workout-notes-field")
        Toggle("Record perceived exertion", isOn: $effortEnabled)
        if effortEnabled { Stepper("Perceived exertion: \(effort)/10", value: $effort, in: 1...10) }
        Button("Save notes") {
          model.mutate {
            var w = model.workouts.first(where: { $0.id == workout.id }) ?? workout
            w.note = note
            w.perceivedExertion = effortEnabled ? effort : nil
            try await model.save(w, kind: "workout")
          }
        }
        .accessibilityIdentifier("workout-save-notes")
        if workout.activity == .strength {
          Text("Heart rate captures cardiovascular demand, not muscular load.").font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      Section("Recorded evidence") {
        DisclosureGroup("Heart rate measurements") {
          if observations.isEmpty {
            Text("No measured heart rate during this workout.").foregroundStyle(.secondary)
          } else {
            MetricRow(
              label: "Average heart rate",
              value: load?.average.map { String(format: "%.0f bpm", $0) } ?? "Unavailable")
            MetricRow(
              label: "Maximum heart rate",
              value: load?.maximum.map { String(format: "%.0f bpm", $0) } ?? "Unavailable")
            Chart(chartPoints) { point in
              let m = point.sample
              LineMark(
                x: .value("Time", m.timestamp), y: .value("bpm", m.value),
                series: .value("Coverage segment", point.segment)
              ).foregroundStyle(.teal)
            }.frame(height: 180).accessibilityLabel(
              "Workout heart rate chart; gaps are not connected")
          }
        }
        DisclosureGroup("Time in zones") {
          if let load, load.coveredSeconds > 0 {
            ForEach(0..<5, id: \.self) { i in
              MetricRow(label: "Zone \(i+1)", value: durationText(load.zones[i]))
            }
          } else {
            Text("Zone totals need recorded heart rate.").foregroundStyle(.secondary)
          }
        }
        DisclosureGroup("Cardiovascular load") {
          MetricRow(
            label: "Estimated load",
            value: (load?.coveredSeconds ?? 0) > 60
              ? String(format: "%.0f", load?.points ?? 0) : "Unavailable",
            detail: "Estimate · Edwards zones · maximum HR \(Int(model.maxHeartRate))")
          if (load?.coveredSeconds ?? 0) <= 60 {
            Text("Load needs more than one minute of covered heart rate.")
              .font(.subheadline).foregroundStyle(.secondary)
          }
          if let version = workout.algorithmVersion {
            MetricRow(label: "Provenance", value: "Confirmed estimate", detail: version)
          }
        }
        DisclosureGroup("Sources and placement") {
          MetricRow(
            label: "Reported placement",
            value: PlacementTimeline.description(samples: observations, records: model.placements))
          if workout.sources.isEmpty {
            Text("No source segments recorded.").foregroundStyle(.secondary)
          }
          ForEach(workout.sources) { s in
            Text(
              "\(model.devices.first{$0.id==s.deviceID}?.name ?? "Registered band") · \(s.start.formatted(date:.omitted,time:.shortened))\n\(s.reason)"
            ).font(.subheadline)
          }
        }
      }
    }.navigationTitle(title ?? workout.activity.rawValue.capitalized).onAppear {
      note = workout.note
      effort = workout.perceivedExertion ?? 5
      effortEnabled = workout.perceivedExertion != nil
    }.task(id: workout.id) {
      do {
        let samples =
          try await model.store?.measurements(
            from: workout.start, to: (workout.end ?? Date()).addingTimeInterval(1),
            kinds: [.heartRate]) ?? []
        historical = CanonicalTimeline.select(samples, sourceSegments: model.sourceSegments)
      } catch { model.errorMessage = "Workout measurements could not load" }
    }
  }
}
