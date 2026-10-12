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

extension PresentationTests {
  func testCollectionStatusCannotTreatConnectionOrOldPulseAsLive() {
    let now = Date()
    let id = UUID()
    var hr = Measurement(
      deviceID: id, kind: .heartRate, timestamp: now, value: 80,
      origin: .measured, transport: "fixture")
    XCTAssertEqual(
      CollectionPresentation(sample: nil, connected: true, wear: .unknown, now: now).state, .waiting
    )
    XCTAssertEqual(
      CollectionPresentation(sample: hr, connected: true, wear: .unknown, now: now).state, .live)
    XCTAssertEqual(
      CollectionPresentation(sample: hr, connected: true, wear: .offBody, now: now).state, .recent)
    XCTAssertEqual(
      CollectionPresentation(sample: hr, connected: false, wear: .onBody, now: now).state, .recent)
    hr.timestamp = now.addingTimeInterval(-60)
    XCTAssertEqual(
      CollectionPresentation(sample: hr, connected: true, wear: .onBody, now: now).state, .recent)
    hr.timestamp = now.addingTimeInterval(-100)
    XCTAssertEqual(
      CollectionPresentation(sample: hr, connected: true, wear: .onBody, now: now).state, .stale)
    XCTAssertNil(
      CollectionPresentation(sample: hr, connected: true, wear: .onBody, now: now).displayedBPM)
    hr.origin = .imported
    XCTAssertNil(
      CollectionPresentation(sample: hr, connected: true, wear: .onBody, now: now).sample)
  }
  func testTrendSelectionKeepsMissingLocalDayEmptyAcrossDST() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Zurich")!
    let formatter = ISO8601DateFormatter()
    let dates = [
      formatter.date(from: "2026-03-28T12:00:00Z")!, formatter.date(from: "2026-03-30T12:00:00Z")!,
    ]
    let missing = formatter.date(from: "2026-03-29T12:00:00Z")!
    XCTAssertNil(TrendSelection.index(at: missing, dates: dates, calendar: calendar))
    XCTAssertEqual(
      TrendSelection.index(at: dates[1].addingTimeInterval(3600), dates: dates, calendar: calendar),
      1)
    XCTAssertNil(TrendSelection.index(at: dates[0], dates: [], calendar: calendar))
  }
  func testLiveChartPreservesGapsAndOrdersSamples() {
    let now = Date()
    let id = UUID()
    let samples = [20.0, 0, 5].map { offset in
      Measurement(
        deviceID: id, kind: .heartRate, timestamp: now.addingTimeInterval(offset), value: 80,
        origin: .measured, transport: "fixture")
    }
    let points = LiveChartSeries.points(samples)
    XCTAssertEqual(
      points.map { $0.sample.timestamp },
      [now, now.addingTimeInterval(5), now.addingTimeInterval(20)])
    XCTAssertEqual(points.map { $0.segment }, [0, 0, 1])
  }
}

extension PresentationTests {
  func testTrendsReloadsForNewCollectionWindowWithoutReloadingEverySample() {
    let first = TrendRefreshIdentity(
      metric: "heartRate", days: 28, demo: false, generation: 1,
      latestSample: Date(timeIntervalSince1970: 120))
    let sameWindow = TrendRefreshIdentity(
      metric: "heartRate", days: 28, demo: false, generation: 1,
      latestSample: Date(timeIntervalSince1970: 240))
    let newWindow = TrendRefreshIdentity(
      metric: "heartRate", days: 28, demo: false, generation: 1,
      latestSample: Date(timeIntervalSince1970: 301))
    XCTAssertEqual(first, sameWindow)
    XCTAssertNotEqual(first, newWindow)
    XCTAssertNotEqual(
      first,
      TrendRefreshIdentity(
        metric: "heartRate", days: 28, demo: true,
        generation: 1, latestSample: Date(timeIntervalSince1970: 120)))
    XCTAssertNotEqual(
      first,
      TrendRefreshIdentity(
        metric: "heartRate", days: 28, demo: false,
        generation: 2, latestSample: Date(timeIntervalSince1970: 120)))
  }
}

extension PresentationTests {
  func testCollectionCannotPresentAnotherBandsPulseUnderConnectedSource() {
    let now = Date()
    let sample = Measurement(
      deviceID: UUID(), kind: .heartRate, timestamp: now, value: 80,
      origin: .measured, transport: "fixture")
    let reading = CollectionPresentation(
      sample: sample, connected: true, wear: .onBody,
      now: now, selectedDeviceID: UUID())
    XCTAssertEqual(reading.state, .waiting)
    XCTAssertNil(reading.displayedBPM)
  }
}

extension PresentationTests {
  func testLatestBandCacheRetainsValidSourceAndRejectsImportedOffBodyReplacement() {
    let now = Date()
    let id = UUID()
    var cache = LatestBandReadings()
    let valid = Measurement(
      deviceID: id, kind: .heartRate, timestamp: now.addingTimeInterval(-5), value: 80,
      origin: .measured, transport: "fixture")
    var imported = valid
    imported.timestamp = now
    imported.origin = .imported
    var offBody = valid
    offBody.timestamp = now
    offBody.wear = .offBody
    cache.ingest([valid, imported, offBody], now: now)
    XCTAssertEqual(cache.latest(selectedDeviceID: id, now: now)?.value, 80)
    XCTAssertNil(cache.latest(selectedDeviceID: UUID(), now: now))
  }
  func testBatteryRejectsMissingMalformedAndStaleValuesInsteadOfZero() throws {
    XCTAssertEqual(try BatteryReading.parse(Data([0]), at: Date()).percent, 0)
    XCTAssertEqual(try BatteryReading.parse(Data([100]), at: Date()).percent, 100)
    XCTAssertThrowsError(try BatteryReading.parse(Data(), at: Date()))
    XCTAssertThrowsError(try BatteryReading.parse(Data([101]), at: Date()))
    XCTAssertThrowsError(try BatteryReading.parse(Data([50, 50]), at: Date()))
    let now = Date()
    let reading = try BatteryReading.parse(Data([52]), at: now.addingTimeInterval(-3601))
    XCTAssertFalse(reading.isFresh(at: now))
  }
}

extension PresentationTests {
  func testReadinessSleepExpiresWithoutAnotherObservation() {
    let end = Date(timeIntervalSince1970: 1_800_000_000)
    let sleep = SleepSession(start: end.addingTimeInterval(-8 * 3600), end: end, timeZoneID: "UTC", origin: .manual)
    XCTAssertEqual(SleepPresentation(sessions: [sleep], now: end.addingTimeInterval(35 * 3600)).readinessSession?.id, sleep.id)
    XCTAssertNil(SleepPresentation(sessions: [sleep], now: end.addingTimeInterval(36 * 3600 + 1)).readinessSession)
  }
}
