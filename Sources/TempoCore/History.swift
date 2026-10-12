import Compression
import Foundation

public enum Whoop4History {
  public static func decode(_ frame: WhoopFrame, deviceID: UUID, firmware: String) throws
    -> [Measurement]
  {
    guard frame.generation == .whoop4, frame.type == 47, firmware == "41.17.6.0" else {
      throw PacketError.unsupported
    }
    let b = Array(frame.raw)
    if frame.sequence == 25 {
      guard b.count == 84 else { throw PacketError.malformed }
      return []
    }
    guard frame.sequence == 24 else { throw PacketError.unsupported }
    guard frame.bodyEnd >= 84 else { throw PacketError.truncated }
    let seconds = u32(b, 11)
    guard seconds >= 1_577_836_800, Double(seconds) <= Date().timeIntervalSince1970 + 300 else {
      throw PacketError.implausible
    }
    let count = Int(b[22])
    guard count <= 4, 23 + count * 2 <= 33 else { throw PacketError.malformed }
    let hr = Int(b[21])
    guard (25...240).contains(hr) else { throw PacketError.implausible }
    let rr = (0..<count).compactMap { n -> Double? in
      let v = u16(b, 23 + n * 2)
      return v == 0 ? nil : Double(v)
    }
    // Preserve uncertain contact evidence. A zero flag is excluded from analytics, without claiming verified off-body status.
    return [
      Measurement(
        deviceID: deviceID, kind: .heartRate,
        timestamp: Date(timeIntervalSince1970: Double(seconds)), value: Double(hr),
        origin: .measured, transport: "whoop4-history-v24", recordKey: StableID.hash(frame.raw),
        rrMilliseconds: rr,
        quality: b[55] == 0 ? ["experimental-contact-zero"] : [], wear: .unknown)
    ]
  }
}
public enum SensorCompression {
  public static let maximumDecodedBytes = 4 * 1024 * 1024
  public static func encode(_ data: Data) throws -> Data {
    guard data.count <= maximumDecodedBytes else { throw StoreError.invalidArchive }
    let capacity = max(1024, data.count + data.count / 4 + 1024)
    var target = [UInt8](repeating: 0, count: capacity)
    let count = data.withUnsafeBytes { src in
      target.withUnsafeMutableBytes { dst in
        compression_encode_buffer(
          dst.baseAddress!.assumingMemoryBound(to: UInt8.self), capacity,
          src.baseAddress!.assumingMemoryBound(to: UInt8.self), data.count, nil, COMPRESSION_LZFSE)
      }
    }
    guard count > 0 else { throw StoreError.invalidArchive }
    var result = Data("TLZF1".utf8)
    result.append(
      contentsOf: (0..<4).map { UInt8(truncatingIfNeeded: UInt32(data.count) >> ($0 * 8)) })
    result.append(contentsOf: target.prefix(count))
    return result
  }
  public static func decode(_ data: Data) throws -> Data {
    let b = Array(data)
    guard b.count > 9, Array(b[0..<5]) == Array("TLZF1".utf8) else {
      throw StoreError.invalidArchive
    }
    let length = Int(u32(b, 5))
    guard length > 0, length <= maximumDecodedBytes else { throw StoreError.invalidArchive }
    var output = [UInt8](repeating: 0, count: length)
    let size = output.withUnsafeMutableBytes { dst in
      data.dropFirst(9).withUnsafeBytes { src in
        compression_decode_buffer(
          dst.baseAddress!.assumingMemoryBound(to: UInt8.self), length,
          src.baseAddress!.assumingMemoryBound(to: UInt8.self), data.count - 9, nil,
          COMPRESSION_LZFSE)
      }
    }
    guard size == length else { throw StoreError.invalidArchive }
    return Data(output)
  }
}

public enum Whoop5History {
  public static func decode(_ input: WhoopFrame, deviceID: UUID, firmware: String) throws
    -> [Measurement]
  {
    guard firmware == "50.42.1.0", input.generation == .whoop5 else {
      throw PacketError.unsupported
    }
    let frame = try WhoopFrame.parse(input.raw, generation: .whoop5)
    guard frame.type == 47, frame.sequence == 18 else { throw PacketError.unsupported }
    guard frame.raw.count == 124, frame.bodyEnd == 120 else { throw PacketError.malformed }
    let b = Array(frame.raw)
    let seconds = u32(b, 15)
    guard seconds >= 1_577_836_800, Double(seconds) <= Date().timeIntervalSince1970 + 300,
      (25...240).contains(Int(b[22]))
    else { throw PacketError.implausible }
    guard b[23] <= 4 else { throw PacketError.malformed }
    // Primary HR is documented. Alternate-HR/quality flags are opaque; never choose another HR from them.
    var sample = Measurement(
      deviceID: deviceID, kind: .heartRate,
      timestamp: Date(timeIntervalSince1970: Double(seconds)), value: Double(b[22]),
      origin: .measured, transport: "whoop5-history-r18-experimental",
      recordKey: "r18:\(u32(b,11)):\(seconds)", wear: .unknown)
    sample.qualityContext = ["opaqueR18CardiacFlags": b[33], "opaqueR18QualityFlags": b[36]]
    // Preserve RR in raw archive. Unresolved R18 quality is insufficient for overnight HRV inputs.
    return [sample]
  }
}
