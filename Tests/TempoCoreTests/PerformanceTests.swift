import XCTest
@testable import TempoCore

final class PerformanceTests: XCTestCase, @unchecked Sendable {
  private let device = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
  private func sample(_ second: Int, kind: MetricKind = .heartRate) -> TempoCore.Measurement {
    TempoCore.Measurement(deviceID: device, kind: kind,
      timestamp: Date(timeIntervalSince1970: 1_700_000_000 + Double(second)),
      value: 70, origin: .measured, transport: "performance-fixture")
  }
  func testCanonicalSelectionHasStableOrderingAtEqualInstants() {
    let records = [sample(0), sample(0, kind: .restingHeartRate), sample(0, kind: .rmssd)]
    let expected = records.sorted { $0.id < $1.id }.map(\.id)
    for _ in 0..<20 {
      XCTAssertEqual(CanonicalTimeline.select(Array(records.reversed()), sourceSegments: []).map(\.id), expected)
    }
  }
  func testCanonicalBenchmark() throws {
    guard ProcessInfo.processInfo.environment["TEMPO_BENCHMARK"] == "1" else {
      throw XCTSkip("Opt-in benchmark; run a Release build with TEMPO_BENCHMARK=1")
    }
    let records = (0..<86400).map { sample($0) }
    let clock = ContinuousClock()
    let legacy = clock.measure {
      for _ in 0..<5 { XCTAssertEqual(legacyCanonical(records).count, records.count) }
    }
    print("TEMPO legacy canonical 86400 records x5: \(legacy)")
    let elapsed = clock.measure {
      for _ in 0..<5 { XCTAssertEqual(CanonicalTimeline.select(records, sourceSegments: []).count, records.count) }
    }
    print("TEMPO canonical 86400 records x5: \(elapsed)")
    let incoming = (86400..<86700).map { sample($0) }
    var retained = records
    let cutoff = records[0].timestamp.addingTimeInterval(300)
    let receipt = clock.measure {
      for record in incoming {
        retained.append(record)
        retained.removeAll { $0.timestamp < cutoff }
      }
    }
    XCTAssertEqual(retained.count, records.count)
    print("TEMPO legacy receipt window 86400 +300 commits: \(receipt)")
    var buffer = CommittedMeasurementBuffer(windowSeconds: 86400)
    buffer.reset(records)
    var published: [TempoCore.Measurement] = []
    var publications = 0
    let coalesced = clock.measure {
      for (index, record) in incoming.enumerated() {
        _ = buffer.append([record])
        if (index + 1).isMultiple(of: 15) {
          published = buffer.publish(at: record.timestamp.addingTimeInterval(1))
          publications += 1
        }
      }
    }
    XCTAssertEqual(published.map(\.id), retained.map(\.id))
    XCTAssertEqual(publications, 20)
    print("TEMPO coalesced receipt window 86400 +300 commits /20 publications: \(coalesced)")
  }
  func testCommittedBufferPreservesHistoryAndOrdersLateRecords() {
    var buffer = CommittedMeasurementBuffer(windowSeconds: 100, publicationThreshold: 3)
    buffer.reset([sample(20), sample(40)])
    XCTAssertFalse(buffer.append([sample(30), sample(20)]))
    XCTAssertEqual(buffer.pendingCount, 2)
    XCTAssertTrue(buffer.append([sample(50)]))
    let records = buffer.publish(at: sample(60).timestamp)
    XCTAssertEqual(records.map(\.timestamp), [20, 30, 40, 50].map { sample($0).timestamp })
    XCTAssertEqual(buffer.pendingCount, 0)
    XCTAssertEqual(buffer.publish(at: sample(145).timestamp).map(\.id), [sample(50).id])
  }
  func testCommittedBufferResetCannotMixDatasetsOrLoseEqualTimeMetrics() {
    var buffer = CommittedMeasurementBuffer()
    buffer.reset([sample(0)])
    _ = buffer.append([sample(1)])
    buffer.reset([sample(20), sample(20, kind: .rmssd)])
    XCTAssertEqual(buffer.pendingCount, 0)
    XCTAssertEqual(buffer.publish(at: sample(30).timestamp).count, 2)
  }
  func testCanonicalWinnerMatchesDocumentedRanking() {
    let a = sample(10)
    var b = sample(10); b.deviceID = UUID(); b.id = "other"; b.wear = .onBody
    let segment = SourceSegment(deviceID: a.deviceID, start: sample(0).timestamp, end: nil, reason: "active")
    XCTAssertEqual(CanonicalTimeline.select([b,a], sourceSegments: [segment]).first?.id, a.id)
    XCTAssertEqual(CanonicalTimeline.select([a,b], sourceSegments: [segment], overrideID: b.deviceID).first?.id, b.id)
    XCTAssertEqual(CanonicalTimeline.select([a,b], sourceSegments: []).first?.id, b.id)
    b.wear = .offBody
    XCTAssertEqual(CanonicalTimeline.select([b,a], sourceSegments: [], overrideID: b.deviceID).first?.id, a.id)
  }

  func testPresentedSummaryKeepsMissingNightUnavailableAndExcludesOtherDaysLoad() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let yesterday = MeasurementFixture(date: now.addingTimeInterval(-86400))
    let result = PresentedHealthSummary.calculate(records: [yesterday], sleeps: [], nightMetrics: [:],
      sourceSegments: [], placements: [], maximumHeartRate: 190, now: now)
    XCTAssertNil(result.readiness.score)
    XCTAssertNil(result.sleepID)
    XCTAssertEqual(result.load?.coveredSeconds ?? 0, 0)
  }
  private func MeasurementFixture(date: Date) -> TempoCore.Measurement {
    TempoCore.Measurement(deviceID: device, kind: .heartRate, timestamp: date,
      value: 70, origin: .measured, transport: "performance-fixture")
  }
  func testPresentedSummaryUsesSavedNightInputsWithoutInventingHRV() {
    let now = sample(86400).timestamp
    let sleep = SleepSession(start: now.addingTimeInterval(-9*3600), end: now.addingTimeInterval(-3600),
      timeZoneID: "UTC", origin: .manual)
    let result = PresentedHealthSummary.calculate(records: [], sleeps: [sleep], nightMetrics: [:],
      sourceSegments: [], placements: [], maximumHeartRate: 190, now: now)
    XCTAssertNil(result.readiness.score)
    XCTAssertEqual(result.sleepID, sleep.id)
    XCTAssertEqual(result.readiness.baselineDays, 0)
  }

  func testWidgetPolicyCoalescesUnchangedSnapshotsButPublishesPrivacyImmediately() {
    var policy = WidgetPublicationPolicy()
    let now = sample(0).timestamp
    XCTAssertTrue(policy.shouldPublish(readiness: 65, sleepSeconds: 8*3600, privateDetails: true, now: now))
    XCTAssertFalse(policy.shouldPublish(readiness: 65, sleepSeconds: 8*3600, privateDetails: true, now: now.addingTimeInterval(15)))
    XCTAssertTrue(policy.shouldPublish(readiness: 65, sleepSeconds: 8*3600, privateDetails: false, now: now.addingTimeInterval(20)))
    XCTAssertTrue(policy.shouldPublish(readiness: 65, sleepSeconds: 8*3600, privateDetails: false, now: now.addingTimeInterval(1820)))
  }
  func testWidgetPolicyForegroundAndClockChangesDoNotLeaveOldSnapshot() {
    var policy = WidgetPublicationPolicy()
    let now = sample(10).timestamp
    XCTAssertTrue(policy.shouldPublish(readiness: nil, sleepSeconds: nil, privateDetails: true, now: now))
    XCTAssertTrue(policy.shouldPublish(readiness: nil, sleepSeconds: nil, privateDetails: true, now: now.addingTimeInterval(1), force: true))
    XCTAssertTrue(policy.shouldPublish(readiness: nil, sleepSeconds: nil, privateDetails: true, now: now.addingTimeInterval(-10)))
  }

  func testBufferRefreshKeepsReceiptsCommittedDuringReadButHonoursTombstones() {
    var buffer = CommittedMeasurementBuffer()
    buffer.reset([sample(20)])
    _ = buffer.append([sample(30)])
    let result = buffer.refresh([sample(20)], excluding: [sample(20).id], at: sample(40).timestamp)
    XCTAssertEqual(result.map(\.id), [sample(30).id])
    XCTAssertEqual(buffer.pendingCount, 0)
  }

  func testOptimizedCanonicalMatchesReferenceAcrossSourcesQualityAndBins() {
    let other = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    let records = (0..<240).map { i -> TempoCore.Measurement in
      var m = TempoCore.Measurement(deviceID: i.isMultiple(of: 2) ? device : other,
        kind: i.isMultiple(of: 4) ? .restingHeartRate : .heartRate,
        timestamp: sample(0).timestamp.addingTimeInterval(Double(i)/3), value: Double(60+i%40),
        origin: i.isMultiple(of: 3) ? .imported : .measured, transport: "parity-fixture", recordKey: "\(i)")
      if i.isMultiple(of: 17) { m.quality = ["invalid-fixture"] }
      if i.isMultiple(of: 11) { m.wear = .offBody }
      else if i.isMultiple(of: 5) { m.wear = .onBody }
      if i.isMultiple(of: 13) { m.qualityContext = ["fixture": 1] }
      return m
    }
    let segments = [SourceSegment(deviceID: device, start: sample(0).timestamp, end: nil, reason: "initial"),
      SourceSegment(deviceID: other, start: sample(40).timestamp, end: sample(60).timestamp, reason: "switch")]
    for bin in [1.0, 2.5] {
      for override in [nil, device, other] as [UUID?] {
        XCTAssertEqual(CanonicalTimeline.select(Array(records.reversed()), sourceSegments: segments,
          overrideID: override, binSeconds: bin).map(\.id),
          legacyCanonical(Array(records.reversed()), segments: segments, override: override, bin: bin).map(\.id))
      }
    }
  }
  // Original selection implementation, retained only as a test/benchmark reference.
  private func legacyCanonical(_ records: [TempoCore.Measurement], segments: [SourceSegment] = [],
    override: UUID? = nil, bin: Double = 1) -> [TempoCore.Measurement] {
    let groups = Dictionary(grouping: records.filter { $0.valid }) {
      "\($0.kind.rawValue)|\(Int(floor($0.timestamp.timeIntervalSince1970/bin)))"
    }
    return groups.values.compactMap { group in
      group.sorted { a,b in
        func rank(_ m: TempoCore.Measurement) -> Int {
          let active = segments.filter { m.timestamp >= $0.start && m.timestamp < ($0.end ?? .distantFuture) }
            .max { $0.start < $1.start }?.deviceID == m.deviceID
          return (m.deviceID == override ? 100 : 0) + (active ? 40 : 0)
            + (m.wear == .onBody ? 20 : 0) + (m.permitsPhysiologicalAnalytics ? 10 : 0)
            + (m.origin == .measured ? 5 : 0)
        }
        return rank(a) == rank(b) ? a.id < b.id : rank(a) > rank(b)
      }.first
    }.sorted { $0.timestamp == $1.timestamp ? $0.id < $1.id : $0.timestamp < $1.timestamp }
  }
  func testBufferRemembersDeletionDuringHistoryReplayUntilDatasetReset() {
    var buffer = CommittedMeasurementBuffer()
    let deleted = sample(20)
    _ = buffer.refresh([], excluding: [deleted.id], at: sample(30).timestamp)
    _ = buffer.append([deleted])
    XCTAssertTrue(buffer.publish(at: sample(40).timestamp).isEmpty)
    buffer.reset()
    _ = buffer.append([deleted])
    XCTAssertEqual(buffer.publish(at: sample(40).timestamp).map(\.id), [deleted.id])
  }

}
