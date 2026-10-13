import XCTest

@testable import TempoCore

final class Whoop5HistoryTests: XCTestCase, @unchecked Sendable {
  func record(
    hr: UInt8 = 80, layout: UInt8 = 18, count: UInt8 = 2, timestamp: UInt32 = 1_700_000_000
  ) throws -> WhoopFrame {
    var body = Data(repeating: 0, count: 109)
    body[0] = 7
    for i in 0..<4 { body[4 + i] = UInt8(truncatingIfNeeded: timestamp >> (8 * i)) }
    body[11] = hr
    body[12] = count
    body[13] = 0
    body[14] = 4
    body[15] = 0x40
    body[16] = 3
    body[25] = 0x80
    return try WhoopFrame.parse(
      WhoopReadProtocol.frame5(type: 47, sequence: layout, command: 0, body: body),
      generation: .whoop5)
  }
  func testDocumentedR18HeartRateAndStableCrossPhoneIdentity() throws {
    let id = UUID()
    let frame = try record()
    let first = try Whoop5History.decode(frame, deviceID: id, firmware: "50.42.1.0")
    let second = try Whoop5History.decode(frame, deviceID: id, firmware: "50.42.1.0")
    XCTAssertEqual(first.count, 1)
    XCTAssertEqual(first.first?.value, 80)
    XCTAssertEqual(first.first?.timestamp, Date(timeIntervalSince1970: 1_700_000_000))
    XCTAssertEqual(first.first?.id, second.first?.id)
    XCTAssertEqual(first.first?.wear, .unknown)
  }
  func testUnknownFirmwareLayoutAndInvalidHeartRateAreNotDecoded() throws {
    XCTAssertThrowsError(
      try Whoop5History.decode(record(), deviceID: UUID(), firmware: "50.43.0.0"))
    XCTAssertThrowsError(
      try Whoop5History.decode(record(layout: 20), deviceID: UUID(), firmware: "50.42.1.0"))
    XCTAssertThrowsError(
      try Whoop5History.decode(record(hr: 0), deviceID: UUID(), firmware: "50.42.1.0"))
    XCTAssertThrowsError(
      try Whoop5History.decode(record(count: 5), deviceID: UUID(), firmware: "50.42.1.0"))
    XCTAssertThrowsError(
      try Whoop5History.decode(record(timestamp: 0), deviceID: UUID(), firmware: "50.42.1.0"))
  }
}

extension Whoop5HistoryTests {
  func testFiveTransferUsesDocumentedTokenAndDurabilityBoundary() throws {
    var transfer = BandHistoryTransfer(generation: .whoop5)
    func metadata(_ marker: UInt8, body: Data = Data()) throws -> WhoopFrame {
      try WhoopFrame.parse(
        WhoopReadProtocol.frame5(type: 49, sequence: 1, command: marker, body: body),
        generation: .whoop5)
    }
    _ = try transfer.receive(metadata(1))
    _ = try transfer.receive(record())
    let token = Data([8, 0, 0, 0, 2, 0, 0, 0])
    guard
      case .chunk(let chunk) = try transfer.receive(
        metadata(2, body: Data(repeating: 0, count: 10) + token))
    else { return XCTFail("Expected chunk") }
    XCTAssertEqual(chunk.token, token)
    XCTAssertThrowsError(try transfer.committed(token: Data([8])))
    XCTAssertEqual(try transfer.committed(token: token), Data([1]) + token)
    XCTAssertThrowsError(
      try transfer.receive(
        WhoopFrame.parse(
          WhoopFrame.encode4(type: 49, sequence: 0, command: 1, payload: Data()),
          generation: .whoop4)))
  }
}

extension Whoop5HistoryTests {
  func testFiveTransferEligibilityRequiresReadFirmwareAndPositiveRange() {
    XCTAssertFalse(
      WhoopReadProtocol.canRetrieve(
        generation: .whoop5, applicationFirmware: nil, storedRecordEstimate: 10))
    XCTAssertFalse(
      WhoopReadProtocol.canRetrieve(
        generation: .whoop5, applicationFirmware: "50.42.1.0", storedRecordEstimate: 0))
    XCTAssertFalse(
      WhoopReadProtocol.canRetrieve(
        generation: .whoop5, applicationFirmware: "50.43.0.0", storedRecordEstimate: 10))
    XCTAssertTrue(
      WhoopReadProtocol.canRetrieve(
        generation: .whoop5, applicationFirmware: "50.42.1.0", storedRecordEstimate: 10))
  }
  func testFiveRawArchiveAndCheckpointCommitAtomicallyThenReplayIdempotently() async throws {
    let store = try TempoStore(path: ":memory:")
    let id = UUID()
    let frame = try record()
    let samples = try Whoop5History.decode(frame, deviceID: id, firmware: "50.42.1.0")
    try await store.commitHistory(
      deviceID: id, samples: samples, cursor: Data([8]), rawFrames: [frame.raw], generation: .whoop5
    )
    try await store.commitHistory(
      deviceID: id, samples: samples, cursor: Data([8]), rawFrames: [frame.raw], generation: .whoop5
    )
    let count = try await store.historyFrameCount(deviceID: id)
    let measurements = try await store.measurements(from: .distantPast, to: .distantFuture)
    XCTAssertEqual(count, 1)
    XCTAssertEqual(measurements.count, 1)
    XCTAssertEqual(measurements.first?.qualityContext?["opaqueR18QualityFlags"], 0x80)
    XCTAssertEqual(measurements.first?.rrMilliseconds, [])
  }
}

extension Whoop5HistoryTests {
  func testRangeReplyAllowsOnlyDocumentedZeroEnvelopePadding() throws {
    var body = Data(repeating: 0, count: 65)
    body[0] = 1
    body[21] = 64
    body[25] = 10
    let reply = try WhoopReadProtocol.reply(
      WhoopFrame.parse(
        WhoopReadProtocol.frame5(type: 36, sequence: 99, command: 34, body: Data([2, 1]) + body),
        generation: .whoop5))
    XCTAssertEqual(reply.body.count, 67)
    XCTAssertEqual(try WhoopReadProtocol.recordCountEstimate(reply.body), 10)
    var bad = reply.body
    bad[66] = 1
    XCTAssertThrowsError(try WhoopReadProtocol.recordCountEstimate(bad))
  }
}

extension Whoop5HistoryTests {
  func testUnresolvedR18QualityDoesNotSupplyPhysiologicalAnalytics() async throws {
    let id = UUID()
    let samples = try (0..<300).flatMap { i in
      try Whoop5History.decode(
        record(timestamp: 1_700_000_000 + UInt32(i)), deviceID: id, firmware: "50.42.1.0")
    }
    XCTAssertTrue(
      samples.allSatisfy(\.valid), "Primary HR remains inspectable as a direct experimental reading"
    )
    XCTAssertNil(CardiovascularLoad.calculate(samples, maxHeartRate: 200)?.average)
    let store = try TempoStore(path: ":memory:")
    try await store.insert(samples)
    let sleep = SleepSession(
      start: Date(timeIntervalSince1970: 1_700_000_000),
      end: Date(timeIntervalSince1970: 1_700_000_300), timeZoneID: "UTC", origin: .manual)
    let inputs = try await store.nightInputs(sleep, sourceSegments: [])
    XCTAssertNil(inputs["rhr"])
    XCTAssertNil(inputs["rmssd"])
  }
  func testFiveArchiveFailureRollsBackSamplesAndCheckpoint() async throws {
    let store = try TempoStore(path: ":memory:")
    let id = UUID()
    let frame = try record()
    let samples = try Whoop5History.decode(frame, deviceID: id, firmware: "50.42.1.0")
    do {
      try await store.commitHistory(
        deviceID: id, samples: samples, cursor: Data([9]), rawFrames: [Data([0])],
        generation: .whoop5)
      XCTFail("Invalid raw data must reject the complete transaction")
    } catch {}
    let rows = try await store.measurements(from: .distantPast, to: .distantFuture)
    let checkpoint = try await store.checkpoint(deviceID: id)
    XCTAssertTrue(rows.isEmpty)
    XCTAssertNil(checkpoint)
  }
}

extension Whoop5HistoryTests {
  func testCanonicalTimelinePrefersQualifiedReadingWithoutOverridingSourceChoice() {
    let id = UUID()
    let other = UUID()
    let time = Date(timeIntervalSince1970: 1_700_000_000)
    var experimental = Measurement(
      deviceID: id, kind: .heartRate, timestamp: time, value: 80, origin: .measured,
      transport: "whoop5-history-r18-experimental")
    experimental.id = "a"
    experimental.qualityContext = ["opaqueR18QualityFlags": 0]
    var qualified = Measurement(
      deviceID: id, kind: .heartRate, timestamp: time, value: 81, origin: .measured,
      transport: "bluetooth-hrs")
    qualified.id = "z"
    XCTAssertEqual(
      CanonicalTimeline.select([experimental, qualified], sourceSegments: []).first?.id, "z")
    qualified.deviceID = other
    XCTAssertEqual(
      CanonicalTimeline.select([experimental, qualified], sourceSegments: [], overrideID: id).first?
        .id, "a")
  }
}

extension Whoop5HistoryTests {
  func testRecoveredExperimentalReadingsStillHaveDescriptiveChartCoverage() throws {
    let id = UUID()
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let samples = try (0..<300).flatMap { i in
      try Whoop5History.decode(
        record(timestamp: 1_700_000_000 + UInt32(i)), deviceID: id, firmware: "50.42.1.0")
    }
    let snapshot = LiveHistorySnapshot(
      samples: samples, from: start, to: start.addingTimeInterval(300), sourceSegments: [],
      maximumHeartRate: 200)
    XCTAssertEqual(snapshot.sampleCount, 300)
    XCTAssertEqual(snapshot.coveredSeconds, 299, accuracy: 0.001)
    XCTAssertEqual(snapshot.average ?? -1, 80, accuracy: 0.001)
  }
}

extension Whoop5HistoryTests {
  func testOpaqueR18QualityCannotGenerateWorkoutSuggestions() throws {
    let id = UUID()
    let samples = try (0..<1140).flatMap { i in
      try Whoop5History.decode(
        record(hr: i < 900 ? 140 : 70, timestamp: 1_700_000_040 + UInt32(i)), deviceID: id,
        firmware: "50.42.1.0")
    }
    let suggestions = AutomaticActivityDetector.detect(
      samples, maxHeartRate: 190, now: Date(timeIntervalSince1970: 1_700_001_240))
    XCTAssertTrue(suggestions.isEmpty)
  }
}

extension Whoop5HistoryTests {
  func testStreamingHistoryDoesNotExpireAtOrdinaryReplyDeadline() throws {
    XCTAssertTrue(HistoryRequestDeadline.shouldExpire(command: 22, streamStarted: false))
    XCTAssertFalse(HistoryRequestDeadline.shouldExpire(command: 22, streamStarted: true))
    XCTAssertTrue(HistoryRequestDeadline.shouldExpire(command: 34, streamStarted: true))
  }
}

extension Whoop5HistoryTests {
  func testRetryCannotAcknowledgeLateCommitWithSameTokenFromEarlierAttempt() throws {
    let token = Data([8, 0, 0, 0, 2, 0, 0, 0])
    let start = try WhoopFrame.parse(
      WhoopReadProtocol.frame5(type: 49, sequence: 1, command: 1, body: Data()), generation: .whoop5
    )
    let end = try WhoopFrame.parse(
      WhoopReadProtocol.frame5(
        type: 49, sequence: 1, command: 2, body: Data(repeating: 0, count: 10) + token),
      generation: .whoop5)
    var first = BandHistoryTransfer(generation: .whoop5)
    XCTAssertFalse(first.hasStarted)
    _ = try first.receive(start)
    XCTAssertTrue(first.hasStarted)
    _ = try first.receive(record())
    guard case .chunk(let oldChunk) = try first.receive(end) else { return XCTFail("chunk") }
    first.interrupt()
    var retry = BandHistoryTransfer(generation: .whoop5)
    _ = try retry.receive(start)
    _ = try retry.receive(record())
    guard case .chunk(let currentChunk) = try retry.receive(end) else { return XCTFail("chunk") }
    XCTAssertNotEqual(oldChunk.attemptID, currentChunk.attemptID)
    XCTAssertThrowsError(try retry.committed(token: token, attemptID: oldChunk.attemptID))
    XCTAssertEqual(
      try retry.committed(token: token, attemptID: currentChunk.attemptID), Data([1]) + token)
  }
}

final class HistoryNotificationRetryTests: XCTestCase {
  func testRetriesAreBoundedAndResetAfterSuccess() {
    var retry = HistoryNotificationRetry()
    XCTAssertEqual(retry.nextDelay(channel: "3"), 2)
    XCTAssertEqual(retry.nextDelay(channel: "3"), 4)
    XCTAssertEqual(retry.nextDelay(channel: "7"), 2)
    XCTAssertEqual(retry.nextDelay(channel: "3"), 8)
    XCTAssertNil(retry.nextDelay(channel: "3"))
    retry.succeeded(channel: "3")
    XCTAssertEqual(retry.nextDelay(channel: "3"), 2)
  }
}
