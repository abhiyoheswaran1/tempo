import CSQLite
import XCTest

@testable import TempoCore

final class HistoryTransferTests: XCTestCase {
  func testFiveCommandMatchesDocumentedHelloAndReplyOrigin() throws {
    let expected = Data([0xAA, 1, 8, 0, 0, 1, 0xE6, 0x71, 35, 1, 145, 1, 0x36, 0x3E, 0x5C, 0x8D])
    XCTAssertEqual(
      WhoopReadProtocol.command(generation: .whoop5, sequence: 1, command: 145, body: Data([1])),
      expected)
    let raw = WhoopReadProtocol.frame5(type: 36, sequence: 99, command: 145, body: Data([7, 1, 1]))
    let reply = try WhoopReadProtocol.reply(WhoopFrame.parse(raw, generation: .whoop5))
    XCTAssertEqual(reply.origin, 7)
    XCTAssertEqual(reply.result, 1)
    XCTAssertNotEqual(reply.origin, 99)
  }
  func testFirmwareReadDoesNotUseBluetoothProcessorOrPendingReply() throws {
    var body = Data(repeating: 0, count: 68)
    body[0] = 1
    for (i, v) in [41, 17, 6, 0].enumerated() { body[1 + i * 4] = UInt8(v) }
    let frame = try WhoopFrame.parse(
      WhoopFrame.encode4(type: 36, sequence: 4, command: 7, payload: Data([3, 1]) + body),
      generation: .whoop4)
    XCTAssertEqual(try WhoopReadProtocol.applicationFirmware(frame), "41.17.6.0")
    XCTAssertThrowsError(
      try WhoopReadProtocol.applicationFirmware(
        WhoopFrame.parse(
          WhoopFrame.encode4(type: 36, sequence: 4, command: 7, payload: Data([3, 2]) + body),
          generation: .whoop4)))
  }
  func testHistoryRequiresStartAndCommitBeforeAcknowledgment() throws {
    var transfer = Whoop4Transfer()
    let end = try metadata(
      2, payload: Data(repeating: 0, count: 10) + Data([1, 2, 3, 4, 5, 6, 7, 8]))
    XCTAssertThrowsError(try transfer.receive(end))
    _ = try transfer.receive(metadata(1))
    _ = try transfer.receive(record())
    guard case .chunk(let chunk) = try transfer.receive(end) else { return XCTFail("chunk") }
    XCTAssertEqual(chunk.token, Data([1, 2, 3, 4, 5, 6, 7, 8]))
    XCTAssertThrowsError(try transfer.committed(token: Data([0])))
    XCTAssertEqual(try transfer.committed(token: chunk.token), Data([1]) + chunk.token)
    XCTAssertThrowsError(try transfer.committed(token: chunk.token))
  }
  func testCompleteDoesNotCommitOpenChunkAndUnknownFirmwareStaysBlocked() throws {
    var transfer = Whoop4Transfer()
    _ = try transfer.receive(metadata(1))
    let record = try WhoopFrame.parse(
      WhoopFrame.encode4(
        type: 47, sequence: 25, command: 0, payload: Data(repeating: 0, count: 73)),
      generation: .whoop4)
    _ = try transfer.receive(record)
    XCTAssertThrowsError(try transfer.receive(metadata(3)))
    XCTAssertFalse(
      WhoopReadProtocol.canRetrieve(generation: .whoop4, applicationFirmware: "17.2.2.0"))
    XCTAssertFalse(
      WhoopReadProtocol.canRetrieve(generation: .whoop5, applicationFirmware: "50.42.1.0"))
  }
  func testInterruptedTransferCannotAcknowledgeOldChunk() throws {
    var transfer = Whoop4Transfer()
    _ = try transfer.receive(metadata(1))
    let end = try metadata(2, payload: Data(repeating: 0, count: 18))
    _ = try transfer.receive(record())
    _ = try transfer.receive(end)
    transfer.interrupt()
    XCTAssertThrowsError(try transfer.committed(token: Data(repeating: 0, count: 8)))
  }
  private func record() throws -> WhoopFrame {
    try WhoopFrame.parse(
      WhoopFrame.encode4(
        type: 47, sequence: 25, command: 0, payload: Data(repeating: 0, count: 73)),
      generation: .whoop4)
  }
  private func metadata(_ type: UInt8, payload: Data = Data()) throws -> WhoopFrame {
    try WhoopFrame.parse(
      WhoopFrame.encode4(type: 49, sequence: 0, command: type, payload: payload),
      generation: .whoop4)
  }
}

extension HistoryTransferTests {
  func testRawHistoryBackupReplayAndFailureDoNotLoseCheckpoint() async throws {
    let store = try TempoStore(path: ":memory:")
    let id = UUID()
    let raw = try metadata(2, payload: Data(repeating: 0, count: 18)).raw
    try await store.commitHistory(
      deviceID: id, samples: [], cursor: Data([1]), rawFrames: [raw, raw])
    let before = try await store.historyFrameCount(deviceID: id)
    XCTAssertEqual(before, 1)
    do {
      try await store.commitHistory(
        deviceID: id, samples: [], cursor: Data([2]), rawFrames: [Data([0])])
      XCTFail("bad raw frame must rollback")
    } catch {}
    let cursor = try await store.checkpoint(deviceID: id)
    XCTAssertEqual(cursor, Data([1]))
    let archive = try await store.exportArchive()
    let restored = try TempoStore(path: ":memory:")
    try await restored.importArchive(archive)
    try await restored.importArchive(archive)
    let count = try await restored.historyFrameCount(deviceID: id)
    XCTAssertEqual(count, 1)
  }
}

extension HistoryTransferTests {
  func testAssemblerMakesDroppedBytesVisibleBeforeAnyHistoryAck() {
    var assembler = FrameAssembler(generation: .whoop4)
    var corrupt = WhoopFrame.encode4(
      type: 47, sequence: 24, command: 0, payload: Data(repeating: 0, count: 80))
    corrupt[23] ^= 1
    _ = assembler.append(corrupt)
    XCTAssertGreaterThan(assembler.discardedBytes, 0)
    var oversized = FrameAssembler(generation: .whoop4)
    _ = oversized.append(Data(repeating: 0, count: 9000))
    XCTAssertEqual(oversized.discardedBytes, 9000)
  }
  func testUnsupportedSpecialEndTokensCannotAdvanceDeviceRetention() throws {
    var transfer = Whoop4Transfer()
    _ = try transfer.receive(metadata(1))
    XCTAssertThrowsError(
      try transfer.receive(
        metadata(2, payload: Data(repeating: 0, count: 10) + Data(repeating: 0xfe, count: 8))))
  }
}

extension HistoryTransferTests {
  func testEmptyEndCannotAcknowledgeAnUnobservedChunk() throws {
    var transfer = Whoop4Transfer()
    _ = try transfer.receive(metadata(1))
    XCTAssertThrowsError(try transfer.receive(metadata(2, payload: Data(repeating: 0, count: 18))))
  }
}

extension HistoryTransferTests {
  func testNextChunkStartAfterCommitPreservesContinuousTransfer() throws {
    var transfer = Whoop4Transfer()
    for token in [Data([1, 0, 0, 0, 0, 0, 0, 0]), Data([2, 0, 0, 0, 0, 0, 0, 0])] {
      _ = try transfer.receive(metadata(1))
      _ = try transfer.receive(record())
      guard
        case .chunk(let chunk) = try transfer.receive(
          metadata(2, payload: Data(repeating: 0, count: 10) + token))
      else { return XCTFail("chunk") }
      _ = try transfer.committed(token: chunk.token)
    }
    guard case .complete = try transfer.receive(metadata(3)) else { return XCTFail("complete") }
  }
  func testLegacyBackupWithNoRawFramesStillImports() async throws {
    var archive = BackupArchive(payload: Data("{\"measurements\":[],\"revisions\":[]}".utf8))
    archive.schemaVersion = 1
    let store = try TempoStore(path: ":memory:")
    try await store.importArchive(archive)
  }
}

extension HistoryTransferTests {
  func testEndCannotCloseWhileAnotherChannelHasAPartialFrame() throws {
    let data = try record().raw
    var payloadChannel = FrameAssembler(generation: .whoop4)
    var metadataChannel = FrameAssembler(generation: .whoop4)
    _ = payloadChannel.append(data.prefix(12))
    _ = metadataChannel.append(try metadata(2, payload: Data(repeating: 0, count: 18)).raw)
    XCTAssertFalse(
      HistoryAssemblyGate.canClose(bufferedBytes: [
        payloadChannel.bufferedBytes, metadataChannel.bufferedBytes,
      ]))
    XCTAssertEqual(payloadChannel.append(data.dropFirst(12)).count, 1)
    XCTAssertTrue(
      HistoryAssemblyGate.canClose(bufferedBytes: [
        payloadChannel.bufferedBytes, metadataChannel.bufferedBytes,
      ]))
  }
}

extension HistoryTransferTests {
  func testSchemaOneUpgradePreservesObservationsAndPendingUpload() async throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(
      "tempo-migration-\(UUID()).sqlite"
    ).path
    defer { try? FileManager.default.removeItem(atPath: path) }
    let original = try TempoStore(path: path)
    let id = UUID()
    let sample = Measurement(
      deviceID: id, kind: .heartRate, timestamp: Date(), value: 70, origin: .measured,
      transport: "fixture")
    try await original.insert([sample])
    var db: OpaquePointer?
    XCTAssertEqual(sqlite3_open(path, &db), SQLITE_OK)
    XCTAssertEqual(
      sqlite3_exec(db, "DROP TABLE history_frames; PRAGMA user_version=1;", nil, nil, nil),
      SQLITE_OK)
    sqlite3_close(db)
    let upgraded = try TempoStore(path: path)
    let records = try await upgraded.measurements(from: .distantPast, to: .distantFuture)
    XCTAssertEqual(records.map(\.id), [sample.id])
    let pending = try await upgraded.pendingCount()
    XCTAssertEqual(pending, 1)
    let archive = try await upgraded.exportArchive()
    XCTAssertEqual(archive.schemaVersion, 2)
    let rawCount = try await upgraded.historyFrameCount(deviceID: id)
    XCTAssertEqual(rawCount, 0)
  }
}

extension HistoryTransferTests {
  func testRecentBackfillIsNeverLabelledLive() {
    let now = Date()
    let sample = Measurement(
      deviceID: UUID(), kind: .heartRate, timestamp: now, value: 80, origin: .measured,
      transport: "whoop4-history-v24")
    XCTAssertEqual(
      CollectionPresentation(sample: sample, connected: true, wear: .unknown, now: now).state,
      .recent)
  }
}

extension HistoryTransferTests {
  func testUnconfirmedHistoricalContactPreservesValueWithoutCountingChargingBand() throws {
    let id = UUID()
    var body = Data(repeating: 0, count: 81)
    let time: UInt32 = 1_700_000_000
    for i in 0..<4 { body[4+i] = UInt8(truncatingIfNeeded: time >> (i*8)) }
    body[14] = 80
    let frame = try WhoopFrame.parse(WhoopFrame.encode4(type: 47, sequence: 24, command: 0, payload: body), generation: .whoop4)
    let sample = try XCTUnwrap(Whoop4History.decode(frame, deviceID: id, firmware: "41.17.6.0").first)
    XCTAssertEqual(sample.value, 80)
    XCTAssertFalse(sample.valid)
    XCTAssertEqual(sample.wear, .unknown)
  }
}
