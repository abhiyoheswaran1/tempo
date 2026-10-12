import Foundation

public struct ChartObservation: Identifiable, Sendable {
  public var sample: Measurement
  public var segment: Int
  public var id: String { sample.id }
}
public enum ChartProjection {
  public static func points(_ samples: [Measurement], maximumPoints: Int = 400)
    -> [ChartObservation]
  {
    guard !samples.isEmpty else { return [] }
    let step = max(1, Int(ceil(Double(samples.count) / Double(max(1, maximumPoints)))))
    var result: [ChartObservation] = []
    var segment = 0
    for i in samples.indices {
      let gap = i > 0 && samples[i].timestamp.timeIntervalSince(samples[i - 1].timestamp) > 10
      if gap {
        if result.last?.sample.id != samples[i - 1].id {
          result.append(ChartObservation(sample: samples[i - 1], segment: segment))
        }
        segment += 1
      }
      if gap || i % step == 0 || i == samples.count - 1 {
        result.append(ChartObservation(sample: samples[i], segment: segment))
      }
    }
    return result
  }
}
