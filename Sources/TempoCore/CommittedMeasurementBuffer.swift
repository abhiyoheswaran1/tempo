import Foundation

/// Coalesces presentation of observations already durably committed by the store.
/// This is not a persistence queue: losing it never loses stored measurements.
public struct CommittedMeasurementBuffer: Sendable {
  private var retained: [Measurement] = []
  private var pending: [Measurement] = []
  private var deletedIDs = Set<String>()
  private let windowSeconds: Double
  public let publicationThreshold: Int
  public var pendingCount: Int { pending.count }
  public init(windowSeconds: Double = 2 * 86400, publicationThreshold: Int = 4096) {
    self.windowSeconds = windowSeconds.isFinite && windowSeconds > 0 ? windowSeconds : 2 * 86400
    self.publicationThreshold = max(1, publicationThreshold)
  }
  public mutating func reset(_ records: [Measurement] = []) {
    retained = unique(records).sorted(by: ordered)
    pending.removeAll(keepingCapacity: false)
    deletedIDs.removeAll(keepingCapacity: false)
  }
  /// Reconcile a same-dataset database refresh with receipts committed while its read was in flight.
  /// Explicit tombstones are applied to every source before presentation, so deleted rows stay hidden.
  public mutating func refresh(_ records: [Measurement], excluding deletedIDs: Set<String>, at now: Date) -> [Measurement] {
    let tombstones = self.deletedIDs.union(deletedIDs)
    let combined = records + retained + pending
    reset(combined.filter { !tombstones.contains($0.id) })
    self.deletedIDs = tombstones
    return publish(at: now)
  }
  @discardableResult public mutating func append(_ records: [Measurement]) -> Bool {
    pending.append(contentsOf: records.filter { !deletedIDs.contains($0.id) })
    return pending.count >= publicationThreshold
  }
  public mutating func publish(at now: Date) -> [Measurement] {
    let cutoff = now.addingTimeInterval(-windowSeconds)
    // Retained observations are chronological, so pruning visits only the expired prefix.
    let first = retained.firstIndex { $0.timestamp >= cutoff } ?? retained.endIndex
    if first > retained.startIndex { retained.removeFirst(first) }
    let incoming = unique(pending.filter { $0.timestamp >= cutoff }).sorted(by: ordered)
    pending.removeAll(keepingCapacity: true)
    if let oldest = incoming.first, retained.last.map({ $0.timestamp < oldest.timestamp }) ?? true {
      // Ordinary live receipt appends without hashing/scanning the full retained window.
      retained.append(contentsOf: incoming)
    } else if !incoming.isEmpty {
      var ids = Set(retained.map(\.id))
      retained.append(contentsOf: incoming.filter { ids.insert($0.id).inserted })
      retained.sort(by: ordered)
    }
    return retained
  }
  private func unique(_ records: [Measurement]) -> [Measurement] {
    var ids = Set<String>()
    return records.filter { ids.insert($0.id).inserted }
  }
  private func ordered(_ a: Measurement, _ b: Measurement) -> Bool {
    a.timestamp == b.timestamp ? a.id < b.id : a.timestamp < b.timestamp
  }
}
