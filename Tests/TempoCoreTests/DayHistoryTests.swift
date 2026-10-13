import XCTest
@testable import TempoCore

final class DayHistoryTests: XCTestCase {
  var calendar: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Zurich")!
    return c
  }
  func date(_ day: Int, hour: Int = 7, month: Int = 10) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
  }
  func night(_ day: Int, hours: Double = 8, origin: Origin = .manual) -> SleepSession {
    let end = date(day)
    return SleepSession(start: end.addingTimeInterval(-hours * 3600), end: end,
      timeZoneID: "Europe/Zurich", origin: origin)
  }
  func testCalendarDayHandlesDSTAndHalfOpenBoundaries() {
    let window = DayHistory.window(for: date(25), calendar: calendar)
    XCTAssertEqual(window.end.timeIntervalSince(window.start), 25 * 3600)
    XCTAssertTrue(window.contains(window.start))
    XCTAssertFalse(window.contains(window.end))
  }
  func testSleepBelongsToWakeDayAndNapsRemainSeparate() {
    var nap = night(13, hours: 1)
    nap.isNap = true
    nap.start = date(13, hour: 13)
    nap.end = date(13, hour: 14)
    let result = DayHistory.sessions([night(12), night(13), nap, night(14)],
      on: date(13), now: date(14), calendar: calendar)
    XCTAssertEqual(result.count, 2)
    XCTAssertEqual(result.filter(\.isNap).count, 1)
  }
  func testObservationRequiresSevenDistinctPriorNights() {
    let result = DailyObservation.sleep([night(13)] + (7...12).map { night($0) },
      now: date(13, hour: 12), calendar: calendar)
    XCTAssertEqual(result.kind, .building)
    XCTAssertEqual(result.referenceCount, 6)
    XCTAssertNil(result.differenceSeconds)
  }
  func testObservationExcludesCurrentDayFromMedianAndRetainsEvidence() {
    let result = DailyObservation.sleep([night(13, hours: 7)] + (6...12).map { night($0) },
      now: date(13, hour: 12), calendar: calendar)
    XCTAssertEqual(result.kind, .shorterSleep)
    XCTAssertEqual(result.differenceSeconds, -3600)
    XCTAssertEqual(result.referenceSeconds, 8 * 3600)
    XCTAssertEqual(result.referenceSessionIDs.count, 7)
    XCTAssertEqual(result.algorithmVersion, "daily-observation-1.0")
  }
  func testDuplicatesNapsUnconfirmedImportsAndFutureCannotBuildBaseline() {
    let prior = night(12)
    var nap = night(11); nap.isNap = true
    let inputs = [night(13), prior, prior, nap, night(10, origin: .derived),
      night(9, origin: .imported), night(14), night(8, origin: .synthetic)]
    let result = DailyObservation.sleep(inputs, now: date(13, hour: 12), calendar: calendar)
    XCTAssertEqual(result.referenceCount, 1)
  }
  func testSyntheticSleepRequiresExplicitDemoOptIn() {
    let inputs = (6...13).map { night($0, origin: .synthetic) }
    XCTAssertEqual(DailyObservation.sleep(inputs, now: date(13, hour: 12), calendar: calendar).kind, .building)
    XCTAssertEqual(DailyObservation.sleep(inputs, now: date(13, hour: 12), calendar: calendar,
      allowSynthetic: true).kind, .usualSleep)
  }
  func testRhythmUsesRecordedClockTimesAcrossDST() {
    let s = SleepSession(start: date(24, hour: 23), end: date(25, hour: 7),
      timeZoneID: "Europe/Zurich", origin: .manual)
    let entry = SleepRhythmEntry(session: s)!
    XCTAssertEqual(entry.startHour, -1)
    XCTAssertEqual(entry.endHour, 7)
    XCTAssertEqual(s.duration, 9 * 3600)
  }
  func testRhythmRejectsInvalidTimezoneAndDates() {
    var s = night(13); s.timeZoneID = "not-a-timezone"
    XCTAssertNil(SleepRhythmEntry(session: s))
    s = night(13); s.start = Date(timeIntervalSince1970: .infinity)
    XCTAssertNil(SleepRhythmEntry(session: s))
  }
  func testExpiredHistoryDoesNotSupplyCurrentObservation() {
    let result = DailyObservation.sleep((1...8).map { night($0) },
      now: date(13, hour: 12), calendar: calendar)
    XCTAssertEqual(result.kind, .building)
    XCTAssertNil(result.currentSessionID)
  }
}

extension DayHistoryTests {
  func testOverlappingSleepSelectionIsIndependentOfInputOrder() {
    var a = night(13); var b = a
    a.id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    b.id = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    XCTAssertEqual(SessionReconciliation.sleep([b, a]).map(\.id), SessionReconciliation.sleep([a, b]).map(\.id))
  }
  func testInvalidInfiniteSleepIsRejectedBeforeReconciliation() {
    var bad = night(13); bad.end = Date(timeIntervalSince1970: .infinity)
    XCTAssertTrue(SessionReconciliation.sleep([bad]).isEmpty)
  }
}

extension DayHistoryTests {
  func testHistoricalImportedHRRequiresExplicitReaderOptIn() {
    let start = date(13)
    let samples = (0...120).map { i in Measurement(deviceID: UUID(), kind: .heartRate,
      timestamp: start.addingTimeInterval(Double(i)), value: 80, origin: .imported, transport: "health") }
    let ordinary = LiveHistorySnapshot(samples: samples, from: start, to: start.addingTimeInterval(121),
      sourceSegments: [], maximumHeartRate: 190)
    XCTAssertEqual(ordinary.sampleCount, 0)
    let reader = LiveHistorySnapshot(samples: samples, from: start, to: start.addingTimeInterval(121),
      sourceSegments: [], maximumHeartRate: 190, includeImported: true)
    XCTAssertEqual(reader.sampleCount, 121)
    XCTAssertEqual(reader.coveredSeconds, 120)
  }
}

extension DayHistoryTests {
  func testCorrectionAcrossMidnightDoesNotResurrectOriginalOnOldWakeDay() {
    let original = SleepSession(start: date(12, hour: 22), end: date(13, hour: 1),
      timeZoneID: "Europe/Zurich", origin: .measured)
    let correction = SleepSession(start: original.start, end: date(12, hour: 23),
      timeZoneID: "Europe/Zurich", origin: .manual)
    XCTAssertTrue(DayHistory.sessions([original, correction], on: date(13), now: date(14), calendar: calendar).isEmpty)
    XCTAssertEqual(DayHistory.sessions([original, correction], on: date(12), now: date(14), calendar: calendar).map(\.id), [correction.id])
  }
  func testManualNapCorrectionDoesNotReturnOriginalAsPrimaryNight() {
    var corrected = night(13); corrected.isNap = true
    let original = night(13, origin: .measured)
    XCTAssertTrue(DayHistory.primarySleeps([original, corrected], now: date(14), calendar: calendar).isEmpty)
  }
}

extension DayHistoryTests {
  func testCaffeineTimeForHistoricalJournalKeepsRecordedDayAndTimezone() throws {
    let entry = JournalEntry(date: date(10, hour: 12), timeZoneID: "Europe/Zurich")
    let anchored = try XCTUnwrap(entry.caffeineTimestamp(clock: date(13, hour: 16)))
    XCTAssertTrue(calendar.isDate(anchored, inSameDayAs: entry.date))
    XCTAssertEqual(calendar.component(.hour, from: anchored), 16)
  }
}
