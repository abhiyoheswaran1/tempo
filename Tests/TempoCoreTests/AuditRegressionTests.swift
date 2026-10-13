import XCTest
@testable import TempoCore

final class AuditRegressionTests: XCTestCase, @unchecked Sendable {
  private let start = Date(timeIntervalSince1970: 1_700_000_000)
  private func sample(_ kind: MetricKind, seconds: Double) -> TempoCore.Measurement {
    Measurement(deviceID: UUID(), kind: kind, timestamp: start.addingTimeInterval(seconds),
      value: 70, origin: .measured, transport: "audit-fixture")
  }
  func testRequestedMetricIsFilteredBeforeLimit() async throws {
    let store = try TempoStore(path: ":memory:")
    let resting = sample(.restingHeartRate, seconds: 0)
    try await store.insert([resting, sample(.heartRate, seconds: 1), sample(.heartRate, seconds: 2)])
    let result = try await store.measurements(from: start, to: start.addingTimeInterval(3), kinds: [.restingHeartRate], limit: 1)
    XCTAssertEqual(result.map(\.id), [resting.id])
  }
  func testDeletedNewestRecordDoesNotConsumeVisibleLimit() async throws {
    let store = try TempoStore(path: ":memory:")
    let older = sample(.heartRate, seconds: 0)
    let newer = sample(.heartRate, seconds: 1)
    try await store.insert([older, newer])
    try await store.saveRevision(Revision(entityID: UUID(), kind: "measurementDeletion", parentIDs: [], payload: Data(newer.id.utf8), deleted: true))
    let result = try await store.measurements(from: start, to: start.addingTimeInterval(3), limit: 1)
    XCTAssertEqual(result.map(\.id), [older.id])
  }
  func testRequeuedChangeStartsWithFreshRetryBudget() async throws {
    let store = try TempoStore(path: ":memory:")
    let original = sample(.heartRate, seconds: 0)
    try await store.insert([original])
    let queued = try await store.pending().first!
    try await store.deferChange(queued.id, attempt: 8, retryAfter: 3600)
    var next = original
    next.timestamp = original.timestamp.addingTimeInterval(1)
    next.id = StableID.hash("another observation same bucket")
    try await store.insert([next])
    let refreshed = try await store.pending().first!
    XCTAssertEqual(refreshed.id, queued.id)
    XCTAssertEqual(refreshed.attempts, 0)
  }
  func testBackwardWorkoutSwitchDoesNotCreateNegativeSourceSegment() {
    var workout = Workout(activity: .padel, start: start)
    let first = UUID()
    workout.switchSource(to: first, at: start.addingTimeInterval(60))
    workout.switchSource(to: UUID(), at: start.addingTimeInterval(30))
    XCTAssertEqual(workout.sources.count, 1)
    XCTAssertNil(workout.sources.first?.end)
  }
  func testFinishBeforeLatestSourceDoesNotCreateInvalidWorkout() {
    var workout = Workout(activity: .cycling, start: start)
    workout.switchSource(to: UUID(), at: start.addingTimeInterval(60))
    workout.finish(at: start.addingTimeInterval(30))
    XCTAssertNil(workout.end)
  }
  func testNonFiniteTimestampIsNotAValidObservation() {
    var reading = sample(.heartRate, seconds: 0)
    reading.timestamp = Date(timeIntervalSince1970: .nan)
    XCTAssertFalse(reading.valid)
  }

  func testExtremeTimestampRejectsWholeWriteBeforeBucketConversion() async throws {
    let store = try TempoStore(path: ":memory:")
    let good = sample(.heartRate, seconds: 0)
    var bad = good
    bad.id = StableID.hash("out-of-range timestamp")
    bad.timestamp = Date(timeIntervalSince1970: 1e30)
    do {
      try await store.insert([good, bad])
      XCTFail("Out-of-range dates must be rejected")
    } catch StoreError.invalidSample {} catch { XCTFail("Unexpected error: \(error)") }
    let remaining = try await store.measurements(from: start, to: start.addingTimeInterval(3))
    XCTAssertTrue(remaining.isEmpty, "The valid prefix must roll back with the invalid row")
  }

  func testDeletedNewestRecordDoesNotEmptyLiveChartWindow() async throws {
    let store = try TempoStore(path: ":memory:")
    let older = sample(.heartRate, seconds: 0)
    let newer = sample(.heartRate, seconds: 1)
    try await store.insert([older, newer])
    try await store.saveRevision(Revision(entityID: UUID(), kind: "measurementDeletion", parentIDs: [], payload: Data(newer.id.utf8), deleted: true))
    let window = try await store.liveHeartRateWindow(from: start, to: start.addingTimeInterval(3), limit: 1)
    XCTAssertEqual(window.samples.map(\.id), [older.id])
    XCTAssertFalse(window.truncated)
  }

  func testStaleUploadFailureCannotDeferReplacedManifest() async throws {
    let store = try TempoStore(path: ":memory:")
    let first = sample(.heartRate, seconds: 0)
    try await store.insert([first])
    let inFlight = try await store.pending().first!
    var second = first
    second.id = StableID.hash("new reading while upload is in flight")
    second.timestamp = first.timestamp.addingTimeInterval(1)
    try await store.insert([second])
    try await store.deferChange(inFlight.id, attempt: 8, retryAfter: 3600, expectedPayload: inFlight.envelope.payload)
    let current = try await store.pending(now: .distantFuture).first!
    XCTAssertEqual(current.attempts, 0)
    XCTAssertLessThanOrEqual(current.nextAttempt, Date())
  }

  func testVisibleLimitBackfillsAcrossQueryPageBoundary() async throws {
    let store = try TempoStore(path: ":memory:")
    let device = UUID()
    let rows = (0..<4100).map { index in
      TempoCore.Measurement(deviceID: device, kind: .heartRate,
        timestamp: start.addingTimeInterval(Double(index)), value: 70,
        origin: .measured, transport: "audit-page")
    }
    try await store.insert(rows)
    try await store.saveRevision(Revision(entityID: UUID(), kind: "measurementDeletion", parentIDs: [], payload: Data(rows.last!.id.utf8), deleted: true))
    let visible = try await store.measurements(from: start, to: start.addingTimeInterval(4101), limit: 4096)
    XCTAssertEqual(visible.count, 4096)
    XCTAssertEqual(visible.first?.id, rows[3].id)
    XCTAssertEqual(visible.last?.id, rows[4098].id)
  }
  func testLiveWindowStillReportsActualVisibleTruncation() async throws {
    let store = try TempoStore(path: ":memory:")
    try await store.insert([sample(.heartRate, seconds: 0), sample(.heartRate, seconds: 1)])
    let window = try await store.liveHeartRateWindow(from: start, to: start.addingTimeInterval(3), limit: 1)
    XCTAssertEqual(window.samples.count, 1)
    XCTAssertTrue(window.truncated)
  }
  func testFinishBeforePauseDoesNotCrashOrCloseSession() {
    var workout = Workout(activity: .running, start: start)
    workout.pause(at: start.addingTimeInterval(30))
    workout.finish(at: start.addingTimeInterval(20))
    XCTAssertNil(workout.end)
    XCTAssertTrue(workout.pauses.isEmpty)
    XCTAssertEqual(workout.pausedAt, start.addingTimeInterval(30))
  }
  func testSwitchBeforeClosedSourceEndIsRejected() {
    var workout = Workout(activity: .padel, start: start)
    let id = UUID()
    workout.switchSource(to: id, at: start)
    workout.closeSource(id, at: start.addingTimeInterval(60))
    workout.switchSource(to: UUID(), at: start.addingTimeInterval(30))
    XCTAssertEqual(workout.sources.count, 1)
    XCTAssertEqual(workout.sources.first?.end, start.addingTimeInterval(60))
  }

}
