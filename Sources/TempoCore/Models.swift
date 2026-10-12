import CryptoKit
import Foundation

public enum StableID {
  public static func hash(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
  public static func hash(_ text: String) -> String { hash(Data(text.utf8)) }
}
public struct Measurement: Codable, Sendable, Identifiable, Equatable {
  public var id: String
  public var deviceID: UUID
  public var kind: MetricKind
  public var timestamp: Date
  public var value: Double
  public var origin: Origin
  public var externalID: String?
  public var transport: String
  public var rrMilliseconds: [Double]
  public var quality: [String]
  public var qualityContext: [String: UInt8]?
  public var wear: WearState
  public var algorithmVersion: String?
  public init(
    deviceID: UUID, kind: MetricKind, timestamp: Date, value: Double, origin: Origin,
    transport: String, recordKey: String? = nil, rrMilliseconds: [Double] = [],
    quality: [String] = [], wear: WearState = .unknown
  ) {
    self.deviceID = deviceID
    self.kind = kind
    self.timestamp = timestamp
    self.value = value
    self.origin = origin
    self.externalID = recordKey
    self.transport = transport
    self.rrMilliseconds = rrMilliseconds
    self.quality = quality
    self.wear = wear
    id = StableID.hash(
      "\(deviceID.uuidString)|\(kind.rawValue)|\(transport)|\(recordKey ?? String(timestamp.timeIntervalSince1970))"
    )
  }
  public var isBandHistory: Bool {
    transport.hasPrefix("whoop4-history-") || transport.hasPrefix("whoop5-history-")
  }
  public var valid: Bool { value.isFinite && quality.isEmpty && wear != .offBody }
  /// Direct experimental readings remain inspectable; opaque signal quality is not an analytical validity claim.
  public var permitsPhysiologicalAnalytics: Bool { valid && qualityContext == nil }
}
public struct SourceSegment: Codable, Sendable, Equatable, Identifiable {
  public var id = UUID()
  public var deviceID: UUID
  public var start: Date
  public var end: Date?
  public var reason: String
  public init(deviceID: UUID, start: Date, end: Date?, reason: String) {
    self.deviceID = deviceID
    self.start = start
    self.end = end
    self.reason = reason
  }
}
public enum Activity: String, Codable, Sendable, CaseIterable {
  case padel, cycling, running, strength, walking, other
}
public struct Workout: Codable, Sendable, Identifiable, Equatable {
  public var id = UUID()
  public var activity: Activity
  public var start: Date
  public var end: Date?
  public var pauses: [DateInterval] = []
  public var pausedAt: Date?
  public var sources: [SourceSegment] = []
  public var note = ""
  public var perceivedExertion: Int?
  public var soreness: Int?
  public var origin: Origin = .manual
  public var detectionID: UUID?
  public var algorithmVersion: String?
  public init(activity: Activity, start: Date) {
    self.activity = activity
    self.start = start
  }
  public mutating func pause(at date: Date) {
    guard end == nil, pausedAt == nil, date >= start else { return }
    pausedAt = date
  }
  public mutating func resume(at date: Date) {
    guard let p = pausedAt, date >= p, end == nil else { return }
    pauses.append(DateInterval(start: p, end: date))
    pausedAt = nil
  }
  public mutating func finish(at date: Date) {
    guard end == nil, date >= start else { return }
    if let p = pausedAt {
      pauses.append(DateInterval(start: p, end: date))
      pausedAt = nil
    }
    end = date
    if !sources.isEmpty, sources.last?.end == nil { sources[sources.count - 1].end = date }
  }
  public mutating func closeSource(_ id: UUID, at date: Date) {
    guard end == nil, let last = sources.last, last.deviceID == id, last.end == nil else { return }
    sources[sources.count - 1].end = max(date, last.start)
  }
  public mutating func switchSource(to id: UUID, at date: Date) {
    guard end == nil, !(sources.last?.deviceID == id && sources.last?.end == nil) else { return }
    if !sources.isEmpty, sources.last?.end == nil { sources[sources.count - 1].end = date }
    sources.append(SourceSegment(deviceID: id, start: date, end: nil, reason: "workout source"))
  }
  public func activeDuration(at now: Date) -> TimeInterval {
    let until = end ?? now
    let pause =
      pauses.reduce(0) { $0 + $1.duration }
      + (pausedAt.map { max(0, until.timeIntervalSince($0)) } ?? 0)
    return max(0, until.timeIntervalSince(start) - pause)
  }
  public func isActive(at t: Date) -> Bool {
    t >= start && t <= (end ?? .distantFuture) && !pauses.contains { $0.contains(t) }
      && !(pausedAt.map { t >= $0 } ?? false)
  }
}
public struct SleepSession: Codable, Sendable, Identifiable, Equatable {
  public var id = UUID()
  public var start: Date
  public var end: Date
  public var timeZoneID: String
  public var origin: Origin
  public var isNap: Bool = false
  public var confidence: Double?
  public var algorithmVersion: String?
  public init(start: Date, end: Date, timeZoneID: String, origin: Origin) {
    self.start = start
    self.end = end
    self.timeZoneID = timeZoneID
    self.origin = origin
  }
  public var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
}
public struct JournalEntry: Codable, Sendable, Identifiable, Equatable {
  public var id = UUID()
  public var date: Date
  public var timeZoneID: String
  public var energy: Int?
  public var mood: Int?
  public var soreness: Int?
  public var sleepQuality: Int?
  public var unwell: Bool?
  public var alcohol: Bool?
  public var lateMeal: Bool?
  public var caffeineTime: Date?
  public var note = ""
  public init(date: Date = Date(), timeZoneID: String = TimeZone.current.identifier) {
    self.date = date
    self.timeZoneID = timeZoneID
  }
}
public struct Revision: Codable, Sendable, Identifiable, Equatable {
  public var id: UUID
  public var entityID: UUID
  public var kind: String
  public var parentIDs: [UUID]
  public var payload: Data
  public var createdAt: Date
  public var deleted: Bool
  public init(
    id: UUID = UUID(), entityID: UUID, kind: String, parentIDs: [UUID], payload: Data,
    deleted: Bool = false, createdAt: Date = Date()
  ) {
    self.id = id
    self.entityID = entityID
    self.kind = kind
    self.parentIDs = parentIDs
    self.payload = payload
    self.createdAt = createdAt
    self.deleted = deleted
  }
}
public struct DerivedMetric: Codable, Sendable {
  public var kind: String
  public var value: Double?
  public var confidence: Double
  public var inputIDs: [String]
  public var algorithmVersion: String
  public var explanation: [String]
}
public struct PersonalBaseline: Codable, Sendable {
  public var date: Date
  public var values: [String: Double]
  public var sourceIDs: [UUID]
  public init(date: Date, values: [String: Double], sourceIDs: [UUID] = []) {
    self.date = date
    self.values = values
    self.sourceIDs = sourceIDs
  }
}
public struct SyncEnvelope: Codable, Sendable, Identifiable {
  public var id: String
  public var kind: String
  public var payload: Data
  public init(id: String, kind: String, payload: Data) {
    self.id = id
    self.kind = kind
    self.payload = payload
  }
}
public struct PendingChange: Codable, Sendable, Identifiable {
  public var id: String
  public var attempts: Int
  public var nextAttempt: Date
  public var envelope: SyncEnvelope
}
public struct BackupArchive: Codable, Sendable {
  public var format = "tempo-backup"
  public var schemaVersion = 2
  public var exportedAt: Date
  public var algorithmVersion = "tempo-1.0"
  public var payload: Data
  public var checksum: String
  public init(payload: Data) {
    self.payload = payload
    exportedAt = Date()
    checksum = StableID.hash(payload)
  }
  public func validate() throws {
    guard format == "tempo-backup", (1...2).contains(schemaVersion),
      payload.count <= 256 * 1024 * 1024,
      checksum == StableID.hash(payload)
    else { throw StoreError.invalidArchive }
  }
}
