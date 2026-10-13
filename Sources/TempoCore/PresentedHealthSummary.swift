import Foundation

/// Immutable presentation calculation; callers can compute it outside the UI actor.
/// Uses the existing readiness/load methods without changing their input requirements.
public struct PresentedHealthSummary: Sendable {
  public let readiness: ReadinessResult
  public let load: LoadResult?
  public let sleepID: UUID?
  public static func calculate(records: [Measurement], sleeps: [SleepSession],
    nightMetrics: [UUID: [String: Double]], sourceSegments: [SourceSegment],
    placements: [PlacementRecord], maximumHeartRate: Double, now: Date,
    calendar: Calendar = .current) -> PresentedHealthSummary {
    let selected = CanonicalTimeline.select(records, sourceSegments: sourceSegments)
    let nights = sleeps.filter { !$0.isNap && $0.duration >= 4 * 3600 && $0.end <= now }
      .sorted { $0.end < $1.end }
    func inputs(_ night: SleepSession) -> [String: Double] {
      nightMetrics[night.id] ?? ["sleepHours": night.duration / 3600]
    }
    let recentNights = Array(nights.suffix(29))
    let baseline = recentNights.map { night in
      PersonalBaseline(date: night.end, values: inputs(night),
        sourceIDs: Array(Set(selected.filter { $0.timestamp >= night.start && $0.timestamp < night.end }.map(\.deviceID))))
    }
    let overnight = selected.filter { sample in
      recentNights.contains { sample.timestamp >= $0.start && sample.timestamp < $0.end }
    }
    let locations = PlacementTimeline.locations(samples: overnight, records: placements).subtracting([.unknown])
    let currentSleep = SleepPresentation(sessions: sleeps, now: now).readinessSession
    let readiness = Readiness.calculate(current: currentSleep.map(inputs) ?? [:],
      baseline: currentSleep == nil ? baseline : Array(baseline.dropLast()),
      deviceChange: Set(sourceSegments.filter { $0.start > now.addingTimeInterval(-28*86400) }.map(\.deviceID)).count > 1,
      placementChange: locations.count > 1)
    let day = DayHistory.window(for: now, calendar: calendar)
    let load = CardiovascularLoad.calculate(selected.filter { day.contains($0.timestamp) }, maxHeartRate: maximumHeartRate)
    return PresentedHealthSummary(readiness: readiness, load: load, sleepID: currentSleep?.id)
  }
}
