import XCTest

@testable import TempoCore

final class BugRegressionTests: XCTestCase, @unchecked Sendable {
  let t = Date(timeIntervalSince1970: 1_700_000_000)
  func readings(_ id: UUID, value: Double, rr: Bool = false) -> [TempoCore.Measurement] {
    (0..<300).map { i in
      Measurement(
        deviceID: id, kind: .heartRate, timestamp: t.addingTimeInterval(Double(i)), value: value,
        origin: .measured, transport: "fixture",
        rrMilliseconds: rr && (i < 120 || i >= 180) ? [800, 820] : [])
    }
  }
  func testNightCacheChangesWhenSameCountSourceSegmentsAreCorrected() async throws {
    let store = try TempoStore(path: ":memory:")
    let a = UUID()
    let b = UUID()
    try await store.insert(readings(a, value: 60) + readings(b, value: 90))
    let sleep = SleepSession(
      start: t, end: t.addingTimeInterval(300), timeZoneID: "UTC", origin: .manual)
    let first = try await store.nightInputs(
      sleep, sourceSegments: [SourceSegment(deviceID: a, start: t, end: nil, reason: "selected")])
    let corrected = try await store.nightInputs(
      sleep, sourceSegments: [SourceSegment(deviceID: b, start: t, end: nil, reason: "corrected")])
    XCTAssertEqual(first["rhr"], 60)
    XCTAssertEqual(corrected["rhr"], 90)
  }
  func testHRVDoesNotJoinRRAcrossMissingIntervals() async throws {
    let store = try TempoStore(path: ":memory:")
    try await store.insert(readings(UUID(), value: 70, rr: true))
    let sleep = SleepSession(
      start: t, end: t.addingTimeInterval(300), timeZoneID: "UTC", origin: .manual)
    let inputs = try await store.nightInputs(sleep, sourceSegments: [])
    XCTAssertNil(
      inputs["rmssd"], "Each RR run has only 120 seconds; missing RR must break overnight coverage")
  }
  func testShortWorkoutPauseIsSubtractedBetweenSamples() {
    let id = UUID()
    let samples = [0.0, 8.0].map {
      Measurement(
        deviceID: id, kind: .heartRate, timestamp: t.addingTimeInterval($0), value: 140,
        origin: .measured, transport: "fixture")
    }
    var workout = Workout(activity: .running, start: t)
    workout.pause(at: t.addingTimeInterval(1))
    workout.resume(at: t.addingTimeInterval(2))
    workout.finish(at: t.addingTimeInterval(8))
    let result = CardiovascularLoad.calculate(samples, maxHeartRate: 200, workout: workout)
    XCTAssertEqual(result?.coveredSeconds ?? -1, 7, accuracy: 0.001)
  }
}

extension BugRegressionTests {
  func testRecoveryResubscribesThenReconnectsSilentStreamWithCooldown() {
    var recovery = CollectionRecovery()
    XCTAssertEqual(
      recovery.check(now: t, subscribedAt: t, lastNotification: nil, offBody: false), .none)
    XCTAssertEqual(
      recovery.check(
        now: t.addingTimeInterval(91), subscribedAt: t, lastNotification: t, offBody: false),
      .resubscribe)
    XCTAssertEqual(
      recovery.check(
        now: t.addingTimeInterval(100), subscribedAt: t, lastNotification: t, offBody: false), .none
    )
    XCTAssertEqual(
      recovery.check(
        now: t.addingTimeInterval(107), subscribedAt: t, lastNotification: t, offBody: false),
      .reconnect)
    XCTAssertEqual(
      recovery.check(
        now: t.addingTimeInterval(120), subscribedAt: t, lastNotification: t, offBody: false), .none
    )
  }
  func testNewConnectionGraceOffBodyAndReceiptCancelRecovery() {
    var recovery = CollectionRecovery()
    XCTAssertEqual(
      recovery.check(
        now: t.addingTimeInterval(20), subscribedAt: t, lastNotification: nil, offBody: false),
      .none)
    XCTAssertEqual(
      recovery.check(
        now: t.addingTimeInterval(100), subscribedAt: t, lastNotification: nil, offBody: true),
      .none)
    XCTAssertEqual(
      recovery.check(
        now: t.addingTimeInterval(100), subscribedAt: t, lastNotification: nil, offBody: false),
      .resubscribe)
    recovery.received()
    XCTAssertEqual(
      recovery.check(
        now: t.addingTimeInterval(120), subscribedAt: t,
        lastNotification: t.addingTimeInterval(119), offBody: false), .none)
  }
  func testConnectionRetriesAreBoundedAndRespectUserPause() {
    var retry = ConnectionRetry()
    XCTAssertNil(retry.nextDelay(allowed: false))
    XCTAssertEqual(
      (0..<6).compactMap { _ in retry.nextDelay(allowed: true) }, [2, 4, 8, 16, 30, 60])
    XCTAssertNil(retry.nextDelay(allowed: true))
    retry.reset()
    XCTAssertEqual(retry.nextDelay(allowed: true), 2)
  }
  func testScanRequestSurvivesCentralInitializationButNotCancel() {
    var intent = ScanIntent()
    intent.request()
    XCTAssertFalse(intent.consume(poweredOn: false, allowed: true))
    XCTAssertTrue(intent.consume(poweredOn: true, allowed: true))
    XCTAssertFalse(intent.consume(poweredOn: true, allowed: true))
    intent.request()
    intent.cancel()
    XCTAssertFalse(intent.consume(poweredOn: true, allowed: true))
  }
}

extension BugRegressionTests {
  func testContinuousRRCoverageStillProducesOvernightHRV() async throws {
    let store = try TempoStore(path: ":memory:")
    let samples = readings(UUID(), value: 70).map { original in
      var sample = original
      sample.rrMilliseconds = [800, 820]
      return sample
    }
    try await store.insert(samples)
    let sleep = SleepSession(
      start: t, end: t.addingTimeInterval(300), timeZoneID: "UTC", origin: .manual)
    let inputs = try await store.nightInputs(sleep, sourceSegments: [])
    XCTAssertEqual(inputs["rmssd"] ?? -1, 20, accuracy: 0.001)
  }
  func testLoadUsesIntervalsAdjacentToPauseAndClipsWorkoutBounds() {
    let samples = [0.0, 3.0, 6.0, 9.0].map {
      Measurement(
        deviceID: UUID(), kind: .heartRate, timestamp: t.addingTimeInterval($0), value: 140,
        origin: .measured, transport: "fixture")
    }
    var workout = Workout(activity: .running, start: t.addingTimeInterval(1))
    workout.pause(at: t.addingTimeInterval(2))
    workout.resume(at: t.addingTimeInterval(7))
    workout.finish(at: t.addingTimeInterval(8))
    let result = CardiovascularLoad.calculate(samples, maxHeartRate: 200, workout: workout)
    XCTAssertEqual(result?.coveredSeconds ?? -1, 2, accuracy: 0.001)
  }
}
