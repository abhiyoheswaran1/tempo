import Foundation

public enum BluetoothCommandPolicy {
  @discardableResult public static func perform(
    poweredOn: Bool, collectionAllowed: Bool,
    cleanup: Bool = false, action: () -> Void
  ) -> Bool {
    guard poweredOn, collectionAllowed || cleanup else { return false }
    action()
    return true
  }
}
public struct LiveMeasurementWindow: Sendable {
  public let samples: [Measurement]
  public let truncated: Bool
  public init(samples: [Measurement], truncated: Bool) {
    self.samples = samples
    self.truncated = truncated
  }
}
public struct LiveHistorySnapshot: Sendable {
  public let points: [LiveChartPoint]
  public let coveredSeconds: TimeInterval
  public let average: Double?
  public let minimum: Double?
  public let maximum: Double?
  public let sampleCount: Int
  public let sourceIDs: [UUID]
  public init(
    samples: [Measurement], from: Date, to: Date, sourceSegments: [SourceSegment],
    maximumHeartRate: Double, allowSynthetic: Bool = false
  ) {
    let valid = CanonicalTimeline.select(
      samples.filter {
        $0.kind == .heartRate && $0.valid && (25...240).contains($0.value)
          && ($0.origin == .measured || (allowSynthetic && $0.origin == .synthetic))
          && $0.timestamp >= from && $0.timestamp <= to
      }, sourceSegments: sourceSegments)
    let load = CardiovascularLoad.calculate(valid, maxHeartRate: maximumHeartRate)
    coveredSeconds = load?.coveredSeconds ?? 0
    average = load?.average
    minimum = valid.map(\.value).min()
    maximum = valid.map(\.value).max()
    sampleCount = valid.count
    sourceIDs = Array(Set(valid.map(\.deviceID))).sorted { $0.uuidString < $1.uuidString }
    // Each of 240 time buckets retains original first/last/min/max observations.
    // Segment IDs are computed before reduction, so discarded points cannot bridge a gap.
    let raw = LiveChartSeries.points(valid)
    let width = max(1, to.timeIntervalSince(from) / 240)
    let groups = Dictionary(grouping: raw) {
      min(239, max(0, Int($0.sample.timestamp.timeIntervalSince(from) / width)))
    }
    points = groups.keys.sorted().flatMap { bucket in
      let group = groups[bucket]!
      let candidates = [
        group.first!, group.last!, group.min { $0.sample.value < $1.sample.value }!,
        group.max { $0.sample.value < $1.sample.value }!,
      ]
      return Dictionary(grouping: candidates, by: \.id).values.compactMap(\.first)
        .sorted {
          $0.sample.timestamp == $1.sample.timestamp
            ? $0.id < $1.id : $0.sample.timestamp < $1.sample.timestamp
        }
    }
  }
}
