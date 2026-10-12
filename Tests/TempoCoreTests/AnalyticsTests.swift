import XCTest

@testable import TempoCore

final class AnalyticsTests: XCTestCase {
  func testHRVRequiresCoverageAndDoesNotBridgeArtifacts() {
    XCTAssertNil(HRV.calculate([800, 810], minimumIntervals: 30))
    let result = HRV.calculate(
      Array(repeating: [800.0, 820.0], count: 150).flatMap { $0 }, minimumIntervals: 30)
    XCTAssertEqual(result?.rmssd ?? 0, 20, accuracy: 0.001)
    XCTAssertNil(HRV.calculate(Array(repeating: 20.0, count: 300), minimumIntervals: 30))
  }
  func testInsufficientReadinessAndSparseAssociation() {
    XCTAssertNil(Readiness.calculate(current: [:], baseline: []).score)
    XCTAssertNil(Association.calculate([(1.0, 2.0), (2.0, 3.0)]))
  }
  func testWorkoutPauseRelaunchAndSwitch() throws {
    let t = Date(timeIntervalSince1970: 1_700_000_000)
    var w = Workout(activity: .padel, start: t)
    w.switchSource(to: UUID(), at: t)
    w.pause(at: t.addingTimeInterval(60))
    var restored = try JSONDecoder().decode(Workout.self, from: JSONEncoder().encode(w))
    restored.resume(at: t.addingTimeInterval(120))
    restored.switchSource(to: UUID(), at: t.addingTimeInterval(150))
    restored.finish(at: t.addingTimeInterval(180))
    XCTAssertEqual(restored.activeDuration(at: t.addingTimeInterval(180)), 120, accuracy: 0.1)
    XCTAssertEqual(restored.sources.count, 2)
  }
  func testSleepElapsedDurationAcrossDST() {
    let start = Date(timeIntervalSince1970: 1_761_436_800)
    let sleep = SleepSession(
      start: start, end: start.addingTimeInterval(8 * 3600), timeZoneID: "Europe/Zurich",
      origin: .manual)
    XCTAssertEqual(sleep.duration, 8 * 3600)
  }
}

extension AnalyticsTests {
  func testDeviceChangeLowersConfidenceWithoutResettingHistory() {
    let history = (0..<21).map {
      PersonalBaseline(
        date: Date(timeIntervalSince1970: 1_700_000_000 + Double($0) * 86400),
        values: ["rhr": 60, "sleepHours": 8])
    }
    let ordinary = Readiness.calculate(current: ["rhr": 60, "sleepHours": 8], baseline: history)
    let switched = Readiness.calculate(
      current: ["rhr": 60, "sleepHours": 8], baseline: history, deviceChange: true)
    XCTAssertEqual(switched.baselineDays, ordinary.baselineDays)
    XCTAssertLessThan(switched.confidence, ordinary.confidence)
  }
}
