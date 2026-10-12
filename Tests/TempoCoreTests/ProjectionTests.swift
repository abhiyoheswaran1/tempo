import XCTest

@testable import TempoCore

final class ProjectionTests: XCTestCase, @unchecked Sendable {
  func testReconstructedImportRevisionIsIdempotent() async throws {
    let store = try TempoStore(path: ":memory:")
    let id = UUID()
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    for _ in 0..<2 {
      try await store.saveRevision(
        Revision(
          id: id, entityID: id, kind: "sleep", parentIDs: [], payload: Data([1]), createdAt: date))
    }
    let count = try await store.revisions().count
    XCTAssertEqual(count, 1)
  }
  func testDeletionSurvivesReadAndBackupRestore() async throws {
    let store = try TempoStore(path: ":memory:")
    let m = TempoCore.Measurement(
      deviceID: UUID(), kind: .heartRate, timestamp: Date(), value: 70, origin: .imported,
      transport: "healthkit", recordKey: "x")
    try await store.insert([m])
    try await store.saveRevision(
      Revision(
        entityID: UUID(), kind: "measurementDeletion", parentIDs: [], payload: Data(m.id.utf8),
        deleted: true))
    let records = try await store.measurements(from: .distantPast, to: .distantFuture)
    XCTAssertTrue(records.isEmpty)
    let other = try TempoStore(path: ":memory:")
    try await other.importArchive(store.exportArchive())
    let restored = try await other.measurements(from: .distantPast, to: .distantFuture)
    XCTAssertTrue(restored.isEmpty)
  }
  func testLatestSourceTransitionWinsAfterReload() {
    let a = UUID()
    let b = UUID()
    let t = Date()
    let segments = [
      SourceSegment(deviceID: a, start: t, end: nil, reason: "initial"),
      SourceSegment(deviceID: b, start: t.addingTimeInterval(10), end: nil, reason: "switch"),
    ]
    let samples = [a, b].map {
      TempoCore.Measurement(
        deviceID: $0, kind: .heartRate, timestamp: t.addingTimeInterval(15), value: 70,
        origin: .measured, transport: "hr")
    }
    XCTAssertEqual(CanonicalTimeline.select(samples, sourceSegments: segments).first?.deviceID, b)
  }
  func testSleepOverlapAndWorkoutImportDoNotDoubleCount() {
    let t = Date()
    let a = SleepSession(
      start: t, end: t.addingTimeInterval(8 * 3600), timeZoneID: "UTC", origin: .manual)
    let b = SleepSession(
      start: t, end: t.addingTimeInterval(8 * 3600), timeZoneID: "UTC", origin: .imported)
    XCTAssertEqual(SessionReconciliation.sleep([a, b]).count, 1)
    var w = Workout(activity: .running, start: t)
    w.end = t.addingTimeInterval(3600)
    var imported = w
    imported.id = UUID()
    imported.origin = .imported
    XCTAssertEqual(SessionReconciliation.workouts([w, imported]).count, 1)
  }
}

extension ProjectionTests {
  func testHealthIdentityCanBeFoundAfterBackupRestore() async throws {
    let store = try TempoStore(path: ":memory:")
    let m = TempoCore.Measurement(
      deviceID: UUID(), kind: .heartRate, timestamp: Date(), value: 70, origin: .imported,
      transport: "healthkit:test", recordKey: "health-sample-uuid")
    try await store.insert([m])
    let archive = try await store.exportArchive()
    let other = try TempoStore(path: ":memory:")
    try await other.importArchive(archive)
    let found = try await other.observations(externalID: "health-sample-uuid")
    XCTAssertEqual(found.map(\.id), [m.id])
  }
  func testStaleLocalEditCannotSupersedeNewerRevision() async throws {
    let store = try TempoStore(path: ":memory:")
    let id = UUID()
    let a = Revision(entityID: id, kind: "workout", parentIDs: [], payload: Data([1]))
    try await store.saveRevision(a)
    let b = Revision(entityID: id, kind: "workout", parentIDs: [a.id], payload: Data([2]))
    try await store.saveRevision(b, expectedParentIDs: [a.id])
    let stale = Revision(entityID: id, kind: "workout", parentIDs: [a.id], payload: Data([3]))
    do {
      try await store.saveRevision(stale, expectedParentIDs: [a.id])
      XCTFail("Stale edit must be refused")
    } catch {}
    let heads = try await store.revisionHeads(entityID: id)
    XCTAssertEqual(heads.map(\.id), [b.id])
  }
}
