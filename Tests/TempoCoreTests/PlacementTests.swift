import XCTest

@testable import TempoCore

final class PlacementTests: XCTestCase {
  let t = Date(timeIntervalSince1970: 1_800_000_000)
  func testChangesApplyForwardAndStaySeparateByBand() {
    let a = UUID()
    let b = UUID()
    let records = [
      PlacementRecord(deviceID: a, placement: .wrist, effectiveFrom: t),
      PlacementRecord(deviceID: a, placement: .upperArm, effectiveFrom: t.addingTimeInterval(60)),
      PlacementRecord(deviceID: b, placement: .underwear, effectiveFrom: t),
    ]
    XCTAssertEqual(
      PlacementTimeline.resolve(deviceID: a, at: t.addingTimeInterval(-1), records: records),
      .unknown)
    XCTAssertEqual(
      PlacementTimeline.resolve(deviceID: a, at: t.addingTimeInterval(59), records: records), .wrist
    )
    XCTAssertEqual(
      PlacementTimeline.resolve(deviceID: a, at: t.addingTimeInterval(60), records: records),
      .upperArm)
    XCTAssertEqual(
      PlacementTimeline.resolve(deviceID: b, at: t.addingTimeInterval(60), records: records),
      .underwear)
  }
  func testAmbiguousSimultaneousReportsStayUnknown() {
    let id = UUID()
    let records = [
      PlacementRecord(deviceID: id, placement: .wrist, effectiveFrom: t),
      PlacementRecord(deviceID: id, placement: .underwear, effectiveFrom: t),
    ]
    XCTAssertEqual(PlacementTimeline.resolve(deviceID: id, at: t, records: records), .unknown)
  }
  func testPlacementRevisionsSurviveIdempotentRestoreWithoutChangingMeasurements() async throws {
    let store = try TempoStore(path: ":memory:")
    let record = PlacementRecord(deviceID: UUID(), placement: .underwear, effectiveFrom: t)
    let measurement = Measurement(
      deviceID: record.deviceID, kind: .heartRate, timestamp: t, value: 70, origin: .measured,
      transport: "fixture")
    try await store.insert([measurement])
    try await store.saveRevision(
      Revision(
        entityID: record.id, kind: "placement", parentIDs: [], payload: JSONEncoder().encode(record)
      ))
    let archive = try await store.exportArchive()
    let copy = try TempoStore(path: ":memory:")
    try await copy.importArchive(archive)
    try await copy.importArchive(archive)
    let restored = try await copy.revisions(kind: "placement")
    XCTAssertEqual(restored.count, 1)
    XCTAssertEqual(
      try JSONDecoder().decode(PlacementRecord.self, from: restored[0].payload), record)
    let samples = try await copy.measurements(from: t, to: t.addingTimeInterval(1))
    XCTAssertEqual(samples, [measurement])
  }
  func testLocationChangeLowersConfidenceButDoesNotAdjustPhysiologicalValues() {
    let history = (0..<21).map {
      PersonalBaseline(
        date: t.addingTimeInterval(Double($0) * 86400), values: ["rhr": 60, "sleepHours": 8])
    }
    let normal = Readiness.calculate(current: ["rhr": 60, "sleepHours": 8], baseline: history)
    let changed = Readiness.calculate(
      current: ["rhr": 60, "sleepHours": 8], baseline: history, placementChange: true)
    XCTAssertEqual(normal.score, changed.score)
    XCTAssertEqual(normal.baselineDays, changed.baselineDays)
    XCTAssertLessThan(changed.confidence, normal.confidence)
    XCTAssertTrue(changed.factors.contains(where: { $0.contains("placement") }))
  }
}

extension PlacementTests {
  func testConflictedEditCreatesUnknownBoundaryInsteadOfRevivingOldPlacement() throws {
    let device = UUID()
    let old = PlacementRecord(deviceID: device, placement: .wrist, effectiveFrom: t)
    let report = PlacementRecord(
      deviceID: device, placement: .upperArm, effectiveFrom: t.addingTimeInterval(60))
    let first = Revision(
      entityID: old.id, kind: "placement", parentIDs: [], payload: try JSONEncoder().encode(old))
    let base = Revision(
      entityID: report.id, kind: "placement", parentIDs: [],
      payload: try JSONEncoder().encode(report))
    var a = report
    a.placement = .wrist
    a.effectiveFrom = t.addingTimeInterval(90)
    var b = report
    b.placement = .underwear
    let left = Revision(
      entityID: report.id, kind: "placement", parentIDs: [base.id],
      payload: try JSONEncoder().encode(a))
    let right = Revision(
      entityID: report.id, kind: "placement", parentIDs: [base.id],
      payload: try JSONEncoder().encode(b))
    let projected = PlacementTimeline.project([first, base, left, right])
    XCTAssertEqual(
      PlacementTimeline.resolve(deviceID: device, at: t.addingTimeInterval(59), records: projected),
      .wrist)
    XCTAssertEqual(
      PlacementTimeline.resolve(deviceID: device, at: t.addingTimeInterval(70), records: projected),
      .unknown)
    XCTAssertEqual(
      PlacementTimeline.resolve(
        deviceID: device, at: t.addingTimeInterval(100), records: projected), .unknown)
  }
}

extension PlacementTests {
  func testInterveningReportDoesNotMaskConflictingMovedTimestamps() throws {
    let device = UUID()
    let original = PlacementRecord(deviceID: device, placement: .wrist, effectiveFrom: t)
    let base = Revision(
      entityID: original.id, kind: "placement", parentIDs: [],
      payload: try JSONEncoder().encode(original))
    var left = original
    left.effectiveFrom = t.addingTimeInterval(120)
    var right = original
    right.effectiveFrom = t.addingTimeInterval(180)
    right.placement = .underwear
    let middle = PlacementRecord(
      deviceID: device, placement: .upperArm, effectiveFrom: t.addingTimeInterval(60))
    let later = PlacementRecord(
      deviceID: device, placement: .wrist, effectiveFrom: t.addingTimeInterval(240))
    let revisions = [
      base,
      Revision(
        entityID: original.id, kind: "placement", parentIDs: [base.id],
        payload: try JSONEncoder().encode(left)),
      Revision(
        entityID: original.id, kind: "placement", parentIDs: [base.id],
        payload: try JSONEncoder().encode(right)),
      Revision(
        entityID: middle.id, kind: "placement", parentIDs: [],
        payload: try JSONEncoder().encode(middle)),
      Revision(
        entityID: later.id, kind: "placement", parentIDs: [],
        payload: try JSONEncoder().encode(later)),
    ]
    let records = PlacementTimeline.project(revisions)
    XCTAssertEqual(
      PlacementTimeline.resolve(deviceID: device, at: t.addingTimeInterval(70), records: records),
      .upperArm)
    XCTAssertEqual(
      PlacementTimeline.resolve(deviceID: device, at: t.addingTimeInterval(130), records: records),
      .unknown)
    XCTAssertEqual(
      PlacementTimeline.resolve(deviceID: device, at: t.addingTimeInterval(190), records: records),
      .unknown)
    XCTAssertEqual(
      PlacementTimeline.resolve(deviceID: device, at: t.addingTimeInterval(250), records: records),
      .wrist)
  }
}
