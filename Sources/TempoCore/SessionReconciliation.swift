import Foundation

public enum SourceTimeline {
  public static func normalized(_ segments: [SourceSegment]) -> [SourceSegment] {
    var sorted = segments.sorted {
      $0.start == $1.start ? $0.id.uuidString < $1.id.uuidString : $0.start < $1.start
    }
    for i in sorted.indices where i + 1 < sorted.count {
      sorted[i].end = min(sorted[i].end ?? .distantFuture, sorted[i + 1].start)
    }
    return sorted
  }
}
public enum SessionReconciliation {
  // Observations remain immutable. This is a display/analytics projection with manual-source priority.
  public static func sleep(_ sessions: [SleepSession]) -> [SleepSession] {
    var chosen: [SleepSession] = []
    for s in sessions.sorted(by: {
      rank($0.origin) == rank($1.origin)
        ? ($0.duration == $1.duration ? $0.id.uuidString < $1.id.uuidString : $0.duration > $1.duration)
        : rank($0.origin) > rank($1.origin)
    }) {
      guard DayHistory.valid(s) else { continue }
      let interval = DateInterval(start: s.start, end: s.end)
      if chosen.contains(where: {
        (DateInterval(start: $0.start, end: $0.end).intersection(with: interval)?.duration ?? 0) > 0
      }) {
        continue
      }
      chosen.append(s)
    }
    return chosen.sorted { $0.end < $1.end }
  }
  public static func workouts(_ sessions: [Workout]) -> [Workout] {
    var chosen: [Workout] = []
    for w in sessions.sorted(by: {
      let left = $0.detectionID != nil ? 5 : rank($0.origin)
      let right = $1.detectionID != nil ? 5 : rank($1.origin)
      return left == right ? $0.id.uuidString < $1.id.uuidString : left > right
    }) {
      let end = w.end ?? .distantFuture
      let interval = DateInterval(start: w.start, end: end)
      if w.origin == .imported
        && chosen.contains(where: { existing in
          let other = DateInterval(start: existing.start, end: existing.end ?? .distantFuture)
          return (other.intersection(with: interval)?.duration ?? 0) > 0.5
            * min(other.duration, interval.duration)
        })
      {
        continue
      }
      chosen.append(w)
    }
    return chosen
  }
  private static func rank(_ origin: Origin) -> Int {
    switch origin {
    case .manual: return 5
    case .measured: return 4
    case .imported: return 3
    case .derived: return 2
    case .synthetic: return 1
    }
  }
}
