import Foundation

public enum BodyPlacement: String, Codable, Sendable, CaseIterable {
  case unknown, wrist, upperArm, underwear
  public var title: String {
    switch self {
    case .unknown: return "Unknown / not recorded"
    case .wrist: return "Wrist"
    case .upperArm: return "Upper arm / bicep"
    case .underwear: return "Underwear / WHOOP Body"
    }
  }
}
/// User-reported context, not device-observed wear detection. Instants are UTC.
public struct PlacementRecord: Codable, Sendable, Identifiable, Hashable {
  public var id = UUID()
  public var deviceID: UUID
  public var placement: BodyPlacement
  public var effectiveFrom: Date
  public var timeZoneID: String
  public init(
    deviceID: UUID, placement: BodyPlacement, effectiveFrom: Date,
    timeZoneID: String = TimeZone.current.identifier
  ) {
    self.deviceID = deviceID
    self.placement = placement
    self.effectiveFrom = effectiveFrom
    self.timeZoneID = timeZoneID
  }
}
public enum PlacementTimeline {
  /// Conflicting edits create an uncertainty boundary including their earlier ancestry.
  public static func project(_ revisions: [Revision]) -> [PlacementRecord] {
    let groups = Dictionary(grouping: revisions.filter { $0.kind == "placement" }, by: \.entityID)
    return groups.flatMap { entityID, history -> [PlacementRecord] in
      let parents = Set(history.flatMap(\.parentIDs))
      let heads = history.filter { !parents.contains($0.id) }
      if heads.count == 1, let head = heads.first {
        return head.deleted
          ? []
          : ((try? JSONDecoder().decode(PlacementRecord.self, from: head.payload)).map { [$0] }
            ?? [])
      }
      let reports = history.compactMap {
        try? JSONDecoder().decode(PlacementRecord.self, from: $0.payload)
      }
      return Dictionary(grouping: reports, by: \.deviceID).flatMap { _, values in
        Dictionary(grouping: values, by: \.effectiveFrom).values.map { versions in
          var unknown = versions[0]
          unknown.id = entityID
          unknown.placement = .unknown
          return unknown
        }
      }
    }.sorted {
      if $0.effectiveFrom != $1.effectiveFrom { return $0.effectiveFrom > $1.effectiveFrom }
      return $0.deviceID.uuidString + $0.id.uuidString < $1.deviceID.uuidString + $1.id.uuidString
    }
  }

  public static func resolve(deviceID: UUID, at instant: Date, records: [PlacementRecord])
    -> BodyPlacement
  {
    let eligible = records.filter { $0.deviceID == deviceID && $0.effectiveFrom <= instant }
    guard let latest = eligible.map(\.effectiveFrom).max() else { return .unknown }
    let choices = Set(eligible.filter { $0.effectiveFrom == latest }.map(\.placement))
    return choices.count == 1 ? choices.first! : .unknown
  }
  public static func locations(samples: [Measurement], records: [PlacementRecord]) -> Set<
    BodyPlacement
  > {
    let grouped = Dictionary(grouping: records, by: \.deviceID)
    let index = grouped.mapValues { records in
      Dictionary(grouping: records, by: \.effectiveFrom).map { instant, values in
        let choices = Set(values.map(\.placement))
        return (instant, choices.count == 1 ? choices.first! : BodyPlacement.unknown)
      }.sorted { $0.0 < $1.0 }
    }
    return Set(
      samples.filter { $0.valid && ($0.origin == .measured || $0.origin == .synthetic) }.map {
        sample in
        let timeline = index[sample.deviceID] ?? []
        var lower = 0
        var upper = timeline.count
        while lower < upper {
          let middle = (lower + upper) / 2
          if timeline[middle].0 <= sample.timestamp { lower = middle + 1 } else { upper = middle }
        }
        return lower == 0 ? .unknown : timeline[lower - 1].1
      })
  }
  public static func description(samples: [Measurement], records: [PlacementRecord]) -> String {
    let values = locations(samples: samples, records: records)
    guard !values.isEmpty else { return "No band measurements to associate" }
    return values.map(\.title).sorted().joined(separator: " · ")
  }
}
