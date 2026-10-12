import Foundation

public enum SourcePreference: String, Codable, Sendable, CaseIterable {
  case automatic, prefer4, prefer5
}
public struct DeviceEvidence: Sendable {
  public var deviceID: UUID
  public var generation: DeviceGeneration
  public var connected: Bool
  public var lastValidSample: Date?
  public var wear: WearState
  public init(
    deviceID: UUID, generation: DeviceGeneration, connected: Bool, lastValidSample: Date?,
    wear: WearState
  ) {
    self.deviceID = deviceID
    self.generation = generation
    self.connected = connected
    self.lastValidSample = lastValidSample
    self.wear = wear
  }
  func usable(_ now: Date, _ freshness: Double) -> Bool {
    connected && wear != .offBody
      && (lastValidSample.map {
        now.timeIntervalSince($0) >= 0 && now.timeIntervalSince($0) <= freshness
      } ?? false)
  }
}
public struct SourceSelector: Sendable {
  public var preference: SourcePreference = .automatic
  public var overrideID: UUID?
  public var freshness: TimeInterval = 90
  public var stability: TimeInterval = 30
  public var disconnectGrace: TimeInterval = 60
  public private(set) var activeID: UUID?
  private var candidateID: UUID?
  private var candidateSince: Date?
  private var unavailableSince: Date?
  public init() {}
  public mutating func update(_ evidence: [DeviceEvidence], now: Date) -> SourceSegment? {
    let usable = evidence.filter { $0.usable(now, freshness) }
    let active = evidence.first { $0.deviceID == activeID }
    let desired = usable.sorted { a, b in
      func rank(_ e: DeviceEvidence) -> Int {
        (e.deviceID == overrideID ? 100 : 0) + (e.wear == .onBody ? 20 : 0)
          + ((preference == .prefer4 && e.generation == .whoop4)
            || (preference == .prefer5 && e.generation == .whoop5) ? 10 : 0)
          + (e.deviceID == activeID ? 2 : 0)
      }
      return rank(a) == rank(b) ? a.deviceID.uuidString < b.deviceID.uuidString : rank(a) > rank(b)
    }.first
    guard let desired else {
      if unavailableSince == nil { unavailableSince = now }
      candidateID = nil
      candidateSince = nil
      return nil
    }
    if activeID == nil {
      activeID = desired.deviceID
      return SourceSegment(
        deviceID: desired.deviceID, start: now, end: nil,
        reason: "initial usable source; wear \(desired.wear.rawValue)")
    }
    if desired.deviceID == activeID {
      candidateID = nil
      candidateSince = nil
      unavailableSince = nil
      return nil
    }
    let activeUsable = active?.usable(now, freshness) ?? false
    if activeUsable && preference == .automatic && overrideID == nil {
      candidateID = nil
      candidateSince = nil
      unavailableSince = nil
      return nil
    }
    if !activeUsable && active?.wear != .offBody {
      if unavailableSince == nil { unavailableSince = now }
      guard now.timeIntervalSince(unavailableSince!) >= disconnectGrace else { return nil }
    }
    if candidateID != desired.deviceID {
      candidateID = desired.deviceID
      candidateSince = now
      return nil
    }
    guard now.timeIntervalSince(candidateSince ?? now) >= stability else { return nil }
    activeID = desired.deviceID
    candidateID = nil
    candidateSince = nil
    unavailableSince = nil
    return SourceSegment(
      deviceID: desired.deviceID, start: now, end: nil,
      reason: desired.wear == .onBody ? "confirmed contact" : "valid data; wear uncertain")
  }
}
public enum CanonicalTimeline {
  public static func select(
    _ samples: [Measurement], sourceSegments: [SourceSegment], overrideID: UUID? = nil,
    binSeconds: Double = 1
  ) -> [Measurement] {
    let groups = Dictionary(grouping: samples.filter { $0.valid }) {
      "\($0.kind.rawValue)|\(Int(floor($0.timestamp.timeIntervalSince1970/binSeconds)))"
    }
    return groups.values.compactMap { group in
      group.sorted { a, b in
        func rank(_ m: Measurement) -> Int {
          let transition = sourceSegments.filter {
            m.timestamp >= $0.start && m.timestamp < ($0.end ?? .distantFuture)
          }.max { $0.start < $1.start }
          let active = transition?.deviceID == m.deviceID
          return (m.deviceID == overrideID ? 100 : 0) + (active ? 40 : 0)
            + (m.wear == .onBody ? 20 : 0) + (m.origin == .measured ? 5 : 0)
        }
        return rank(a) == rank(b) ? a.id < b.id : rank(a) > rank(b)
      }.first
    }.sorted { $0.timestamp < $1.timestamp }
  }
}
public struct AccountGate: Codable, Sendable {
  public private(set) var boundAccount: String?
  public init() {}
  public mutating func bind(_ account: String) -> Bool {
    if let boundAccount { return boundAccount == account }
    boundAccount = account
    return true
  }
}
