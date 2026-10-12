import XCTest

@testable import TempoCore

final class HistoryTests: XCTestCase {
  func testV25DoesNotInventHeartRate() throws {
    var payload = Data(repeating: 0, count: 73)
    payload[4] = 0
    payload[5] = 0xf1
    payload[6] = 0x53
    payload[7] = 0x65
    let frame = WhoopFrame.encode4(type: 47, sequence: 25, command: 0, payload: payload)
    let decoded = try Whoop4History.decode(
      WhoopFrame.parse(frame, generation: .whoop4), deviceID: UUID(), firmware: "41.17.6.0")
    XCTAssertTrue(decoded.isEmpty)
  }
  func testUnknownFirmwareCannotDecodeHistory() throws {
    let frame = WhoopFrame.encode4(
      type: 47, sequence: 24, command: 0, payload: Data(repeating: 0, count: 81))
    XCTAssertThrowsError(
      try Whoop4History.decode(
        WhoopFrame.parse(frame, generation: .whoop4), deviceID: UUID(), firmware: "unknown"))
  }
  func testCompressionRoundTripAndLimit() throws {
    let data = Data(repeating: 42, count: 10000)
    XCTAssertEqual(try SensorCompression.decode(SensorCompression.encode(data)), data)
    XCTAssertThrowsError(try SensorCompression.decode(Data([1, 2, 3])))
  }
}
