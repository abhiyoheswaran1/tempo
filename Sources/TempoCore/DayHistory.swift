import Foundation

public struct DayWindow: Sendable {
  public let start: Date
  public let end: Date
  public func contains(_ instant: Date) -> Bool { instant >= start && instant < end }
}

/// Calendar-day display projection. Originals and manual revision ancestry remain unchanged.
public enum DayHistory {
  public static func window(for date: Date, calendar: Calendar = .current) -> DayWindow {
    let start = calendar.startOfDay(for: date)
    return DayWindow(start: start, end: calendar.date(byAdding: .day, value: 1, to: start)!)
  }
  public static func valid(_ session: SleepSession) -> Bool {
    [session.start, session.end].allSatisfy {
      Int(exactly: floor($0.timeIntervalSince1970)) != nil
    } && session.end > session.start && session.duration <= 24 * 3600
  }
  public static func sessions(_ sessions: [SleepSession], on day: Date, now: Date,
    calendar: Calendar = .current, allowSynthetic: Bool = false) -> [SleepSession] {
    let window = window(for: day, calendar: calendar)
    return SessionReconciliation.sleep(sessions.filter {
      valid($0) && $0.end <= now
        && $0.origin != .derived && ($0.origin != .synthetic || allowSynthetic)
    }).filter { window.contains($0.end) }
  }
  /// One primary saved sleep per wake day. Imported stage intervals are not a whole night.
  public static func primarySleeps(_ sessions: [SleepSession], now: Date,
    calendar: Calendar = .current, allowSynthetic: Bool = false) -> [SleepSession] {
    let valid = SessionReconciliation.sleep(sessions.filter {
      self.valid($0) && $0.end <= now && $0.origin != .derived
        && ($0.origin != .synthetic || allowSynthetic)
    }).filter { !$0.isNap && $0.origin != .imported }
    return Dictionary(grouping: valid) { calendar.startOfDay(for: $0.end) }.values.compactMap {
      $0.sorted { $0.duration == $1.duration ? $0.id.uuidString < $1.id.uuidString : $0.duration > $1.duration }.first
    }.sorted { $0.end < $1.end }
  }
}

public enum DailyObservationKind: String, Sendable {
  case building, shorterSleep, longerSleep, usualSleep
}
public struct DailyObservation: Sendable {
  public let kind: DailyObservationKind
  public let currentSessionID: UUID?
  public let currentSeconds: Double?
  public let referenceSeconds: Double?
  public let differenceSeconds: Double?
  public let referenceSessionIDs: [UUID]
  public var referenceCount: Int { referenceSessionIDs.count }
  public let algorithmVersion = "daily-observation-1.0"
  public static func sleep(_ sessions: [SleepSession], now: Date, calendar: Calendar = .current,
    allowSynthetic: Bool = false) -> DailyObservation {
    let today = calendar.startOfDay(for: now)
    let from = calendar.date(byAdding: .day, value: -28, to: today)!
    let nights = DayHistory.primarySleeps(sessions, now: now, calendar: calendar,
      allowSynthetic: allowSynthetic)
    let current = nights.last { $0.end >= today }
    let prior = nights.filter { $0.end >= from && $0.end < today }
    let values = prior.map(\.duration).sorted()
    let reference: Double?
    if values.count >= 7 {
      let middle = values.count / 2
      reference = values.count.isMultiple(of: 2)
        ? values[middle - 1] / 2 + values[middle] / 2 : values[middle]
    } else { reference = nil }
    let delta = current.flatMap { s in reference.map { s.duration - $0 } }
    let kind: DailyObservationKind
    if let delta { kind = delta <= -1800 ? .shorterSleep : delta >= 1800 ? .longerSleep : .usualSleep }
    else { kind = .building }
    return DailyObservation(kind: kind, currentSessionID: current?.id,
      currentSeconds: current?.duration, referenceSeconds: reference, differenceSeconds: delta,
      referenceSessionIDs: prior.map(\.id))
  }
}

/// Recorded local clock times relative to midnight on the wake date.
/// Clock span is intentionally separate from elapsed duration across DST.
public struct SleepRhythmEntry: Identifiable, Sendable {
  public let session: SleepSession
  public let startHour: Double
  public let endHour: Double
  public var id: UUID { session.id }
  public init?(session: SleepSession) {
    guard DayHistory.valid(session), let zone = TimeZone(identifier: session.timeZoneID) else { return nil }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    let wakeDay = calendar.startOfDay(for: session.end)
    let startDay = calendar.startOfDay(for: session.start)
    let offset = calendar.dateComponents([.day], from: wakeDay, to: startDay).day ?? 0
    func hour(_ date: Date) -> Double {
      let c = calendar.dateComponents([.hour, .minute, .second], from: date)
      return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60 + Double(c.second ?? 0) / 3600
    }
    self.session = session
    startHour = Double(offset) * 24 + hour(session.start)
    endHour = hour(session.end)
  }
}

public extension JournalEntry {
  /// Time-only edits stay on the journal's recorded local day, including historical edits.
  func caffeineTimestamp(clock: Date) -> Date? {
    guard Int(exactly: floor(date.timeIntervalSince1970)) != nil,
      Int(exactly: floor(clock.timeIntervalSince1970)) != nil,
      let zone = TimeZone(identifier: timeZoneID) else { return nil }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    let time = calendar.dateComponents([.hour, .minute], from: clock)
    return calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0,
      second: 0, of: date)
  }
}
