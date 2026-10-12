import Foundation

/// Wire facts are version-bounded in docs/ProtocolResearch.md; no service authentication is implemented.
public enum WhoopReadProtocol {
  public struct Reply: Sendable {
    public let command: UInt8
    public let origin: UInt8
    public let result: UInt8
    public let body: Data
  }
  public static func frame5(type: UInt8, sequence: UInt8, command: UInt8, body: Data) -> Data {
    var inner = Data([type, sequence, command])
    inner.append(body)
    while inner.count % 4 != 0 { inner.append(0) }
    let length = inner.count + 4
    var header = Data([
      0xaa, 1, UInt8(truncatingIfNeeded: length), UInt8(truncatingIfNeeded: length >> 8), 0, 1,
    ])
    let crc = Checksums.crc16(header)
    header.append(contentsOf: [UInt8(truncatingIfNeeded: crc), UInt8(truncatingIfNeeded: crc >> 8)])
    header.append(inner)
    let sum = Checksums.crc32(inner)
    header.append(contentsOf: (0..<4).map { UInt8(truncatingIfNeeded: sum >> ($0 * 8)) })
    return header
  }
  public static func command(
    generation: DeviceGeneration, sequence: UInt8, command: UInt8, body: Data
  ) -> Data {
    generation == .whoop4
      ? WhoopFrame.encode4(type: 35, sequence: sequence, command: command, payload: body)
      : frame5(type: 35, sequence: sequence, command: command, body: body)
  }
  public static func reply(_ input: WhoopFrame) throws -> Reply {
    let frame = try WhoopFrame.parse(input.raw, generation: input.generation)
    let start = frame.generation == .whoop4 ? 7 : 11
    guard frame.type == 36, frame.bodyEnd >= start + 2 else { throw PacketError.truncated }
    return Reply(
      command: frame.command, origin: frame.raw[start], result: frame.raw[start + 1],
      body: Data(frame.raw[(start + 2)..<frame.bodyEnd]))
  }
  public static func applicationFirmware(_ frame: WhoopFrame) throws -> String {
    let response = try reply(frame)
    let b = Array(response.body)
    guard response.result == 1, b.first == 1 else { throw PacketError.unsupported }
    if frame.generation == .whoop4 {
      guard response.command == 7, b.count == 68 else { throw PacketError.malformed }
      let values = (0..<4).map { u32(b, 1 + $0 * 4) }
      guard values[0] == 41, values.allSatisfy({ $0 <= 100_000 }) else {
        throw PacketError.implausible
      }
      return values.map(String.init).joined(separator: ".")
    }
    guard response.command == 145, b.count == 107, b[91] == 50 else {
      throw PacketError.unsupported
    }
    return "\(b[91]).\(b[92]).\(b[93]).\(u32(b,94))"
  }
  public static func recordCountEstimate(_ body: Data) throws -> UInt32 {
    let b = Array(body)
    guard b.count == 65, b[0] == 1, u32(b, 21) > 0 else { throw PacketError.malformed }
    return u32(b, 25)
  }
  public static func canRetrieve(generation: DeviceGeneration, applicationFirmware: String?) -> Bool
  {
    generation == .whoop4 && applicationFirmware == "41.17.6.0"
  }
}
public struct HistoryChunk: Sendable {
  public let frames: [Data]
  public let token: Data
}
/// Legacy transfer only. W5 metadata/initialization are never inferred by shifting W4 offsets.
public struct Whoop4Transfer: Sendable {
  public enum Event: Sendable {
    case none
    case chunk(HistoryChunk)
    case repeatCommitted(Data)
    case complete
  }
  private enum State: Sendable {
    case idle, receiving
    case committing(Data)
    case complete, failed
  }
  private var state = State.idle
  private var frames: [Data] = []
  private var bytes = 0
  private var lastCommitted: Data?
  public init() {}
  public mutating func interrupt() {
    state = .failed
    frames = []
    bytes = 0
  }
  public mutating func receive(_ input: WhoopFrame) throws -> Event {
    let frame = try WhoopFrame.parse(input.raw, generation: .whoop4)
    guard input.generation == .whoop4 else { throw PacketError.unsupported }
    if frame.type == 49 {
      switch frame.command {
      case 1:
        switch state {
        case .idle: break
        case .receiving where frames.isEmpty: break
        default: throw PacketError.malformed
        }
        state = .receiving
      case 2:
        guard frame.bodyEnd >= 25 else { throw PacketError.truncated }
        let token = Data(frame.raw[17..<25])
        let word = u32(Array(token), 0)
        guard word != 0xfefe_fefe, word != 0xfdfd_fdfd, word != 0xffff_ffff else {
          throw PacketError.unsupported
        }
        if case .committing(let pending) = state, pending == token { return .none }
        guard case .receiving = state else { throw PacketError.malformed }
        if frames.isEmpty, lastCommitted == token { return .repeatCommitted(Data([1]) + token) }
        guard !frames.isEmpty else { throw PacketError.malformed }
        frames.append(frame.raw)
        state = .committing(token)
        return .chunk(HistoryChunk(frames: frames, token: token))
      case 3:
        guard case .receiving = state, frames.isEmpty else { throw PacketError.malformed }
        state = .complete
        return .complete
      default: throw PacketError.unsupported
      }
    } else if [UInt8(47), 48, 52].contains(frame.type) {
      guard case .receiving = state, bytes + frame.raw.count <= 2 * 1024 * 1024,
        frames.count < 10_000
      else { throw PacketError.malformed }
      frames.append(frame.raw)
      bytes += frame.raw.count
    }
    return .none
  }
  public mutating func committed(token: Data) throws -> Data {
    guard case .committing(let pending) = state, pending == token else {
      throw PacketError.malformed
    }
    frames = []
    bytes = 0
    lastCommitted = token
    state = .receiving
    return Data([1]) + token
  }
}

public enum HistoryAssemblyGate {
  public static func canClose(bufferedBytes: [Int]) -> Bool {
    bufferedBytes.allSatisfy { $0 == 0 }
  }
}
