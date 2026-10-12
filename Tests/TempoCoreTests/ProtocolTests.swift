import XCTest

@testable import TempoCore

final class ProtocolTests: XCTestCase {
  func testStandardHeartRateWithIntervals() throws {
    let result = try HeartRatePacket.parse(Data([0x16, 72, 0, 4, 0, 4]))
    XCTAssertEqual(result.bpm, 72)
    XCTAssertEqual(result.rrMilliseconds, [1000, 1000])
    XCTAssertEqual(result.contact, .onBody)
  }
  func testMalformedStandardPackets() {
    for bytes: [UInt8] in [[], [1], [1, 2], [8, 70, 1], [16, 70, 1]] {
      XCTAssertThrowsError(try HeartRatePacket.parse(Data(bytes)))
    }
  }
  func testUnknownFirmwareDoesNotEnableHistory() {
    XCTAssertEqual(CapabilityProfile.make(generation: .whoop4, firmware: "new")[.history], .unknown)
    XCTAssertEqual(
      CapabilityProfile.make(generation: .whoop5, firmware: "50.42.1.0")[.spo2], .unsupported)
  }
  func testWhoopFourFrameRejectsBadCRCAndTruncation() throws {
    let frame = WhoopFrame.encode4(type: 35, sequence: 1, command: 26, payload: Data())
    XCTAssertEqual(try WhoopFrame.parse(frame, generation: .whoop4).command, 26)
    XCTAssertThrowsError(try WhoopFrame.parse(frame.dropLast(), generation: .whoop4))
    var corrupt = frame
    corrupt[4] ^= 1
    XCTAssertThrowsError(try WhoopFrame.parse(corrupt, generation: .whoop4))
  }
  func testWhoopFiveDocumentedHello() throws {
    let hello = Data([0xAA, 1, 8, 0, 0, 1, 0xE6, 0x71, 35, 1, 145, 1, 0x36, 0x3E, 0x5C, 0x8D])
    XCTAssertEqual(try WhoopFrame.parse(hello, generation: .whoop5).command, 145)
    XCTAssertThrowsError(try WhoopFrame.parse(hello, generation: .whoop4))
  }
  func testFragmentationAndBoundedGarbage() throws {
    let f = WhoopFrame.encode4(type: 35, sequence: 0, command: 26, payload: Data())
    var assembler = FrameAssembler(generation: .whoop4)
    XCTAssertTrue(assembler.append(f.prefix(5)).isEmpty)
    XCTAssertEqual(assembler.append(f.dropFirst(5)), [f])
    _ = assembler.append(Data(repeating: 0xAA, count: 100_000))
    XCTAssertLessThanOrEqual(assembler.bufferedBytes, 8192)
  }
}
