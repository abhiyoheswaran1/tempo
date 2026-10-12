import XCTest

@testable import TempoCore

final class IntegrityTests: XCTestCase, @unchecked Sendable {
  func sample(_ device: UUID, _ t: Double = 1_700_000_000, _ value: Double = 70)
    -> TempoCore.Measurement
  {
    Measurement(
      deviceID: device, kind: .heartRate, timestamp: Date(timeIntervalSince1970: t), value: value,
      origin: .measured, transport: "history-v24", recordKey: "record-\(t)")
  }
  func testDuplicateHistoryAndAtomicCheckpoint() async throws {
    let store = try TempoStore(path: ":memory:")
    let id = UUID()
    let m = sample(id)
    try await store.commitHistory(deviceID: id, samples: [m, m], cursor: Data([1, 2, 3]))
    try await store.commitHistory(deviceID: id, samples: [m], cursor: Data([1, 2, 3]))
    let measurements = try await store.measurements(from: .distantPast, to: .distantFuture)
    let cursor = try await store.checkpoint(deviceID: id)
    XCTAssertEqual(measurements.count, 1)
    XCTAssertEqual(cursor, Data([1, 2, 3]))
  }
  func testInvalidWriteDoesNotAdvanceCursor() async throws {
    let store = try TempoStore(path: ":memory:")
    let id = UUID()
    do {
      try await store.commitHistory(
        deviceID: id, samples: [sample(id, 1_700_000_000, .nan)], cursor: Data([2]))
      XCTFail("must reject")
    } catch {}
    let cursor = try await store.checkpoint(deviceID: id)
    XCTAssertNil(cursor)
  }
  func testOverlapDoesNotDoubleCount() {
    let a = UUID()
    let b = UUID()
    let t = Date(timeIntervalSince1970: 1_700_000_000)
    let samples = [sample(a), sample(b, 1_700_000_000, 80)]
    XCTAssertEqual(
      CanonicalTimeline.select(
        samples,
        sourceSegments: [
          SourceSegment(deviceID: a, start: t.addingTimeInterval(-1), end: nil, reason: "active")
        ]
      ).map(\.deviceID), [a])
  }
  func testChargingBandDoesNotReplaceValidActive() {
    let a = UUID()
    let b = UUID()
    let now = Date()
    var selector = SourceSelector()
    let worn = DeviceEvidence(
      deviceID: a, generation: .whoop4, connected: true, lastValidSample: now, wear: .onBody)
    let charging = DeviceEvidence(
      deviceID: b, generation: .whoop5, connected: true, lastValidSample: now, wear: .offBody)
    XCTAssertEqual(selector.update([worn, charging], now: now)?.deviceID, a)
    XCTAssertNil(selector.update([worn, charging], now: now.addingTimeInterval(10)))
    XCTAssertEqual(selector.activeID, a)
  }
  func testHysteresisBriefDisconnectAndPreference() {
    let a = UUID()
    let b = UUID()
    let t = Date()
    var s = SourceSelector()
    let ea = DeviceEvidence(
      deviceID: a, generation: .whoop4, connected: true, lastValidSample: t, wear: .unknown)
    let eb = DeviceEvidence(
      deviceID: b, generation: .whoop5, connected: true, lastValidSample: t, wear: .unknown)
    _ = s.update([ea], now: t)
    XCTAssertNil(s.update([eb], now: t.addingTimeInterval(5)))
    s.preference = .prefer5
    _ = s.update([ea, eb], now: t.addingTimeInterval(10))
    XCTAssertEqual(s.update([ea, eb], now: t.addingTimeInterval(45))?.deviceID, b)
  }
  func testAccountChangeBlocksHistoryTransfer() {
    var gate = AccountGate()
    XCTAssertTrue(gate.bind("apple-a"))
    XCTAssertFalse(gate.bind("apple-b"))
    XCTAssertTrue(gate.bind("apple-a"))
  }
  func testBackupChecksumAndIdempotentRestore() async throws {
    let store = try TempoStore(path: ":memory:")
    try await store.insert([sample(UUID())])
    let export = try await store.exportArchive()
    let other = try TempoStore(path: ":memory:")
    try await other.importArchive(export)
    try await other.importArchive(export)
    let records = try await other.measurements(from: .distantPast, to: .distantFuture)
    XCTAssertEqual(records.count, 1)
    var bad = export
    bad.checksum = "bad"
    do {
      try await other.importArchive(bad)
      XCTFail("corrupt")
    } catch {}
  }
  func testConcurrentCorrectionsArePreserved() async throws {
    let store = try TempoStore(path: ":memory:")
    let id = UUID()
    let a = Revision(entityID: id, kind: "sleep", parentIDs: [], payload: Data("a".utf8))
    let b = Revision(entityID: id, kind: "sleep", parentIDs: [], payload: Data("b".utf8))
    try await store.saveRevision(a)
    try await store.saveRevision(b)
    let heads = try await store.revisionHeads(entityID: id)
    XCTAssertEqual(heads.count, 2)
  }
}
