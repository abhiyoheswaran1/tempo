import XCTest
@testable import TempoCore

final class SleepDetectionTests: XCTestCase {
  let device = UUID()
  let start = Date(timeIntervalSince1970: 1_790_000_000)
  func records() -> [TempoCore.Measurement] {
    (0..<12*3600).map { i in
      TempoCore.Measurement(deviceID: device, kind: .heartRate, timestamp: start.addingTimeInterval(Double(i)), value: i >= 3600 && i < 9*3600 ? 55 : 85, origin: .measured, transport: "test")
    }
  }
  func testFindsCoveredRestButDoesNotDeclareConfirmedSleep() {
    let result = SleepDetection.candidates(records(), now: start.addingTimeInterval(12*3600))
    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result[0].session.origin, .derived)
    XCTAssertGreaterThan(result[0].coverage, 0.9)
    XCTAssertEqual(result[0].session.algorithmVersion, "sleep-candidate-1.0")
  }
  func testSparseAndFlatDataNeverInventSleep() {
    XCTAssertTrue(SleepDetection.candidates(Array(records().prefix(50)), now: start.addingTimeInterval(12*3600)).isEmpty)
    var flat = records(); for i in flat.indices { flat[i].value = 55 }
    XCTAssertTrue(SleepDetection.candidates(flat, now: start.addingTimeInterval(12*3600)).isEmpty)
  }
  func testGapsBreakCandidatesAndOverlapsDoNotIncreaseCoverage() {
    let samples = records().filter { $0.timestamp < start.addingTimeInterval(4*3600) || $0.timestamp >= start.addingTimeInterval(7*3600) }
    let a = SleepDetection.candidates(samples, now: start.addingTimeInterval(12*3600))
    XCTAssertEqual(a.count, 1)
    XCTAssertGreaterThanOrEqual(a[0].session.start, start.addingTimeInterval(7*3600))
    let b = SleepDetection.candidates(samples + samples, now: start.addingTimeInterval(12*3600))
    XCTAssertEqual(a, b)
  }
  func testCurrentRestIsNotFinishedSleep() {
    XCTAssertTrue(SleepDetection.candidates(Array(records().prefix(8*3600)), now: start.addingTimeInterval(8*3600)).isEmpty)
  }
}
