import Foundation
import HealthKit
import Observation
import TempoCore

@MainActor @Observable final class HealthService {
  var status = "Apple Health is optional"
  private let health = HKHealthStore()
  private let store: TempoStore
  private let healthDeviceID = UUID(uuidString: "542335C0-894A-4C81-91E6-A25788988888")!
  init(store: TempoStore) { self.store = store }
  struct Options {
    var heartRate = false
    var restingHeartRate = false
    var hrv = false
    var sleep = false
    var workouts = false
    var weight = false
    var exportHeartRate = false
    var exportSleep = false
    var exportWorkouts = false
  }
  func authorize(_ options: Options) async throws {
    guard HKHealthStore.isHealthDataAvailable() else {
      status = "Health data unavailable on this device"
      return
    }
    var read = Set<HKObjectType>()
    var write = Set<HKSampleType>()
    if options.heartRate { read.insert(HKQuantityType(.heartRate)) }
    if options.restingHeartRate { read.insert(HKQuantityType(.restingHeartRate)) }
    if options.hrv { read.insert(HKQuantityType(.heartRateVariabilitySDNN)) }
    if options.weight { read.insert(HKQuantityType(.bodyMass)) }
    if options.sleep { read.insert(HKCategoryType(.sleepAnalysis)) }
    if options.workouts { read.insert(HKObjectType.workoutType()) }
    if options.exportHeartRate { write.insert(HKQuantityType(.heartRate)) }
    if options.exportSleep { write.insert(HKCategoryType(.sleepAnalysis)) }
    if options.exportWorkouts { write.insert(HKObjectType.workoutType()) }
    try await health.requestAuthorization(toShare: write, read: read)
    status = "Permission request completed. Read access is private to Health."
  }
  func importData(_ options: Options) async throws {
    var quantities: [(HKQuantityTypeIdentifier, MetricKind, HKUnit)] = []
    if options.heartRate {
      quantities.append((.heartRate, .heartRate, HKUnit.count().unitDivided(by: .minute())))
    }
    if options.restingHeartRate {
      quantities.append(
        (.restingHeartRate, .restingHeartRate, HKUnit.count().unitDivided(by: .minute())))
    }
    if options.hrv {
      quantities.append((.heartRateVariabilitySDNN, .sdnn, .secondUnit(with: .milli)))
    }
    if options.weight { quantities.append((.bodyMass, .weight, .gramUnit(with: .kilo))) }
    for (type, kind, unit) in quantities {
      let result = try await anchored(HKQuantityType(type))
      var observations: [TempoCore.Measurement] = []
      for sample in result.samples.compactMap({ $0 as? HKQuantitySample })
      where sample.sourceRevision.source.bundleIdentifier != Bundle.main.bundleIdentifier {
        let m = TempoCore.Measurement(
          deviceID: healthDeviceID, kind: kind, timestamp: sample.startDate,
          value: sample.quantity.doubleValue(for: unit), origin: .imported,
          transport: "healthkit:\(sample.sourceRevision.source.bundleIdentifier)",
          recordKey: sample.uuid.uuidString)
        observations.append(m)
        try await store.setMetadata("health.uuid.\(sample.uuid)", value: Data(m.id.utf8))
      }
      try await store.insert(observations)
      for d in result.deleted {
        let portableIDs = try await store.observations(externalID: d.uuid.uuidString).map(\.id)
        let localID = try await store.metadata("health.uuid.\(d.uuid)").flatMap {
          String(data: $0, encoding: .utf8)
        }
        for id in Set(portableIDs + (localID.map { [$0] } ?? [])) {
          try await store.saveRevision(
            Revision(
              entityID: d.uuid, kind: "measurementDeletion", parentIDs: [], payload: Data(id.utf8),
              deleted: true))
        }
      }
      try await saveAnchor(result.anchor, type: HKQuantityType(type))
    }
    if options.sleep {
      let type = HKCategoryType(.sleepAnalysis)
      let result = try await anchored(HKCategoryType(.sleepAnalysis))
      for sample in result.samples.compactMap({ $0 as? HKCategorySample })
      where sample.sourceRevision.source.bundleIdentifier != Bundle.main.bundleIdentifier {
        guard
          [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
          ].contains(sample.value)
        else { continue }
        var sleep = SleepSession(
          start: sample.startDate, end: sample.endDate,
          timeZoneID: sample.metadata?[HKMetadataKeyTimeZone] as? String ?? "UTC", origin: .imported
        )
        sleep.id = sample.uuid
        try await store.saveRevision(
          Revision(
            id: sample.uuid, entityID: sample.uuid, kind: "sleep", parentIDs: [],
            payload: JSONEncoder().encode(sleep), createdAt: sample.endDate))
      }
      for d in result.deleted {
        let heads = try await store.revisionHeads(entityID: d.uuid)
        if !heads.isEmpty {
          try await store.saveRevision(
            Revision(
              entityID: d.uuid, kind: "sleep", parentIDs: heads.map(\.id), payload: Data(),
              deleted: true))
        }
      }
      try await saveAnchor(result.anchor, type: type)
    }
    if options.workouts {
      let result = try await anchored(HKObjectType.workoutType())
      for sample in result.samples.compactMap({ $0 as? HKWorkout })
      where sample.sourceRevision.source.bundleIdentifier != Bundle.main.bundleIdentifier {
        var w = TempoCore.Workout(
          activity: activity(sample.workoutActivityType), start: sample.startDate)
        w.id = sample.uuid
        w.end = sample.endDate
        w.origin = .imported
        try await store.saveRevision(
          Revision(
            id: sample.uuid, entityID: sample.uuid, kind: "workout", parentIDs: [],
            payload: JSONEncoder().encode(w), createdAt: sample.endDate))
      }
      for d in result.deleted {
        let heads = try await store.revisionHeads(entityID: d.uuid)
        if !heads.isEmpty {
          try await store.saveRevision(
            Revision(
              entityID: d.uuid, kind: "workout", parentIDs: heads.map(\.id), payload: Data(),
              deleted: true))
        }
      }
      try await saveAnchor(result.anchor, type: HKObjectType.workoutType())
    }
    status =
      "A bounded page of available Health data imported. Repeat to continue older history; denied types may return no samples."
  }
  private struct AnchorResult {
    var samples: [HKSample]
    var deleted: [HKDeletedObject]
    var anchor: HKQueryAnchor?
  }
  private func anchored(_ type: HKSampleType) async throws -> AnchorResult {
    var anchor: HKQueryAnchor?
    if let data = try await store.metadata("health.anchor.\(type.identifier)") {
      anchor = try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }
    return try await withCheckedThrowingContinuation { continuation in
      let query = HKAnchoredObjectQuery(
        type: type, predicate: nil, anchor: anchor, limit: 1000
      ) { _, samples, deleted, anchor, error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume(
            returning: AnchorResult(samples: samples ?? [], deleted: deleted ?? [], anchor: anchor))
        }
      }
      health.execute(query)
    }
  }
  private func saveAnchor(_ anchor: HKQueryAnchor?, type: HKSampleType) async throws {
    if let anchor {
      try await store.setMetadata(
        "health.anchor.\(type.identifier)",
        value: NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true))
    }
  }
  func exportHeartRate(_ observations: [TempoCore.Measurement]) async throws {
    let type = HKQuantityType(.heartRate)
    let unit = HKUnit.count().unitDivided(by: .minute())
    guard health.authorizationStatus(for: type) == .sharingAuthorized else {
      status = "Heart-rate export permission is not granted"
      return
    }
    var samples: [HKQuantitySample] = []
    var ids: [String] = []
    for m in observations where m.origin == .measured && m.valid && m.kind == .heartRate {
      guard try await store.metadata("health.export.\(m.id)") == nil else { continue }
      samples.append(
        HKQuantitySample(
          type: type, quantity: HKQuantity(unit: unit, doubleValue: m.value), start: m.timestamp,
          end: m.timestamp,
          metadata: [HKMetadataKeySyncIdentifier: "tempo:\(m.id)", HKMetadataKeySyncVersion: 1]))
      ids.append(m.id)
      if samples.count == 500 { break }
    }
    guard !samples.isEmpty else { return }
    try await health.save(samples)
    for id in ids { try await store.setMetadata("health.export.\(id)", value: Data([1])) }
    status = "Measured heart rate exported without importing Tempo's own samples"
  }
  private func activity(_ type: HKWorkoutActivityType) -> TempoCore.Activity {
    switch type {
    case .cycling: return .cycling
    case .running: return .running
    case .walking: return .walking
    case .traditionalStrengthTraining, .functionalStrengthTraining: return .strength
    default: return .other
    }
  }
}

extension HealthService {
  func exportSessions(workouts: [Workout], sleeps: [SleepSession], options: Options) async throws {
    if options.exportSleep {
      let type = HKCategoryType(.sleepAnalysis)
      if health.authorizationStatus(for: type) == .sharingAuthorized {
        for s in sleeps where s.origin == .manual {
          let key = "tempo:sleep:\(s.id.uuidString):\(StableID.hash(try JSONEncoder().encode(s)))"
          guard try await store.metadata("health.export.\(key)") == nil else { continue }
          let heads = try await store.revisionHeads(entityID: s.id)
          let version = Int((heads.map(\.createdAt).max() ?? s.end).timeIntervalSince1970 * 1000)
          let sample = HKCategorySample(
            type: type, value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            start: s.start, end: s.end,
            metadata: [
              HKMetadataKeySyncIdentifier: "tempo:sleep:\(s.id.uuidString)",
              HKMetadataKeySyncVersion: version, HKMetadataKeyWasUserEntered: true,
              HKMetadataKeyTimeZone: s.timeZoneID,
            ])
          try await health.save(sample)
          try await store.setMetadata("health.export.\(key)", value: Data([1]))
        }
      }
    }
    if options.exportWorkouts,
      health.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
    {
      for w in workouts
      where w.end != nil && (w.origin == .manual || (w.origin == .derived && w.detectionID != nil))
      {
        let key = "tempo:workout:\(w.id.uuidString)"
        guard try await store.metadata("health.export.\(key)") == nil else { continue }
        let config = HKWorkoutConfiguration()
        switch w.activity {
        case .cycling: config.activityType = .cycling
        case .running: config.activityType = .running
        case .walking: config.activityType = .walking
        case .strength: config.activityType = .traditionalStrengthTraining
        case .padel: config.activityType = .other
        case .other: config.activityType = .other
        }
        let builder = HKWorkoutBuilder(healthStore: health, configuration: config, device: nil)
        try await builder.beginCollection(at: w.start)
        try await builder.addMetadata([
          HKMetadataKeySyncIdentifier: key, HKMetadataKeySyncVersion: 1,
          HKMetadataKeyWorkoutBrandName: "Tempo", HKMetadataKeyWasUserEntered: true,
          "TempoActivity": w.activity.rawValue,
          "TempoProvenance": w.detectionID == nil ? "manual" : "confirmed-heart-rate-estimate",
          "TempoAlgorithmVersion": w.algorithmVersion ?? "manual",
        ])
        let events = w.pauses.flatMap {
          [
            HKWorkoutEvent(
              type: .pause, dateInterval: DateInterval(start: $0.start, duration: 0), metadata: nil),
            HKWorkoutEvent(
              type: .resume, dateInterval: DateInterval(start: $0.end, duration: 0), metadata: nil),
          ]
        }
        if !events.isEmpty { try await builder.addWorkoutEvents(events) }
        try await builder.endCollection(at: w.end!)
        _ = try await builder.finishWorkout()
        try await store.setMetadata("health.export.\(key)", value: Data([1]))
      }
    }
    status = "Supported sessions exported; Tempo sources are excluded from imports"
  }
}
