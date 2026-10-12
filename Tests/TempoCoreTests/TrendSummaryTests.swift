import XCTest

@testable import TempoCore

final class TrendSummaryTests: XCTestCase {
  let t = Date(timeIntervalSince1970: 1_800_000_000)
  func samples(_ id: UUID = UUID()) -> [TempoCore.Measurement] {
    (0...120).map {
      Measurement(
        deviceID: id, kind: .heartRate, timestamp: t.addingTimeInterval(Double($0)),
        value: $0 < 60 ? 100 : 160, origin: .measured, transport: "fixture")
    }
  }
  func testDailyHeartRateUsesCoveredTimeRatherThanLastSample() {
    let summary = DailyTrendSummary.calculate(samples(), kind: .heartRate)[0]
    XCTAssertEqual(summary.value, 130, accuracy: 0.01)
    XCTAssertEqual(summary.coveredSeconds ?? 0, 120, accuracy: 0.01)
    XCTAssertEqual(summary.method, "Covered-time average")
  }
  func testGapsAndOverlappingBandsDoNotAddCoverage() {
    let a = samples()
    let b = samples()
    let summary = DailyTrendSummary.calculate(a + b + a, kind: .heartRate)[0]
    XCTAssertEqual(summary.coveredSeconds ?? 0, 120, accuracy: 0.01)
    let sparse = [a[0], a[120]]
    XCTAssertTrue(DailyTrendSummary.calculate(sparse, kind: .heartRate).isEmpty)
  }
  func testImportedHrvIsMedianAndProvenanceRemainsAvailable() {
    let id = UUID()
    let records = [20.0, 30, 90].enumerated().map {
      Measurement(
        deviceID: id, kind: .sdnn, timestamp: t.addingTimeInterval(Double($0.offset)),
        value: $0.element, origin: .imported, transport: "health")
    }
    let summary = DailyTrendSummary.calculate(records, kind: .sdnn)[0]
    XCTAssertEqual(summary.value, 30)
    XCTAssertEqual(summary.inputOrigins, [.imported])
    XCTAssertEqual(summary.inputCount, 3)
  }
  func testSyntheticInputsRequireDemoOptIn() {
    var data = samples()
    for i in data.indices { data[i].origin = .synthetic }
    XCTAssertTrue(DailyTrendSummary.calculate(data, kind: .heartRate).isEmpty)
    XCTAssertEqual(
      DailyTrendSummary.calculate(data, kind: .heartRate, allowSynthetic: true).count, 1)
  }
}

extension TrendSummaryTests {
  func testLocalDayBoundaryAcrossDSTAndDeletedObservations() async throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Zurich")!
    let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25))!
    let next = calendar.date(byAdding: .day, value: 1, to: day)!
    XCTAssertEqual(next.timeIntervalSince(day), 25 * 3600)
    let id = UUID()
    let data = (0...120).map {
      Measurement(
        deviceID: id, kind: .heartRate, timestamp: day.addingTimeInterval(Double($0)), value: 80,
        origin: .measured, transport: "fixture")
    }
    let store = try TempoStore(path: ":memory:")
    try await store.insert(data)
    let summaries = try await store.dailySummaries(
      kind: .heartRate, from: day, to: next, calendar: calendar)
    XCTAssertEqual(summaries.count, 1)
    XCTAssertEqual(summaries[0].date, day)
    XCTAssertEqual(summaries[0].coveredSeconds, 120)
    for m in data {
      try await store.saveRevision(
        Revision(
          entityID: UUID(), kind: "measurementDeletion", parentIDs: [], payload: Data(m.id.utf8)))
    }
    let deleted = try await store.dailySummaries(
      kind: .heartRate, from: day, to: next, calendar: calendar)
    XCTAssertTrue(deleted.isEmpty)
  }
}

extension TrendSummaryTests {
  func testMidnightCoverageRetainsBoundaryInputProvenance() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let day = calendar.startOfDay(for: t)
    let id = UUID()
    let data = (0...14).map {
      Measurement(
        deviceID: id, kind: .heartRate, timestamp: day.addingTimeInterval(-3 + Double($0) * 5),
        value: 100, origin: .measured, transport: "fixture")
    }
    let summary = DailyTrendSummary.calculate(data, kind: .heartRate, calendar: calendar).first {
      $0.date == day
    }!
    XCTAssertEqual(summary.inputCount, data.count)
    XCTAssertEqual(summary.inputDigest, StableID.hash(data.map(\.id).joined(separator: "|")))
  }
}
