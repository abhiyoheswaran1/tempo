import Foundation

public enum EvidenceLevel: String, Sendable {
  case building, limited, developing, strong
  public init(confidence: Double) {
    if !confidence.isFinite || confidence <= 0 {
      self = .building
    } else if confidence < 0.5 {
      self = .limited
    } else if confidence < 0.8 {
      self = .developing
    } else {
      self = .strong
    }
  }
  public var title: String {
    switch self {
    case .building: return "Building baseline"
    case .limited: return "Limited evidence"
    case .developing: return "Developing evidence"
    case .strong: return "Strong evidence"
    }
  }
}
public enum SampleFreshness: Sendable {
  case missing, fresh, stale
  public init(timestamp: Date?, now: Date) {
    guard let timestamp else {
      self = .missing
      return
    }
    let age = now.timeIntervalSince(timestamp)
    self = age.isFinite && age >= -5 && age <= 90 ? .fresh : .stale
  }
}
public struct SleepPresentation {
  public var session: SleepSession?
  public var readinessSession: SleepSession?
  public var title: String
  public init(sessions: [SleepSession], now: Date, calendar: Calendar = .current) {
    session = sessions.filter { !$0.isNap && $0.end <= now && $0.end > $0.start }.max {
      $0.end < $1.end
    }
    readinessSession = sessions.filter {
      !$0.isNap && $0.duration >= 4 * 3600 && $0.end <= now
        && now.timeIntervalSince($0.end) <= 36 * 3600
    }.max { $0.end < $1.end }
    if let session, calendar.isDate(session.end, inSameDayAs: now),
      calendar.component(.hour, from: session.end) <= 12
    {
      title = "Last night"
    } else {
      title = "Latest sleep"
    }
  }
}
public enum WorkoutPresentation {
  public static func orderedActivities(_ workouts: [Workout]) -> [Activity] {
    let frequency = Dictionary(grouping: workouts.filter { $0.end != nil }, by: \.activity)
      .mapValues(\.count)
    return Activity.allCases.sorted {
      let left = frequency[$0] ?? 0
      let right = frequency[$1] ?? 0
      return left == right
        ? Activity.allCases.firstIndex(of: $0)! < Activity.allCases.firstIndex(of: $1)!
        : left > right
    }
  }
}

public enum LiveSampleSelection {
  public static func latest(
    _ samples: [Measurement], selectedDeviceID: UUID?, now: Date, allowSynthetic: Bool = false
  ) -> Measurement? {
    samples.filter {
      $0.kind == .heartRate && $0.valid && (25...240).contains($0.value)
        && ($0.origin == .measured || (allowSynthetic && $0.origin == .synthetic))
        && $0.timestamp <= now.addingTimeInterval(5)
        && (selectedDeviceID == nil || $0.deviceID == selectedDeviceID)
    }.max { $0.timestamp == $1.timestamp ? $0.id < $1.id : $0.timestamp < $1.timestamp }
  }
}

public enum LiveReadingState: Sendable {
  case waiting, live, recent, stale
  public init(timestamp: Date?, connected: Bool, now: Date) {
    guard let timestamp else {
      self = .waiting
      return
    }
    let age = now.timeIntervalSince(timestamp)
    guard age.isFinite, age >= -5, age <= 90 else {
      self = .stale
      return
    }
    self = connected && age <= 10 ? .live : .recent
  }
}

public enum SyncFreshness {
  public static let cloudInterval: TimeInterval = 300
  public static func shouldSync(lastSuccess: Date?, pending: Int, now: Date) -> Bool {
    pending > 0 || lastSuccess.map { now.timeIntervalSince($0) >= cloudInterval } ?? true
  }
}

public enum WearEvidence {
  /// Contact flags remain useful even when off-body physiological values are excluded.
  public static func current(_ sample: Measurement?, connected: Bool, now: Date) -> WearState {
    guard connected, let sample, sample.origin == .measured, sample.quality.isEmpty,
      sample.timestamp <= now.addingTimeInterval(5), now.timeIntervalSince(sample.timestamp) <= 90
    else { return .unknown }
    return sample.wear
  }
}

public enum ManualRefreshOutcome: Equatable, Sendable {
  case demo, localOnly, cloudRunning, needsAttention, pending, synced, retryScheduled
  public static func resolve(
    demo: Bool, cloudEnabled: Bool, cloudBusy: Bool,
    cloudError: String?, pending: Int, lastSuccess: Date?, startedAt: Date
  ) -> Self {
    if demo { return .demo }
    if !cloudEnabled { return .localOnly }
    if cloudBusy { return .cloudRunning }
    if cloudError != nil { return .needsAttention }
    if pending > 0 { return .pending }
    if let lastSuccess, lastSuccess >= startedAt { return .synced }
    return .retryScheduled
  }
  public var message: String {
    switch self {
    case .demo: "Demo refreshed · real integrations stay off"
    case .localOnly: "Local history refreshed · iCloud is off"
    case .cloudRunning: "Collection checked · iCloud sync is still running"
    case .needsAttention: "Local history refreshed · iCloud needs attention"
    case .pending: "Collection checked · some uploads await retry"
    case .synced: "Collection checked · iCloud synced"
    case .retryScheduled: "Collection checked · iCloud retry is scheduled"
    }
  }
}
