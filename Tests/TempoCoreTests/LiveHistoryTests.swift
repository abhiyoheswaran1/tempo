import XCTest

@testable import TempoCore

final class LiveHistoryTests: XCTestCase {
  func testFourHourPlotIsBoundedAndKeepsActualExtremaAndGaps() {
    let end = Date()
    let id = UUID()
    var samples = (0..<14400).filter { !(6600..<7200).contains($0) }.map {
      Measurement(
        deviceID: id, kind: .heartRate, timestamp: end.addingTimeInterval(Double($0 - 14399)),
        value: 80, origin: .measured, transport: "fixture")
    }
    samples[100].value = 160
    let history = LiveHistorySnapshot(
      samples: samples, from: end.addingTimeInterval(-14400), to: end,
      sourceSegments: [], maximumHeartRate: 190)
    XCTAssertLessThanOrEqual(history.points.count, 960)
    XCTAssertTrue(history.points.contains { $0.sample.value == 160 })
    XCTAssertEqual(history.maximum, 160)
    XCTAssertEqual(history.coveredSeconds, 13798, accuracy: 0.01)
    XCTAssertEqual(Set(history.points.map(\.segment)).count, 2)
    XCTAssertTrue(
      history.points.allSatisfy { point in samples.contains { $0.id == point.sample.id } })
  }
  func testWindowLoadsDirectHRBeforeApplyingLimitAndMarksTruncation() async throws {
    let store = try TempoStore(path: ":memory:")
    let now = Date()
    let id = UUID()
    let hr = (0..<5).map {
      Measurement(
        deviceID: id, kind: .heartRate, timestamp: now.addingTimeInterval(Double($0 - 20)),
        value: 80, origin: .measured, transport: "fixture")
    }
    let other = (0..<10).map {
      Measurement(
        deviceID: id, kind: .weight, timestamp: now.addingTimeInterval(Double($0 - 10)), value: 70,
        origin: .imported, transport: "health")
    }
    try await store.insert(hr + other)
    let window = try await store.liveHeartRateWindow(
      from: now.addingTimeInterval(-60), to: now, limit: 3)
    XCTAssertEqual(window.samples.count, 3)
    XCTAssertTrue(window.truncated)
    XCTAssertEqual(window.samples.map(\.timestamp), Array(hr.suffix(3)).map(\.timestamp))
  }
  func testUnpoweredBluetoothCommandsNeverExecuteAndDemoOnlyAllowsCleanup() {
    var effects: [String] = []
    XCTAssertFalse(
      BluetoothCommandPolicy.perform(poweredOn: false, collectionAllowed: true, cleanup: true) {
        effects.append("stop")
      })
    XCTAssertFalse(
      BluetoothCommandPolicy.perform(poweredOn: true, collectionAllowed: false, cleanup: false) {
        effects.append("connect")
      })
    XCTAssertTrue(
      BluetoothCommandPolicy.perform(poweredOn: true, collectionAllowed: false, cleanup: true) {
        effects.append("cancel")
      })
    XCTAssertTrue(
      BluetoothCommandPolicy.perform(poweredOn: true, collectionAllowed: true, cleanup: false) {
        effects.append("connect")
      })
    XCTAssertEqual(effects, ["cancel", "connect"])
  }
}
