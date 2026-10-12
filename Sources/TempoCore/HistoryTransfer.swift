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
    guard b.count == 65 || (b.count == 67 && b[65] == 0 && b[66] == 0), b[0] == 1, u32(b, 21) > 0
    else { throw PacketError.malformed }
    return u32(b, 25)
  }
  public static func canRetrieve(
    generation: DeviceGeneration, applicationFirmware: String?, storedRecordEstimate: UInt32? = nil
  ) -> Bool {
    switch generation {
    case .whoop4: return applicationFirmware == "41.17.6.0"
    case .whoop5: return applicationFirmware == "50.42.1.0" && (storedRecordEstimate ?? 0) > 0
    }
  }
}
public struct HistoryChunk: Sendable {
  public let frames: [Data]
  public let token: Data
  public let generation: DeviceGeneration
  public let attemptID: UUID
  public init(
    frames: [Data], token: Data, generation: DeviceGeneration = .whoop4, attemptID: UUID = UUID()
  ) {
    self.frames = frames
    self.token = token
    self.generation = generation
    self.attemptID = attemptID
  }
}
/// Shared durability lifecycle with independently evidenced per-generation metadata boundaries.
public struct BandHistoryTransfer: Sendable {
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
  public let attemptID = UUID()
  public var hasStarted: Bool {
    switch state {
    case .idle, .failed: false
    case .receiving, .committing(_), .complete: true
    }
  }
  private var state = State.idle
  private var frames: [Data] = []
  private var bytes = 0
  private var lastCommitted: Data?
  private let generation: DeviceGeneration
  public init(generation: DeviceGeneration = .whoop4) { self.generation = generation }
  public mutating func interrupt() {
    state = .failed
    frames = []
    bytes = 0
  }
  public mutating func receive(_ input: WhoopFrame) throws -> Event {
    let frame = try WhoopFrame.parse(input.raw, generation: generation)
    guard input.generation == generation else { throw PacketError.unsupported }
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
        let tokenStart = generation == .whoop4 ? 17 : 21
        guard frame.bodyEnd >= tokenStart + 8 else { throw PacketError.truncated }
        let token = Data(frame.raw[tokenStart..<(tokenStart + 8)])
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
        return .chunk(
          HistoryChunk(frames: frames, token: token, generation: generation, attemptID: attemptID))
      case 3:
        guard case .receiving = state, frames.isEmpty else { throw PacketError.malformed }
        state = .complete
        return .complete
      default: throw PacketError.unsupported
      }
    } else if (generation == .whoop4 ? [UInt8(47), 48, 52] : [UInt8(47), 48, 52, 54]).contains(
      frame.type)
    {
      guard case .receiving = state, bytes + frame.raw.count <= 2 * 1024 * 1024,
        frames.count < 10_000
      else { throw PacketError.malformed }
      frames.append(frame.raw)
      bytes += frame.raw.count
    }
    return .none
  }
  public mutating func committed(token: Data, attemptID: UUID) throws -> Data {
    guard self.attemptID == attemptID else { throw PacketError.unsupported }
    return try committed(token: token)
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

/// Backward-compatible W4 default; native callers explicitly choose the generation.
public typealias Whoop4Transfer = BandHistoryTransfer

public enum HistoryRequestDeadline {
  public static func shouldExpire(command: UInt8, streamStarted: Bool) -> Bool {
    command != 22 || !streamStarted
  }
}
