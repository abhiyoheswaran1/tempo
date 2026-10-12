import Foundation

public struct HRVResult: Sendable {
  public var rmssd: Double
  public var sdnn: Double
  public var accepted: Int
  public var rejected: Int
  public var coverage: Double
}
public enum HRV {
  public static func calculate(_ intervals: [Double], minimumIntervals: Int = 240) -> HRVResult? {
    guard intervals.count >= minimumIntervals else { return nil }
    var accepted: [Double] = []
    var squares: [Double] = []
    var previous: Double?
    var rejected = 0
    for rr in intervals {
      guard rr.isFinite, (300...2000).contains(rr) else {
        rejected += 1
        previous = nil
        continue
      }
      if let p = previous, abs(rr - p) / p > 0.2 {
        rejected += 1
        previous = nil
        continue
      }
      if let p = previous { squares.append(pow(rr - p, 2)) }
      accepted.append(rr)
      previous = rr
    }
    let coverage = Double(accepted.count) / Double(intervals.count)
    guard accepted.count >= minimumIntervals, coverage >= 0.9, squares.count >= minimumIntervals - 1
    else { return nil }
    let mean = accepted.reduce(0, +) / Double(accepted.count)
    let sdnn = sqrt(accepted.reduce(0) { $0 + pow($1 - mean, 2) } / Double(accepted.count - 1))
    return HRVResult(
      rmssd: sqrt(squares.reduce(0, +) / Double(squares.count)), sdnn: sdnn,
      accepted: accepted.count, rejected: rejected, coverage: coverage)
  }
}
public struct ReadinessResult: Sendable {
  public var score: Int?
  public var confidence: Double
  public var headline: String
  public var factors: [String]
  public var baselineDays: Int
  public var algorithmVersion = "readiness-1.2"
}
public enum Readiness {
  public static func calculate(
    current: [String: Double], baseline: [PersonalBaseline], deviceChange: Bool = false,
    placementChange: Bool = false
  )
    -> ReadinessResult
  {
    let days = Set(baseline.map { Int(floor($0.date.timeIntervalSince1970 / 86400)) }).count
    guard days >= 7 else {
      return ReadinessResult(
        score: nil, confidence: 0, headline: "Your baseline is still building.",
        factors: ["At least 7 qualifying nights are needed; 21 establish your baseline."],
        baselineDays: days)
    }
    var components: [Double] = []
    var factors: [String] = []
    for key in ["rmssd", "rhr", "sleepHours"] {
      let values = baseline.compactMap { $0.values[key] }.filter { $0.isFinite && $0 > 0 }
      guard values.count >= 7, let v = current[key], v.isFinite, v > 0 else { continue }
      let processed = key == "rmssd" ? values.map { log($0) } : values
      let median = processed.sorted()[processed.count / 2]
      let deviations = processed.map { abs($0 - median) }.sorted()
      let scale = max(
        deviations[deviations.count / 2] * 1.4826, key == "rmssd" ? 0.1 : (key == "rhr" ? 3 : 0.5))
      let z = ((key == "rmssd" ? log(v) : v) - median) / scale
      components.append(max(-2, min(2, key == "rhr" ? -z : z)))
      factors.append(
        "\(key): \(String(format:"%.1f",v)); compared with \(values.count) personal nights")
    }
    guard components.count >= 2 else {
      return ReadinessResult(
        score: nil, confidence: 0, headline: "More overnight coverage is needed.", factors: factors,
        baselineDays: days)
    }
    let score =
      Int((60 + components.reduce(0, +) / Double(components.count) * 15).rounded() / 5) * 5
    let confidence =
      min(1, Double(days) / 21) * Double(components.count) / 3 * (deviceChange ? 0.5 : 1)
      * (placementChange ? 0.75 : 1)
    if deviceChange {
      factors.append(
        "Band sources changed; confidence reduced because device offsets are not calibrated.")
    }
    if placementChange {
      factors.append(
        "Reported body placement varied in available overnight samples; confidence conservatively reduced. No physiological correction applied."
      )
    }
    return ReadinessResult(
      score: score, confidence: confidence,
      headline: score < 50
        ? "A lighter day may suit your recent measurements."
        : "Your overnight measurements are close to your usual range.", factors: factors,
      baselineDays: days)
  }
}
public struct LoadResult: Sendable {
  public var points: Double
  public var coveredSeconds: Double
  public var zones: [Double]
  public var average: Double?
  public var maximum: Double?
}
public enum CardiovascularLoad {
  public static func calculate(
    _ samples: [Measurement], maxHeartRate: Double, workout: Workout? = nil
  ) -> LoadResult? {
    guard (100...240).contains(maxHeartRate) else { return nil }
    let hr = samples.filter {
      $0.kind == .heartRate && $0.permitsPhysiologicalAnalytics
    }.sorted { $0.timestamp < $1.timestamp }
    var zones = Array(repeating: 0.0, count: 5)
    var weighted = 0.0
    var coverage = 0.0
    for pair in zip(hr, hr.dropFirst()) {
      let elapsed = pair.1.timestamp.timeIntervalSince(pair.0.timestamp)
      guard elapsed > 0, elapsed <= 10 else { continue }
      var delta = elapsed
      if let workout {
        let start = max(pair.0.timestamp, workout.start)
        let end = min(pair.1.timestamp, workout.end ?? .distantFuture)
        guard end > start else { continue }
        var cursor = start
        delta = 0
        var pauses = workout.pauses
        if let pausedAt = workout.pausedAt {
          pauses.append(DateInterval(start: pausedAt, end: max(pausedAt, end)))
        }
        for pause in pauses.sorted(by: { $0.start < $1.start }) {
          let pauseStart = max(start, pause.start)
          let pauseEnd = min(end, pause.end)
          guard pauseEnd > pauseStart else { continue }
          delta += max(0, pauseStart.timeIntervalSince(cursor))
          cursor = max(cursor, pauseEnd)
        }
        delta += max(0, end.timeIntervalSince(cursor))
      }
      guard delta > 0 else { continue }
      let fraction = pair.0.value / maxHeartRate
      let zone = max(0, min(4, Int(floor((fraction - 0.5) * 10))))
      if fraction >= 0.5 { zones[zone] += delta }
      weighted += pair.0.value * delta
      coverage += delta
    }
    return LoadResult(
      points: zones.enumerated().reduce(0) { $0 + $1.element / 60 * Double($1.offset + 1) },
      coveredSeconds: coverage, zones: zones, average: coverage > 0 ? weighted / coverage : nil,
      maximum: hr.filter { workout?.isActive(at: $0.timestamp) ?? true }.map(\.value).max())
  }
}
public struct AssociationResult: Sendable {
  public var correlation: Double
  public var count: Int
  public var interval: ClosedRange<Double>
}
public enum Association {
  public static func calculate(_ pairs: [(Double, Double)]) -> AssociationResult? {
    let p = pairs.filter { $0.0.isFinite && $0.1.isFinite }
    guard p.count >= 30 else { return nil }
    let n = Double(p.count)
    let x = p.map(\.0).reduce(0, +) / n
    let y = p.map(\.1).reduce(0, +) / n
    let vx = p.reduce(0) { $0 + pow($1.0 - x, 2) }
    let vy = p.reduce(0) { $0 + pow($1.1 - y, 2) }
    guard vx > 0, vy > 0 else { return nil }
    let r = max(-0.999, min(0.999, p.reduce(0) { $0 + ($1.0 - x) * ($1.1 - y) } / sqrt(vx * vy)))
    let z = atanh(r)
    let e = 1.96 / sqrt(n - 3)
    return AssociationResult(correlation: r, count: p.count, interval: tanh(z - e)...tanh(z + e))
  }
}
