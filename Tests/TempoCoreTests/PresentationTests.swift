import XCTest

@testable import TempoCore

final class PresentationTests: XCTestCase {
  func testEvidenceCategoriesDoNotImplyCalibratedProbability() {
    XCTAssertEqual(EvidenceLevel(confidence: 0).title, "Building baseline")
    XCTAssertEqual(EvidenceLevel(confidence: 0.3).title, "Limited evidence")
    XCTAssertEqual(EvidenceLevel(confidence: 0.65).title, "Developing evidence")
    XCTAssertEqual(EvidenceLevel(confidence: 0.9).title, "Strong evidence")
    XCTAssertEqual(EvidenceLevel(confidence: .nan).title, "Building baseline")
  }
  func testSleepSummaryExcludesNapsAndLabelsOlderNights() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Zurich")!
    let now = Date(timeIntervalSince1970: 1_800_036_000)
    var nap = SleepSession(
      start: now.addingTimeInterval(-3600), end: now, timeZoneID: "Europe/Zurich", origin: .manual)
    nap.isNap = true
    let older = SleepSession(
      start: now.addingTimeInterval(-3 * 86400 - 8 * 3600), end: now.addingTimeInterval(-3 * 86400),
      timeZoneID: "Europe/Zurich", origin: .manual)
    let summary = SleepPresentation(sessions: [nap, older], now: now, calendar: calendar)
    XCTAssertEqual(summary.session?.id, older.id)
    XCTAssertEqual(summary.title, "Latest sleep")
    XCTAssertNotEqual(summary.title, "Last night")
  }
  func testFreshnessRejectsFutureAndStaleSamples() {
    let now = Date()
    XCTAssertEqual(SampleFreshness(timestamp: nil, now: now), .missing)
    XCTAssertEqual(SampleFreshness(timestamp: now.addingTimeInterval(30), now: now), .stale)
    XCTAssertEqual(SampleFreshness(timestamp: now.addingTimeInterval(-91), now: now), .stale)
    XCTAssertEqual(SampleFreshness(timestamp: now.addingTimeInterval(-10), now: now), .fresh)
  }
}

extension PresentationTests {
  func testLiveSampleCannotComeFromWeightImportedHistoryOrOtherSelectedBand() {
    let now = Date()
    let selected = UUID()
    let other = UUID()
    let hr = Measurement(
      deviceID: selected, kind: .heartRate, timestamp: now.addingTimeInterval(-10), value: 80,
      origin: .measured, transport: "ble")
    let weight = Measurement(
      deviceID: selected, kind: .weight, timestamp: now, value: 70, origin: .imported,
      transport: "health")
    let imported = Measurement(
      deviceID: selected, kind: .heartRate, timestamp: now, value: 95, origin: .imported,
      transport: "health")
    let wrong = Measurement(
      deviceID: other, kind: .heartRate, timestamp: now, value: 110, origin: .measured,
      transport: "ble")
    XCTAssertEqual(
      LiveSampleSelection.latest(
        [hr, weight, imported, wrong], selectedDeviceID: selected, now: now)?.id, hr.id)
  }
}

extension PresentationTests {
  func testOldSleepCannotSupplyCurrentReadinessAndNapsCannotReplaceIt() {
    let now = Date()
    let old = SleepSession(
      start: now.addingTimeInterval(-80 * 3600), end: now.addingTimeInterval(-72 * 3600),
      timeZoneID: "UTC", origin: .manual)
    XCTAssertNil(SleepPresentation(sessions: [old], now: now).readinessSession)
    let recent = SleepSession(
      start: now.addingTimeInterval(-10 * 3600), end: now.addingTimeInterval(-2 * 3600),
      timeZoneID: "UTC", origin: .manual)
    var nap = SleepSession(
      start: now.addingTimeInterval(-3600), end: now, timeZoneID: "UTC", origin: .manual)
    nap.isNap = true
    XCTAssertEqual(
      SleepPresentation(sessions: [nap, recent, old], now: now).readinessSession?.id, recent.id)
  }
}

extension PresentationTests {
  func testManualRefreshNeverClaimsOldCloudSuccessAsNewSync() {
    let now = Date()
    XCTAssertEqual(
      ManualRefreshOutcome.resolve(
        demo: false, cloudEnabled: true, cloudBusy: false, cloudError: nil, pending: 0,
        lastSuccess: now.addingTimeInterval(-10), startedAt: now), .retryScheduled)
    XCTAssertEqual(
      ManualRefreshOutcome.resolve(
        demo: false, cloudEnabled: true, cloudBusy: false, cloudError: nil, pending: 0,
        lastSuccess: now.addingTimeInterval(1), startedAt: now), .synced)
    XCTAssertEqual(
      ManualRefreshOutcome.resolve(
        demo: false, cloudEnabled: true, cloudBusy: false, cloudError: "offline", pending: 0,
        lastSuccess: now.addingTimeInterval(1), startedAt: now), .needsAttention)
    XCTAssertEqual(
      ManualRefreshOutcome.resolve(
        demo: true, cloudEnabled: true, cloudBusy: false, cloudError: nil, pending: 0,
        lastSuccess: now.addingTimeInterval(1), startedAt: now), .demo)
    XCTAssertEqual(
      ManualRefreshOutcome.resolve(
        demo: false, cloudEnabled: false, cloudBusy: false, cloudError: nil, pending: 4,
        lastSuccess: nil, startedAt: now), .localOnly)
  }
}

extension PresentationTests {
  func testWorkoutHeartRateRejectsStaleImportedAndOffBodyAsLive() {
    let now = Date()
    let id = UUID()
    var sample = Measurement(
      deviceID: id, kind: .heartRate, timestamp: now, value: 126, origin: .measured,
      transport: "fixture")
    let live = WorkoutLiveReading(
      sample: sample, connected: true, wear: .onBody, now: now, maximumHeartRate: 180)
    XCTAssertEqual(live.state, .live)
    XCTAssertEqual(live.bpm, 126)
    XCTAssertEqual(live.zone, 3)
    let disconnected = WorkoutLiveReading(
      sample: sample, connected: false, wear: .unknown, now: now, maximumHeartRate: 180)
    XCTAssertEqual(disconnected.state, .recent)
    XCTAssertNil(disconnected.zone)
    let offBody = WorkoutLiveReading(
      sample: sample, connected: true, wear: .offBody, now: now, maximumHeartRate: 180)
    XCTAssertNotEqual(offBody.state, .live)
    XCTAssertNil(offBody.zone)
    sample.timestamp = now.addingTimeInterval(-100)
    XCTAssertNil(
      WorkoutLiveReading(
        sample: sample, connected: true, wear: .onBody, now: now, maximumHeartRate: 180
      ).bpm)
    sample.timestamp = now
    sample.origin = .imported
    XCTAssertNil(
      WorkoutLiveReading(
        sample: sample, connected: true, wear: .onBody, now: now, maximumHeartRate: 180
      ).bpm)
  }
}
