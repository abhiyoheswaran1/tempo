import Foundation

public struct ActivityDetectionSettings: Codable, Sendable {
  public var activationFraction = 0.65
  public var releaseFraction = 0.55
  public var minimumDuration: TimeInterval = 600
  public var minimumMinuteCoverage = 0.8
  public var activationMinutes = 2
  public var recoveryMinutes = 3
  public var maximumSampleGap: TimeInterval = 10
  public init() {}
  var valid: Bool {
    activationFraction.isFinite && releaseFraction.isFinite && activationFraction > releaseFraction
      && (0.3...0.95).contains(activationFraction) && (0.2...0.9).contains(releaseFraction)
      && minimumDuration >= 120 && minimumDuration <= 43200 && minimumMinuteCoverage >= 0.5
      && minimumMinuteCoverage <= 1 && activationMinutes >= 1 && recoveryMinutes >= 1
      && maximumSampleGap > 0 && maximumSampleGap <= 10
  }
}
public struct DetectedActivityCandidate: Codable, Sendable, Identifiable, Equatable {
  public var start: Date
  public var end: Date
  public var coverage: Double
  public var sourceIDs: [UUID]
  public var inputDigest: String
  public var inputCount: Int
  public var finishReason: String
  public var maximumHeartRate: Double
  public var activationBPM: Double
  public var releaseBPM: Double
  public var algorithmVersion: String
  public var origin: Origin
  public var confirmedWear: Bool
  public var id: UUID {
    StableID.uuid("\(algorithmVersion)|\(Int(start.timeIntervalSince1970/60))")
  }
  public var workoutID: UUID { StableID.uuid("confirmed-workout|\(id.uuidString)") }
}
public enum ActivityDecisionStatus: String, Codable, Sendable { case pending, confirmed, dismissed }
public struct DetectedActivityDecision: Codable, Sendable, Identifiable, Equatable {
  public var candidate: DetectedActivityCandidate
  public var status: ActivityDecisionStatus
  public var id: UUID { candidate.id }
  public init(candidate: DetectedActivityCandidate, status: ActivityDecisionStatus = .pending) {
    self.candidate = candidate
    self.status = status
  }
}
extension StableID {
  public static func uuid(_ text: String) -> UUID {
    let hex = hash(text)
    return UUID(
      uuidString:
        "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.dropFirst(20).prefix(12))"
    )!
  }
}
public enum AutomaticActivityDetector {
  private struct Minute {
    var covered = 0.0
    var high = 0.0
    var sustain = 0.0
  }
  public static func detect(
    _ observations: [Measurement], maxHeartRate: Double, now: Date,
    sourceSegments: [SourceSegment] = [], existingWorkouts: [Workout] = [],
    settings: ActivityDetectionSettings = ActivityDetectionSettings(), allowSynthetic: Bool = false
  ) -> [DetectedActivityCandidate] {
    guard (100...240).contains(maxHeartRate), settings.valid else { return [] }
    let samples = CanonicalTimeline.select(
      observations.filter {
        $0.kind == .heartRate
          && ($0.origin == .measured || (allowSynthetic && $0.origin == .synthetic)) && $0.valid
          && (25...240).contains($0.value)
          && $0.timestamp <= now
      }, sourceSegments: sourceSegments)
    var minutes: [Int: Minute] = [:]
    for (a, b) in zip(samples, samples.dropFirst()) {
      let delta = b.timestamp.timeIntervalSince(a.timestamp)
      guard delta > 0, delta <= settings.maximumSampleGap else { continue }
      var cursor = a.timestamp.timeIntervalSince1970
      let until = b.timestamp.timeIntervalSince1970
      while cursor < until {
        let key = Int(floor(cursor / 60))
        let end = min(until, Double(key + 1) * 60)
        let seconds = end - cursor
        var bin = minutes[key] ?? Minute()
        bin.covered += seconds
        if a.value >= maxHeartRate * settings.activationFraction { bin.high += seconds }
        if a.value >= maxHeartRate * settings.releaseFraction { bin.sustain += seconds }
        minutes[key] = bin
        cursor = end
      }
    }
    var results: [DetectedActivityCandidate] = []
    var warmStart: Int?
    var warmCount = 0
    var activeStart: Int?
    var lastSupportEnd: Int?
    var recovery = 0
    var previous: Int?
    func emit(_ reason: String) {
      guard let start = activeStart, let end = lastSupportEnd,
        Double(end - start) * 60 >= settings.minimumDuration
      else { return }
      let from = Date(timeIntervalSince1970: Double(start) * 60)
      let to = Date(timeIntervalSince1970: Double(end) * 60)
      guard
        !existingWorkouts.contains(where: { w in w.start < to && (w.end ?? .distantFuture) > from })
      else { return }
      let selected = samples.filter { $0.timestamp >= from && $0.timestamp < to }
      let covered = (start..<end).reduce(0.0) { $0 + (minutes[$1]?.covered ?? 0) }
      results.append(
        DetectedActivityCandidate(
          start: from, end: to, coverage: min(1, covered / to.timeIntervalSince(from)),
          sourceIDs: Array(Set(selected.map(\.deviceID))).sorted { $0.uuidString < $1.uuidString },
          inputDigest: StableID.hash(selected.map(\.id).joined(separator: "|")),
          inputCount: selected.count, finishReason: reason, maximumHeartRate: maxHeartRate,
          activationBPM: maxHeartRate * settings.activationFraction,
          releaseBPM: maxHeartRate * settings.releaseFraction, algorithmVersion: "activity-hr-1.0",
          origin: selected.contains(where: { $0.origin == .synthetic }) ? .synthetic : .derived,
          confirmedWear: !selected.isEmpty && selected.allSatisfy { $0.wear == .onBody }))
    }
    func reset() {
      warmStart = nil
      warmCount = 0
      activeStart = nil
      lastSupportEnd = nil
      recovery = 0
    }
    for key in minutes.keys.sorted() {
      guard Double(key + 1) * 60 <= now.timeIntervalSince1970, let bin = minutes[key] else {
        continue
      }
      if let previous, key > previous + 1 {
        emit("Data gap; end time is the last supported interval")
        reset()
      }
      previous = key
      guard bin.covered / 60 >= settings.minimumMinuteCoverage else {
        emit("Insufficient coverage; timing needs review")
        reset()
        continue
      }
      let high = bin.high / bin.covered >= 0.7
      let sustained = bin.sustain / bin.covered >= 0.5
      if activeStart == nil {
        if high {
          if warmStart == nil { warmStart = key }
          warmCount += 1
          if warmCount >= settings.activationMinutes {
            activeStart = warmStart
            lastSupportEnd = key + 1
          }
        } else {
          warmStart = nil
          warmCount = 0
        }
      } else if sustained {
        lastSupportEnd = key + 1
        recovery = 0
      } else {
        recovery += 1
        if recovery >= settings.recoveryMinutes {
          emit("Heart rate settled; review the estimated timing")
          reset()
        }
      }
    }
    if let lastSupportEnd,
      now.timeIntervalSince1970 - Double(lastSupportEnd) * 60 >= Double(settings.recoveryMinutes)
        * 60
    {
      emit("Data stopped; activity completion is uncertain")
    }
    return results
  }
}
