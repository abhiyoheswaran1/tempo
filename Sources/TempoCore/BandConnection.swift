import Foundation

public enum BandLinkState: String, Sendable {
  case disconnected, connecting, connected, disconnecting
}
public struct BandConnectionLedger: Sendable {
  public private(set) var pausedIDs: Set<UUID>
  public private(set) var target: UUID?
  private var states: [UUID: BandLinkState] = [:]
  public init(pausedIDs: Set<UUID> = []) { self.pausedIDs = pausedIDs }
  public func state(_ id: UUID) -> BandLinkState { states[id] ?? .disconnected }
  public func canReplaceBinding(_ id: UUID) -> Bool { state(id) == .disconnected }
  public func canOfferConnection(_ id: UUID) -> Bool { state(id) == .disconnected }
  public mutating func requestConnect(_ id: UUID) -> Bool {
    guard state(id) != .connected, state(id) != .connecting else { return false }
    if let old = target, old != id, state(old) != .disconnected { states[old] = .disconnecting }
    pausedIDs.remove(id)
    target = id
    states[id] = .connecting
    return true
  }
  public mutating func didConnect(_ id: UUID) -> Bool {
    guard target == id, !pausedIDs.contains(id) else { return false }
    states[id] = .connected
    return true
  }
  public mutating func disconnect(_ id: UUID) {
    pausedIDs.insert(id)
    if target == id { target = nil }
    states[id] = state(id) == .disconnected ? .disconnected : .disconnecting
  }
  public mutating func lostConnection(_ id: UUID) {
    states[id] = shouldReconnect(id) ? .connecting : .disconnected
  }
  public func shouldReconnect(_ id: UUID) -> Bool { target == id && !pausedIDs.contains(id) }
  public mutating func failedConnection(_ id: UUID) { states[id] = .disconnected }
  public mutating func suspend() {
    target = nil
    states = [:]
  }
}
public enum BandGenerationEvidence {
  public static func resolve(hasWhoop4Service: Bool, hasWhoop5Service: Bool) -> DeviceGeneration? {
    guard hasWhoop4Service != hasWhoop5Service else { return nil }
    return hasWhoop5Service ? .whoop5 : .whoop4
  }
  public static func correct(_ device: RegisteredDevice, to generation: DeviceGeneration)
    -> RegisteredDevice
  {
    var result = device
    if result.name == "Whoop 4" || result.name == "Whoop 5" {
      result.name = generation == .whoop4 ? "Whoop 4" : "Whoop 5"
    }
    result.generation = generation
    result.capabilities = .make(generation: generation, firmware: result.firmware)
    return result
  }
  public static func archivedDevice(id: UUID, revisions: [Revision]) -> RegisteredDevice? {
    revisions.filter { $0.kind == "device" && $0.entityID == id && !$0.deleted }.sorted {
      $0.createdAt > $1.createdAt
    }.compactMap { try? JSONDecoder().decode(RegisteredDevice.self, from: $0.payload) }.first
  }
}
