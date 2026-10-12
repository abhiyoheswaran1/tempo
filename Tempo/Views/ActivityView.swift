import Charts
import SwiftUI
import TempoCore

struct ActivityView: View {
  @Environment(AppModel.self) var model
  @State private var selected: TempoCore.Activity = .padel
  var body: some View {
    List {
      if let workout = model.activeWorkout {
        Section("In progress") {
          TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 12) {
              Text(workout.activity.rawValue.capitalized).font(.title2.weight(.semibold))
              Text(durationText(workout.activeDuration(at: context.date))).font(.largeTitle)
                .monospacedDigit()
              Text(workout.pausedAt == nil ? "Recording elapsed time" : "Paused").foregroundStyle(
                .secondary)
              if let sample = model.lastSample,
                context.date.timeIntervalSince(sample.timestamp) < 90
              {
                Text("\(Int(sample.value)) bpm").font(.title)
                Text("Source: \(model.activeDevice?.name ?? "Uncertain")").font(.caption)
              } else {
                Text("Heart rate unavailable · gaps remain visible").foregroundStyle(.secondary)
              }
            }
          }
          HStack {
            Button(workout.pausedAt == nil ? "Pause" : "Resume") {
              model.mutate { try await model.pauseResume() }
            }.buttonStyle(.bordered)
            Spacer()
            Button("Finish") { model.mutate { try await model.finishWorkout() } }.buttonStyle(
              .borderedProminent)
          }
        }
      } else {
        Section("Start a workout") {
          Picker("Activity", selection: $selected) {
            ForEach(TempoCore.Activity.allCases, id: \.self) {
              Text($0.rawValue.capitalized).tag($0)
            }
          }
          Button("Start \(selected.rawValue.capitalized)") {
            model.mutate { try await model.startWorkout(selected) }
          }.buttonStyle(.borderedProminent)
        }
      }
      Section("History") {
        ForEach(model.workouts.filter { $0.end != nil }) { w in
          NavigationLink {
            WorkoutDetailView(workout: w)
          } label: {
            VStack(alignment: .leading) {
              Text(w.activity.rawValue.capitalized).font(.headline)
              Text(
                "\(w.start.formatted(date:.abbreviated,time:.shortened)) · \(durationText(w.activeDuration(at:w.end ?? Date())))"
              ).font(.caption).foregroundStyle(.secondary)
            }
          }
        }.onDelete { indices in
          let rows = model.workouts.filter { $0.end != nil }
          for i in indices {
            model.mutate { try await model.delete(id: rows[i].id, kind: "workout") }
          }
        }
        if model.workouts.isEmpty {
          Text(
            "Your sessions will appear here. Workouts survive app relaunch; disconnected periods have no invented heart rate."
          ).foregroundStyle(.secondary)
        }
      }
    }.navigationTitle("Activity")
  }
}
struct WorkoutDetailView: View {
  @Environment(AppModel.self) var model
  let workout: Workout
  @State private var note = ""
  @State private var effort = 5
  @State private var historical: [TempoCore.Measurement] = []
  var observations: [TempoCore.Measurement] {
    (workout.end == nil ? model.canonical : historical).filter {
      $0.kind == .heartRate && $0.timestamp >= workout.start
        && $0.timestamp <= (workout.end ?? Date())
    }
  }
  var body: some View {
    let chartPoints = ChartProjection.points(observations)
    return List {
      Section {
        MetricRow(
          label: "Duration", value: durationText(workout.activeDuration(at: workout.end ?? Date())))
        let load = CardiovascularLoad.calculate(
          observations, maxHeartRate: model.maxHeartRate, workout: workout)
        MetricRow(
          label: "Coverage",
          value:
            "\(Int(min(1,(load?.coveredSeconds ?? 0)/max(1,workout.activeDuration(at:workout.end ?? Date())))*100))%"
        )
        MetricRow(
          label: "Average heart rate",
          value: load?.average.map { String(format: "%.0f bpm", $0) } ?? "Unavailable")
        MetricRow(
          label: "Maximum heart rate",
          value: load?.maximum.map { String(format: "%.0f bpm", $0) } ?? "Unavailable")
        MetricRow(
          label: "Cardiovascular load",
          value: (load?.coveredSeconds ?? 0) > 60
            ? String(format: "%.0f", load?.points ?? 0) : "Unavailable",
          detail: "Estimate · Edwards zones · maximum HR \(Int(model.maxHeartRate))")
      }
      Section("Heart rate") {
        if observations.isEmpty {
          Text("No measured heart rate during this workout.")
        } else {
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
      Section("Time in zones") {
        if let load = CardiovascularLoad.calculate(
          observations, maxHeartRate: model.maxHeartRate, workout: workout)
        {
          ForEach(0..<5, id: \.self) { i in
            MetricRow(label: "Zone \(i+1)", value: durationText(load.zones[i]))
          }
        }
      }
      Section("Sources") {
        ForEach(workout.sources) { s in
          Text(
            "\(model.devices.first{$0.id==s.deviceID}?.name ?? "Registered band") · \(s.start.formatted(date:.omitted,time:.shortened))\n\(s.reason)"
          ).font(.subheadline)
        }
      }
      Section("Your experience") {
        TextField("Notes", text: $note, axis: .vertical)
        Stepper("Perceived exertion: \(effort)/10", value: $effort, in: 1...10)
        Button("Save notes") {
          model.mutate {
            var w = model.workouts.first(where: { $0.id == workout.id }) ?? workout
            w.note = note
            w.perceivedExertion = effort
            try await model.save(w, kind: "workout")
          }
        }
        if workout.activity == .strength {
          Text("Heart rate captures cardiovascular demand, not muscular load.").font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }.navigationTitle(workout.activity.rawValue.capitalized).onAppear {
      note = workout.note
      effort = workout.perceivedExertion ?? 5
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
