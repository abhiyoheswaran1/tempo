import Foundation

public struct DailyTrendSummary: Sendable, Identifiable {
  public var date: Date
  public var kind: MetricKind
  public var value: Double
  public var coveredSeconds: Double?
  public var inputCount: Int
  public var inputOrigins: [Origin]
  public var sourceIDs: [UUID]
  public var inputDigest: String
  public var method: String
  public var truncated = false
  public var algorithmVersion = "daily-summary-1.0"
  public var id: String { "\(kind.rawValue)|\(date.timeIntervalSince1970)" }
  public static func calculate(
    _ measurements: [Measurement], kind: MetricKind, calendar: Calendar = .current,
    sourceSegments: [SourceSegment] = [], allowSynthetic: Bool = false
  ) -> [DailyTrendSummary] {
    let samples = CanonicalTimeline.select(
      measurements.filter {
        $0.kind == kind && $0.valid && ($0.origin != .synthetic || allowSynthetic) && $0.value > 0
          && ((kind != .heartRate && kind != .restingHeartRate) || (25...240).contains($0.value))
      }, sourceSegments: sourceSegments)
    let groups = Dictionary(grouping: samples) { calendar.startOfDay(for: $0.timestamp) }
    return groups.keys.sorted().compactMap { day in
      let input = groups[day]!
      var evidence = Dictionary(uniqueKeysWithValues: input.map { ($0.id, $0) })
      let until = calendar.date(byAdding: .day, value: 1, to: day)!
      var weighted = 0.0
      var covered = 0.0
      if kind == .heartRate {
        // Include the preceding day sample only when it can legitimately cover a midnight boundary.
        let range = samples.filter {
          $0.timestamp >= day.addingTimeInterval(-10)
            && $0.timestamp <= until.addingTimeInterval(10)
        }
        for (a, b) in zip(range, range.dropFirst()) {
          let delta = b.timestamp.timeIntervalSince(a.timestamp)
          guard delta > 0, delta <= 10 else { continue }
          let exposure = max(0, min(b.timestamp, until).timeIntervalSince(max(a.timestamp, day)))
          if exposure > 0 {
            evidence[a.id] = a
            evidence[b.id] = b
          }
          covered += exposure
          weighted += exposure * a.value
        }
        guard covered >= 60 else { return nil }
      }
      let value: Double
      let method: String
      if kind == .heartRate {
        value = weighted / covered
        method = "Covered-time average"
      } else if kind == .weight {
        value = input.last!.value
        method = "Latest measurement"
      } else {
        let values = input.map(\.value).sorted()
        value =
          values.count % 2 == 0
          ? (values[values.count / 2 - 1] + values[values.count / 2]) / 2 : values[values.count / 2]
        method = "Daily median"
      }
      let evidenceSamples = evidence.values.sorted {
        $0.timestamp == $1.timestamp ? $0.id < $1.id : $0.timestamp < $1.timestamp
      }
      return DailyTrendSummary(
        date: day, kind: kind, value: value,
        coveredSeconds: kind == .heartRate ? covered : nil, inputCount: evidenceSamples.count,
        inputOrigins: Array(Set(evidenceSamples.map(\.origin))).sorted {
          $0.rawValue < $1.rawValue
        },
        sourceIDs: Array(Set(evidenceSamples.map(\.deviceID))).sorted {
          $0.uuidString < $1.uuidString
        },
        inputDigest: StableID.hash(evidenceSamples.map(\.id).joined(separator: "|")), method: method
      )
    }
  }
}
