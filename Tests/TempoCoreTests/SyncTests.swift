import XCTest

@testable import TempoCore

final class SyncTests: XCTestCase, @unchecked Sendable {
  func testSampleDuringUploadKeepsBatchDirty() async throws {
    let store = try TempoStore(path: ":memory:")
    let id = UUID()
    let a = TempoCore.Measurement(
      deviceID: id, kind: .heartRate, timestamp: Date(timeIntervalSince1970: 1_700_000_000),
      value: 70, origin: .measured, transport: "hrs")
    let b = TempoCore.Measurement(
      deviceID: id, kind: .heartRate, timestamp: Date(timeIntervalSince1970: 1_700_000_001),
      value: 71, origin: .measured, transport: "hrs")
    try await store.insert([a])
    let pending = try await store.pending()[0]
    try await store.insert([b])
    try await store.acknowledge(pending.id, expectedPayload: pending.envelope.payload)
    let count = try await store.pendingCount()
    XCTAssertEqual(count, 1)
  }
  func testBackoffKeepsDurableChanges() async throws {
    let store = try TempoStore(path: ":memory:")
    let r = Revision(entityID: UUID(), kind: "journal", parentIDs: [], payload: Data([1]))
    try await store.saveRevision(r)
    let p = try await store.pending()[0]
    try await store.deferChange(p.id, attempt: 3, retryAfter: 3600)
    let ready = try await store.pending()
    let count = try await store.pendingCount()
    XCTAssertTrue(ready.isEmpty)
    XCTAssertEqual(count, 1)
  }
}

extension SyncTests {
  func testNormalDatabaseRejectsSyntheticMeasurements() async throws {
    let store = try TempoStore(path: ":memory:")
    let m = TempoCore.Measurement(
      deviceID: UUID(), kind: .heartRate, timestamp: Date(), value: 70, origin: .synthetic,
      transport: "demo")
    do {
      try await store.insert([m])
      XCTFail("Synthetic data must be rejected by a normal store")
    } catch {}
  }
}
