import Foundation

/// Descriptive stored-receipt coverage, independent of physiological quality or sleep detection.
public struct CollectionCoverage: Sendable {
  public let from: Date
  public let to: Date
  public let coveredSeconds: Double
  public let sampleCount: Int
  public let historicalCount: Int
  public let latestRecord: Date?
  public let gaps: [DateInterval]
  public let hasUnqualifiedRecords: Bool
  public var fraction: Double { min(1, max(0, coveredSeconds / max(1, to.timeIntervalSince(from)))) }
  public init(samples: [Measurement], from: Date, to: Date, allowSynthetic: Bool = false) {
    self.from = from; self.to = to
    let records = samples.filter {
      $0.kind == .heartRate && $0.value.isFinite && (25...240).contains($0.value)
        && $0.timestamp.timeIntervalSince1970.isFinite && $0.timestamp >= from && $0.timestamp <= to
        && ($0.origin == .measured && ($0.transport == "bluetooth-hrs" || $0.isBandHistory)
          || allowSynthetic && $0.origin == .synthetic && $0.transport == "demo")
    }
    let instants = Set(records.map(\.timestamp)).sorted()
    sampleCount = Set(records.map(\.id)).count
    historicalCount = Set(records.filter(\.isBandHistory).map(\.id)).count
    latestRecord = instants.last
    hasUnqualifiedRecords = records.contains { !$0.permitsPhysiologicalAnalytics }
    var missing: [DateInterval] = [], covered = 0.0
    if from < to {
      if let first = instants.first {
        if first > from { missing.append(DateInterval(start: from, end: first)) }
        for (a,b) in zip(instants, instants.dropFirst()) {
          let delta = b.timeIntervalSince(a)
          if delta <= 10 { covered += delta }
          else { missing.append(DateInterval(start: a, end: b)) }
        }
        if let last = instants.last, last < to { missing.append(DateInterval(start: last, end: to)) }
      } else { missing = [DateInterval(start: from, end: to)] }
    }
    coveredSeconds = covered; gaps = missing
  }
}

public struct ReliabilityReport: Codable, Identifiable, Sendable {
  public var id: String { StableID.hash("\(start.timeIntervalSince1970)|\(end.timeIntervalSince1970)") }
  public let start: Date
  public let end: Date
  public let cpuSeconds: Double?
  public let peakMemoryMB: Double?
  public let backgroundCPUExits: Int?
  public let appVersion: String?
  public let includesMultipleVersions: Bool?
  public init(start: Date, end: Date, cpuSeconds: Double?, peakMemoryMB: Double?,
    backgroundCPUExits: Int? = nil, appVersion: String? = nil, includesMultipleVersions: Bool? = nil) {
    self.start = start; self.end = end; self.cpuSeconds = cpuSeconds; self.peakMemoryMB = peakMemoryMB
    self.backgroundCPUExits = backgroundCPUExits; self.appVersion = appVersion
    self.includesMultipleVersions = includesMultipleVersions
  }
  public var valid: Bool {
    Int(exactly: floor(start.timeIntervalSince1970)) != nil
      && Int(exactly: floor(end.timeIntervalSince1970)) != nil && start < end
      && (backgroundCPUExits.map { $0 >= 0 } ?? true)
      && [cpuSeconds,peakMemoryMB].allSatisfy { $0.map { $0.isFinite && $0 >= 0 && Int(exactly: floor($0)) != nil } ?? true }
  }
}
public struct ReliabilityArchive: Codable, Sendable {
  public private(set) var reports: [ReliabilityReport] = []
  public init() {}
  public mutating func record(_ report: ReliabilityReport) {
    guard report.valid else { return }
    reports.removeAll { $0.id == report.id }
    reports.append(report)
    reports.sort { $0.end > $1.end }
    reports = Array(reports.prefix(7))
  }
  public mutating func clear() { reports = [] }
}
