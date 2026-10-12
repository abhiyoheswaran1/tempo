import Foundation

public enum PacketError: Error, Equatable {
  case truncated, malformed, checksum, unsupported, implausible
}
public struct HeartRatePacket: Equatable, Sendable {
  public var bpm: Int
  public var rrMilliseconds: [Double]
  public var contact: WearState
  public static func parse(_ data: Data) throws -> Self {
    let b = Array(data)
    guard b.count >= 2 else { throw PacketError.truncated }
    let flags = b[0]
    guard flags & 0xE0 == 0 else { throw PacketError.unsupported }
    var i = 1
    let hr: Int
    if flags & 1 != 0 {
      guard b.count >= 3 else { throw PacketError.truncated }
      hr = Int(b[1]) | Int(b[2]) << 8
      i = 3
    } else {
      hr = Int(b[1])
      i = 2
    }
    if flags & 8 != 0 {
      guard i + 2 <= b.count else { throw PacketError.truncated }
      i += 2
    }
    var rr: [Double] = []
    if flags & 16 != 0 {
      guard i < b.count, (b.count - i) % 2 == 0 else { throw PacketError.truncated }
      while i < b.count {
        let ticks = Int(b[i]) | Int(b[i + 1]) << 8
        if ticks > 0 { rr.append(Double(ticks) * 1000 / 1024) }
        i += 2
      }
    } else if i != b.count {
      throw PacketError.malformed
    }
    guard (25...240).contains(hr) else { throw PacketError.implausible }
    return Self(
      bpm: hr, rrMilliseconds: rr,
      contact: flags & 4 == 0 ? .unknown : (flags & 2 != 0 ? .onBody : .offBody))
  }
}
public enum Checksums {
  public static func crc8(_ bytes: some Sequence<UInt8>) -> UInt8 {
    var c: UInt8 = 0
    for b in bytes {
      c ^= b
      for _ in 0..<8 { c = c & 0x80 != 0 ? (c &<< 1) ^ 7 : c &<< 1 }
    }
    return c
  }
  public static func crc16(_ bytes: some Sequence<UInt8>) -> UInt16 {
    var c: UInt16 = 0xffff
    for b in bytes {
      c ^= UInt16(b)
      for _ in 0..<8 { c = c & 1 != 0 ? (c >> 1) ^ 0xa001 : c >> 1 }
    }
    return c
  }
  public static func crc32(_ bytes: some Sequence<UInt8>) -> UInt32 {
    var c: UInt32 = 0xffff_ffff
    for b in bytes {
      c ^= UInt32(b)
      for _ in 0..<8 { c = c & 1 != 0 ? (c >> 1) ^ 0xedb8_8320 : c >> 1 }
    }
    return c ^ 0xffff_ffff
  }
}
public struct WhoopFrame: Sendable, Equatable {
  public let raw: Data
  public let generation: DeviceGeneration
  public let type: UInt8
  public let sequence: UInt8
  public let command: UInt8
  public let bodyEnd: Int
  public static func parse(_ data: Data, generation: DeviceGeneration) throws -> Self {
    let b = Array(data)
    guard b.count >= 11 else { throw PacketError.truncated }
    guard b[0] == 0xaa else { throw PacketError.malformed }
    let start: Int
    let length: Int
    if generation == .whoop4 {
      length = Int(b[1]) | Int(b[2]) << 8
      guard length >= 7, length <= 8188, b.count == length + 4 else { throw PacketError.malformed }
      guard Checksums.crc8(b[1...2]) == b[3] else { throw PacketError.checksum }
      start = 4
    } else {
      guard b.count >= 16, b[1] == 1 else { throw PacketError.unsupported }
      let declared = Int(b[2]) | Int(b[3]) << 8
      guard declared >= 8, (declared - 4) % 4 == 0, declared + 8 == b.count, b.count <= 8192 else {
        throw PacketError.malformed
      }
      guard Checksums.crc16(b[0..<6]) == u16(b, 6) else { throw PacketError.checksum }
      length = b.count - 4
      start = 8
    }
    guard Checksums.crc32(b[start..<length]) == u32(b, length) else { throw PacketError.checksum }
    return Self(
      raw: data, generation: generation, type: b[start], sequence: b[start + 1],
      command: b[start + 2], bodyEnd: length)
  }
  public static func encode4(type: UInt8, sequence: UInt8, command: UInt8, payload: Data) -> Data {
    let inner = [type, sequence, command] + Array(payload)
    let length = inner.count + 4
    let l = [UInt8(length & 255), UInt8(length >> 8)]
    let c = Checksums.crc32(inner)
    return Data(
      [0xaa] + l + [Checksums.crc8(l)] + inner
        + (0..<4).map { UInt8(truncatingIfNeeded: c >> ($0 * 8)) })
  }
  public func liveHR() throws -> (Date, HeartRatePacket) {
    guard type == 40 else { throw PacketError.unsupported }
    let b = Array(raw)
    let timeOffset = generation == .whoop4 ? 6 : 10
    let hrOffset = generation == .whoop4 ? 12 : 16
    guard bodyEnd >= hrOffset + 2 else { throw PacketError.truncated }
    let count = Int(b[hrOffset + 1])
    guard hrOffset + 2 + count * 2 <= bodyEnd else { throw PacketError.truncated }
    let hr = Int(b[hrOffset])
    guard (25...240).contains(hr) else { throw PacketError.implausible }
    let seconds = u32(b, timeOffset)
    guard seconds >= 1_577_836_800 else { throw PacketError.implausible }
    let rr = (0..<count).compactMap { n -> Double? in
      let v = u16(b, hrOffset + 2 + n * 2)
      guard v != 0 else { return nil }
      return generation == .whoop4 ? Double(v) : Double((UInt32(v) * 1000 + 512) / 1024)
    }
    return (
      Date(timeIntervalSince1970: Double(seconds)),
      HeartRatePacket(bpm: hr, rrMilliseconds: rr, contact: .unknown)
    )
  }
}
func u16(_ b: [UInt8], _ i: Int) -> UInt16 { UInt16(b[i]) | UInt16(b[i + 1]) << 8 }
func u32(_ b: [UInt8], _ i: Int) -> UInt32 {
  (0..<4).reduce(0) { $0 | UInt32(b[i + $1]) << ($1 * 8) }
}
public struct FrameAssembler: Sendable {
  public let generation: DeviceGeneration
  private var buffer: [UInt8] = []
  public private(set) var discardedBytes = 0
  public var bufferedBytes: Int { buffer.count }
  public init(generation: DeviceGeneration) { self.generation = generation }
  public mutating func append(_ fragment: Data) -> [Data] {
    if fragment.count > 8192 {
      discardedBytes += fragment.count + buffer.count
      buffer.removeAll()
      return []
    }
    buffer += fragment
    if buffer.count > 8192 {
      discardedBytes += buffer.count
      buffer.removeAll()
      return []
    }
    var frames: [Data] = []
    while buffer.count >= 4 {
      guard buffer[0] == 0xaa else {
        discardedBytes += 1
        buffer.removeFirst()
        continue
      }
      let count = generation == .whoop4 ? Int(u16(buffer, 1)) + 4 : Int(u16(buffer, 2)) + 8
      guard (11...8192).contains(count) else {
        discardedBytes += 1
        buffer.removeFirst()
        continue
      }
      if generation == .whoop4 && Checksums.crc8(buffer[1...2]) != buffer[3] {
        discardedBytes += 1
        buffer.removeFirst()
        continue
      }
      if generation == .whoop5 {
        guard buffer[1] == 1 else {
          discardedBytes += 1
        buffer.removeFirst()
          continue
        }
        if buffer.count < 8 { break }
        if Checksums.crc16(buffer[0..<6]) != u16(buffer, 6) {
          discardedBytes += 1
        buffer.removeFirst()
          continue
        }
      }
      guard buffer.count >= count else { break }
      let f = Data(buffer.prefix(count))
      if (try? WhoopFrame.parse(f, generation: generation)) != nil {
        frames.append(f)
        buffer.removeFirst(count)
      } else {
        discardedBytes += 1
        buffer.removeFirst()
      }
    }
    return frames
  }
}
