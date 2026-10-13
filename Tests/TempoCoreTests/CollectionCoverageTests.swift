import XCTest
@testable import TempoCore
final class CollectionCoverageTests: XCTestCase {
  let start = Date(timeIntervalSince1970: 1_700_000_000)
  func sample(_ second: Double, device: UUID = UUID(), origin: Origin = .measured) -> TempoCore.Measurement {
    TempoCore.Measurement(deviceID: device, kind: .heartRate, timestamp: start.addingTimeInterval(second),
      value: 70, origin: origin, transport: origin == .synthetic ? "demo" : "bluetooth-hrs")
  }
  func testCoverageKeepsEdgesAndInteriorGapsWithoutDoubleCountingBands() {
    let result = CollectionCoverage(samples: [sample(10),sample(11),sample(11),sample(30),sample(31)],
      from: start, to: start.addingTimeInterval(40))
    XCTAssertEqual(result.coveredSeconds, 2)
    XCTAssertEqual(result.gaps.count, 3)
    XCTAssertEqual(result.latestRecord, start.addingTimeInterval(31))
    XCTAssertEqual(result.historicalCount, 0)
  }
  func testReceiptQualityIsSeparateFromPhysiologicalEligibilityAndDemoIsOptIn() {
    var m = sample(1);m.quality = ["unknown-fixture-flag"]
    let result = CollectionCoverage(samples: [m,sample(2)], from: start, to: start.addingTimeInterval(10))
    XCTAssertEqual(result.coveredSeconds, 1)
    XCTAssertTrue(result.hasUnqualifiedRecords)
    XCTAssertEqual(CollectionCoverage(samples: [sample(1,origin:.synthetic)], from:start,to:start.addingTimeInterval(10)).sampleCount,0)
    XCTAssertEqual(CollectionCoverage(samples: [sample(1,origin:.imported)], from:start,to:start.addingTimeInterval(10)).sampleCount,0)
  }
  func testEmptyCoverageIsMissingNotZeroPhysiology() {
    let result = CollectionCoverage(samples: [], from:start,to:start.addingTimeInterval(60))
    XCTAssertNil(result.latestRecord)
    XCTAssertEqual(result.gaps.count,1)
    XCTAssertEqual(result.coveredSeconds,0)
  }
  func testReliabilityArchiveIsBoundedIdempotentAndRejectsInvalidMetrics() {
    var archive = ReliabilityArchive()
    for day in 0..<10 {
      let report = ReliabilityReport(start:start.addingTimeInterval(Double(day)*86400),
        end:start.addingTimeInterval(Double(day+1)*86400),cpuSeconds:1,peakMemoryMB:50)
      archive.record(report);archive.record(report)
    }
    XCTAssertEqual(archive.reports.count,7)
    archive.record(ReliabilityReport(start:start,end:start.addingTimeInterval(10),cpuSeconds:-1,peakMemoryMB:50))
    XCTAssertEqual(archive.reports.count,7)
    archive.clear();XCTAssertTrue(archive.reports.isEmpty)
  }
  func testReliabilityRejectsUnrepresentableDurationBeforeRendering() {
    XCTAssertFalse(ReliabilityReport(start:start,end:start.addingTimeInterval(86400),cpuSeconds:1e300,peakMemoryMB:50).valid)
  }

}
