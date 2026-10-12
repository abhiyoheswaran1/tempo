import Foundation

public enum DeviceGeneration: String, Codable, Sendable, CaseIterable { case whoop4, whoop5 }
public enum Support: String, Codable, Sendable { case verified, experimental, unsupported, unknown }
public enum Capability: String, Codable, Sendable, CaseIterable {
  case liveHeartRate, rrIntervals, history, motion, wearDetection, battery, temperature,
    respiration, spo2, haptics, firmwareAlarm, identity, firmware
}
public struct CapabilityProfile: Codable, Sendable, Equatable {
  public var states: [Capability: Support]
  public var evidenceVersion = "2026-10-12"
  public subscript(_ capability: Capability) -> Support { states[capability] ?? .unknown }
  public static func make(generation: DeviceGeneration, firmware: String?) -> Self {
    var s = Dictionary(uniqueKeysWithValues: Capability.allCases.map { ($0, Support.unknown) })
    // Verified public standard contract; instance availability still requires discovery.
    s[.liveHeartRate] = .experimental
    s[.rrIntervals] = .experimental
    if generation == .whoop4 && firmware == "41.17.6.0" {
      for c in [
        Capability.history, .motion, .wearDetection, .battery, .haptics, .firmwareAlarm, .identity,
        .firmware,
      ] { s[c] = .experimental }
      s[.temperature] = .unsupported
      s[.respiration] = .unsupported
      s[.spo2] = .unsupported
    }
    if generation == .whoop5 && firmware == "50.42.1.0" {
      for c in [
        Capability.history, .motion, .battery, .temperature, .haptics, .firmwareAlarm, .identity,
        .firmware,
      ] { s[c] = .experimental }
      s[.wearDetection] = .unknown
      s[.respiration] = .unsupported
      s[.spo2] = .unsupported
    }
    return Self(states: s)
  }
}
public enum WearState: String, Codable, Sendable { case onBody, offBody, unknown }
public enum MetricKind: String, Codable, Sendable, CaseIterable {
  case heartRate, restingHeartRate, rmssd, sdnn, temperature, respiratoryRate, oxygenSaturation,
    weight
}
public enum Origin: String, Codable, Sendable {
  case measured, derived, imported, manual, synthetic
}
public struct RegisteredDevice: Codable, Sendable, Identifiable, Equatable {
  public var id: UUID
  public var generation: DeviceGeneration
  public var name: String
  public var hardwareIdentityHash: String?
  public var firmware: String?
  public var capabilities: CapabilityProfile
  public var registeredAt: Date
  public init(
    id: UUID = UUID(), generation: DeviceGeneration, name: String, firmware: String? = nil
  ) {
    self.id = id
    self.generation = generation
    self.name = name
    self.firmware = firmware
    capabilities = .make(generation: generation, firmware: firmware)
    registeredAt = Date()
  }
}
