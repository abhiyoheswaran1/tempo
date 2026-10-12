import XCTest

@testable import TempoCore

final class VolumeTests: XCTestCase, @unchecked Sendable {
  func testRangeReadIsBoundedAndNewestFirstCoverage() async throws {
    let store = try TempoStore(path: ":memory:")
    let id = UUID()
    try await store.insert(
      (0..<100).map {
        TempoCore.Measurement(
          deviceID: id, kind: .heartRate,
          timestamp: Date(timeIntervalSince1970: 1_700_000_000 + Double($0)),
          value: Double(60 + $0 % 10), origin: .measured, transport: "test")
      })
    let rows = try await store.measurements(from: .distantPast, to: .distantFuture, limit: 10)
    XCTAssertEqual(rows.count, 10)
    XCTAssertEqual(rows.first?.timestamp.timeIntervalSince1970, 1_700_000_090)
    let daily = try await store.dailyRepresentatives(
      kind: .heartRate, from: .distantPast, to: .distantFuture)
    XCTAssertEqual(daily.count, 1)
  }
}

extension VolumeTests {
  func testChartProjectionIsBoundedAndKeepsGapsSeparated() {
    let device = UUID()
    let t = Date(timeIntervalSince1970: 1_700_000_000)
    let observations = (0..<1500).map {
      TempoCore.Measurement(
        deviceID: device, kind: .heartRate,
        timestamp: t.addingTimeInterval(Double($0 + ($0 >= 750 ? 100 : 0))), value: 70,
        origin: .measured, transport: "test")
    }
    let chart = ChartProjection.points(observations, maximumPoints: 400)
    XCTAssertLessThan(chart.count, 500)
    XCTAssertEqual(Set(chart.map(\.segment)), [0, 1])
    XCTAssertEqual(chart.last?.sample.id, observations.last?.id)
  }
}
