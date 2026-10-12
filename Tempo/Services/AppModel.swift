import Foundation
import Observation
import SwiftUI
import TempoCore
import WidgetKit

@MainActor @Observable final class AppModel {
  var store: TempoStore?
  var bluetooth = BluetoothService()
  var cloud: CloudSyncService?
  var health: HealthService?
  var devices: [RegisteredDevice] = []
  var archivedDevices: [RegisteredDevice] = []
  var lastCloudSync: Date?
  var pendingCloudChanges = 0
  var measurements: [TempoCore.Measurement] = []
  private var latestReadings = LatestBandReadings()
  private var displayedReadiness: ReadinessResult?
  private var displayedLoad: LoadResult?
  private var displayedStore: ObjectIdentifier?
  private var displayedDate: Date?
  private var displayedSleepID: UUID?
  var nightMetrics: [UUID: [String: Double]] = [:]
  var workouts: [Workout] = []
  var detectedActivities: [DetectedActivityDecision] = []
  var automaticDetectionEnabled = false
  var activityScanning = false
  var activityLastScan: Date?
  private var lastActivityScanRequest: Date?
  var sleeps: [SleepSession] = []
  var journals: [JournalEntry] = []
  var sourceSegments: [SourceSegment] = []
  var conflictEntities: [UUID] = []
  var activeWorkout: Workout?
  var errorMessage: String?
  var transitioningDataset = false
  private var loadGeneration = 0
  var historyGeneration = 0
  var demo = false
  var syncEnabled = false
  var maxHeartRate: Double = 190
  var hideWidgetDetails = true
  var selector = SourceSelector()
  private var live = LiveActivityService()
  private var refreshTask: Task<Void, Never>?
  private var fallbackTask: Task<Void, Never>?
  private var lastProbe: Date?
  private var collectionTask: Task<Void, Never>?
  private var mutationTail: Task<Void, Never>?
  var placements: [PlacementRecord] = []
  var activeDevice: RegisteredDevice? { devices.first { $0.id == selector.activeID } }
  var canonical: [TempoCore.Measurement] {
    CanonicalTimeline.select(measurements, sourceSegments: sourceSegments)
  }
  var lastSample: TempoCore.Measurement? {
    guard !transitioningDataset else { return nil }
    return LiveSampleSelection.latest(
      Array(bluetooth.lastSamples.values)
        + (latestReadings.latest(
          selectedDeviceID: selector.activeID, now: Date(), allowSynthetic: demo
        ).map { [$0] } ?? []),
      selectedDeviceID: selector.activeID, now: Date(), allowSynthetic: demo)
  }
  var todayReadiness: ReadinessResult {
    if displayedStore == store.map(ObjectIdentifier.init), let displayedDate,
      Calendar.current.isDateInToday(displayedDate), displayedSleepID == readinessSleep?.id,
      let displayedReadiness
    {
      return displayedReadiness
    }
    return readiness
  }
  var todayLoad: LoadResult? {
    guard displayedStore == store.map(ObjectIdentifier.init), let displayedDate,
      Calendar.current.isDateInToday(displayedDate)
    else { return nil }
    return displayedLoad
  }
  private func refreshPresentedSummary() {
    guard let store else { return }
    displayedReadiness = readiness
    displayedSleepID = readinessSleep?.id
    displayedLoad = CardiovascularLoad.calculate(
      canonical.filter { Calendar.current.isDateInToday($0.timestamp) }, maxHeartRate: maxHeartRate)
    displayedStore = ObjectIdentifier(store)
    displayedDate = Date()
  }
  var finishedWorkout: Workout?
  var readinessSleep: SleepSession? {
    SleepPresentation(sessions: sleeps, now: Date()).readinessSession
  }
  var readiness: ReadinessResult {
    let selectedMeasurements = canonical
    let nights = sleeps.filter { !$0.isNap && $0.duration >= 4 * 3600 && $0.end <= Date() }.sorted {
      $0.end < $1.end
    }
    let baseline = nights.suffix(29).map { night in
      PersonalBaseline(
        date: night.end, values: nightInputs(night),
        sourceIDs: Array(
          Set(
            selectedMeasurements.filter { $0.timestamp >= night.start && $0.timestamp < night.end }
              .map(
                \.deviceID))))
    }
    let overnightSamples = selectedMeasurements.filter { sample in
      nights.suffix(29).contains { sample.timestamp >= $0.start && sample.timestamp < $0.end }
    }
    let locations = PlacementTimeline.locations(samples: overnightSamples, records: placements)
      .subtracting([.unknown])
    let currentSleep = readinessSleep
    let current = currentSleep.map { nightInputs($0) } ?? [:]
    return Readiness.calculate(
      current: current, baseline: currentSleep == nil ? baseline : Array(baseline.dropLast()),
      deviceChange: Set(
        sourceSegments.filter { $0.start > Date().addingTimeInterval(-28 * 86400) }.map(\.deviceID)
      ).count > 1, placementChange: locations.count > 1)
  }
  func nightInputs(_ sleep: SleepSession) -> [String: Double] {
    nightMetrics[sleep.id] ?? ["sleepHours": sleep.duration / 3600]
  }
  func start() async {
    guard store == nil else { return }
    do {
      let root = try FileManager.default.url(
        for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
      ).appendingPathComponent("Tempo", isDirectory: true)
      try FileManager.default.createDirectory(
        at: root, withIntermediateDirectories: true,
        attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
      store = try TempoStore(
        path: ProcessInfo.processInfo.arguments.contains("--ui-testing")
          ? ":memory:" : root.appendingPathComponent("history.sqlite").path)
      if let store { health = HealthService(store: store) }
      try await load()
      bluetooth.onConnectionChange = { [weak self] in self?.scheduleFallback() }
      bluetooth.onSample = { [weak self] m in self?.enqueueSample(m) }
      bluetooth.onGeneration = { [weak self] id, generation in
        self?.mutate { [weak self] in
          guard let self, let device = self.devices.first(where: { $0.id == id }),
            device.generation != generation
          else { return }
          try await self.save(
            BandGenerationEvidence.correct(device, to: generation), kind: "device")
        }
      }
      bluetooth.onMetadata = { [weak self] id, firmware, identity in
        self?.mutate { [weak self] in
          guard let self, let index = self.devices.firstIndex(where: { $0.id == id }) else {
            return
          }
          var d = self.devices[index]
          if let firmware {
            d.firmware = firmware
            d.capabilities = .make(generation: d.generation, firmware: firmware)
          }
          if let identity { d.hardwareIdentityHash = identity }
          try await self.save(d, kind: "device")
        }
      }
      bluetooth.configure(devices)
      if let id = devices.first(where: { !bluetooth.isPaused($0.id) })?.id {
        bluetooth.connect(deviceID: id)
      }
      if syncEnabled { await syncIfNeeded() }
      scheduleAutomaticScan(force: true)
    } catch {
      errorMessage =
        "Local storage could not open. Collection is paused: \(error.localizedDescription)"
    }
  }
  private func enqueueSample(_ m: TempoCore.Measurement) {
    guard !demo, !transitioningDataset, devices.contains(where: { $0.id == m.deviceID }) else {
      return
    }
    let preceding = collectionTask
    collectionTask = Task { [weak self] in
      await preceding?.value
      guard let self, let store = self.store else { return }
      do {
        try await store.insert([m])
        self.measurements.append(m)
        self.latestReadings.ingest([m], now: Date(), allowSynthetic: self.demo)
        // Keep only the visible recent window in memory. Older history remains in SQLite.
        let cutoff = Date().addingTimeInterval(-2 * 86400)
        self.measurements.removeAll { $0.timestamp < cutoff }
        let evidence = self.devices.map { d in
          let sample = self.bluetooth.lastSamples[d.id]
          return DeviceEvidence(
            deviceID: d.id, generation: d.generation,
            connected: self.bluetooth.connected.contains(d.id),
            lastValidSample: sample?.valid == true ? sample?.timestamp : nil,
            wear: sample?.wear ?? .unknown)
        }
        if let segment = self.selector.update(evidence, now: Date()) {
          if !self.sourceSegments.isEmpty, self.sourceSegments.last?.end == nil {
            self.sourceSegments[self.sourceSegments.count - 1].end = segment.start
          }
          self.sourceSegments.append(segment)
          try await self.save(segment, kind: "source")
          self.mutate { [weak self] in
            guard let self, var w = self.activeWorkout, w.end == nil else { return }
            w.switchSource(to: segment.deviceID, at: segment.start)
            try await self.save(w, kind: "workout")
          }
        }
        if let w = self.activeWorkout { await self.updateLive(w) }
        self.scheduleSnapshot()
        self.scheduleAutomaticScan()
        if m.wear == .offBody { self.scheduleFallback(immediate: true) }
      } catch {
        self.errorMessage =
          "A measurement could not be persisted. Collection status is not a guarantee of stored coverage."
      }
    }
  }
  private func scheduleFallback(immediate: Bool = false) {
    guard !demo, selector.preference == .automatic, selector.overrideID == nil, devices.count > 1
    else { return }
    fallbackTask?.cancel()
    fallbackTask = Task { [weak self] in
      if !immediate { try? await Task.sleep(for: .seconds(60)) }
      guard !Task.isCancelled, let self, !self.demo, self.selector.preference == .automatic,
        self.selector.overrideID == nil
      else { return }
      let active = self.selector.activeID ?? self.devices.first?.id
      if let active, let sample = self.bluetooth.lastSamples[active], sample.valid,
        sample.wear != .offBody,
        self.bluetooth.connected.contains(active), Date().timeIntervalSince(sample.timestamp) < 90
      {
        return
      }
      if let last = self.lastProbe, Date().timeIntervalSince(last) < 180 { return }
      guard
        let other = self.devices.first(where: { $0.id != active && !self.bluetooth.isPaused($0.id) }
        )
      else { return }
      self.lastProbe = Date()
      self.bluetooth.connect(deviceID: other.id)
    }
  }
  private func scheduleSnapshot() {
    guard refreshTask == nil else { return }
    refreshTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(15))
      guard let self else { return }
      await self.refreshSyncSummary()
      await self.syncIfNeeded()
      self.refreshPresentedSummary()
      self.bluetooth.refreshBatteryIfNeeded()
      self.writeWidget()
      self.refreshTask = nil
    }
  }
  func mutate(_ action: @escaping @MainActor () async throws -> Void) {
    guard !transitioningDataset else { return }
    let previous = mutationTail
    mutationTail = Task { [weak self] in
      await previous?.value
      do { try await action() } catch { self?.errorMessage = error.localizedDescription }
    }
  }
  func load() async throws {
    guard let store else { return }
    loadGeneration += 1
    let generation = loadGeneration
    let loadedMeasurements = try await store.measurements(
      from: Date().addingTimeInterval(-2 * 86400), to: Date().addingTimeInterval(300))
    let revisions = try await store.revisions()
    guard generation == loadGeneration, self.store === store else { return }
    measurements = loadedMeasurements
    let parents = Set(revisions.flatMap(\.parentIDs))
    let heads = revisions.filter { !parents.contains($0.id) }
    let groups = Dictionary(grouping: heads, by: \.entityID)
    conflictEntities = groups.filter { $0.value.count > 1 }.map(\.key)
    let unique = heads.filter { groups[$0.entityID]?.count == 1 && !$0.deleted }
    let decoder = JSONDecoder()
    devices = unique.filter { $0.kind == "device" }.compactMap {
      try? decoder.decode(RegisteredDevice.self, from: $0.payload)
    }
    archivedDevices = groups.filter {
      $0.value.count == 1 && $0.value[0].kind == "device" && $0.value[0].deleted
    }.keys.compactMap { BandGenerationEvidence.archivedDevice(id: $0, revisions: revisions) }
    if !demo { bluetooth.configure(devices) }
    placements = PlacementTimeline.project(revisions)
    workouts = SessionReconciliation.workouts(
      unique.filter { $0.kind == "workout" }.compactMap {
        try? decoder.decode(Workout.self, from: $0.payload)
      }
    ).sorted { $0.start > $1.start }
    activeWorkout = workouts.first { $0.end == nil }
    detectedActivities = unique.filter { $0.kind == "detectedActivity" }.compactMap {
      try? decoder.decode(DetectedActivityDecision.self, from: $0.payload)
    }.sorted { $0.candidate.start > $1.candidate.start }
    sleeps = SessionReconciliation.sleep(
      unique.filter { $0.kind == "sleep" }.compactMap {
        try? decoder.decode(SleepSession.self, from: $0.payload)
      }
    ).sorted { $0.end > $1.end }
    journals = unique.filter { $0.kind == "journal" }.compactMap {
      try? decoder.decode(JournalEntry.self, from: $0.payload)
    }.sorted { $0.date > $1.date }
    sourceSegments = SourceTimeline.normalized(
      unique.filter { $0.kind == "source" }.compactMap {
        try? decoder.decode(SourceSegment.self, from: $0.payload)
      }
    ).sorted { $0.start < $1.start }
    for night in sleeps.prefix(29) {
      let values = try await store.nightInputs(night, sourceSegments: sourceSegments)
      guard generation == loadGeneration, self.store === store else { return }
      nightMetrics[night.id] = values
    }
    if let data = try await store.metadata("preferences.local"),
      let p = try? decoder.decode(Preferences.self, from: data)
    {
      guard generation == loadGeneration, self.store === store else { return }
      selector.preference = p.preference
      maxHeartRate = p.maxHeartRate
      hideWidgetDetails = p.hideWidgetDetails
      automaticDetectionEnabled = p.automaticDetectionEnabled ?? false
      syncEnabled = p.syncEnabled
    }
    if let revision = unique.first(where: { $0.kind == "preferences" }),
      let p = try? decoder.decode(PortablePreferences.self, from: revision.payload)
    {
      guard generation == loadGeneration, self.store === store else { return }
      selector.preference = p.preference
      maxHeartRate = p.maxHeartRate
      hideWidgetDetails = p.hideWidgetDetails
      automaticDetectionEnabled = p.automaticDetectionEnabled ?? false
    }
    await refreshSyncSummary()
    guard generation == loadGeneration, self.store === store else { return }
    historyGeneration &+= 1
    latestReadings = LatestBandReadings()
    latestReadings.ingest(measurements, now: Date(), allowSynthetic: demo)
    refreshPresentedSummary()
    writeWidget()
  }
  func save<T: Codable & Identifiable>(_ value: T, kind: String) async throws where T.ID == UUID {
    guard let store else { return }
    let heads = try await store.revisionHeads(entityID: value.id)
    guard heads.count <= 1 else { throw ModelError.unresolvedConflict }
    try await store.saveRevision(
      Revision(
        entityID: value.id, kind: kind, parentIDs: heads.map(\.id),
        payload: JSONEncoder().encode(value)), enqueue: !demo, expectedParentIDs: heads.map(\.id))
    try await load()
  }
  func delete(id: UUID, kind: String) async throws {
    guard let store else { return }
    let heads = try await store.revisionHeads(entityID: id)
    try await store.saveRevision(
      Revision(
        entityID: id, kind: kind, parentIDs: heads.map(\.id), payload: Data(), deleted: true),
      enqueue: !demo, expectedParentIDs: heads.map(\.id))
    try await load()
  }
  func resolve(entityID: UUID, chosen: Revision) async throws {
    guard let store else { return }
    let heads = try await store.revisionHeads(entityID: entityID)
    try await store.saveRevision(
      Revision(
        entityID: entityID, kind: chosen.kind, parentIDs: heads.map(\.id), payload: chosen.payload,
        deleted: chosen.deleted), enqueue: !demo)
    try await load()
  }
  func register(
    _ discovery: BluetoothService.Discovery, generation: DeviceGeneration, existing: UUID? = nil
  ) async throws {
    guard !demo else { return }
    if let existing, !demo, bluetooth.state(existing) != .disconnected,
      bluetooth.deviceID(for: discovery.id) != existing
    {
      throw ModelError.identityMismatch
    }
    let mappedID = bluetooth.deviceID(for: discovery.id)
    if let mappedID, let existing, mappedID != existing { throw ModelError.identityMismatch }
    let id = mappedID ?? existing
    let known = id.flatMap { candidate in (devices + archivedDevices).first { $0.id == candidate } }
    let d =
      known.map { BandGenerationEvidence.correct($0, to: discovery.generation ?? generation) }
      ?? RegisteredDevice(
        generation: discovery.generation ?? generation,
        name: (discovery.generation ?? generation) == .whoop4 ? "Whoop 4" : "Whoop 5")
    if !devices.contains(where: { $0.id == d.id }) || devices.first(where: { $0.id == d.id }) != d {
      try await save(d, kind: "device")
    }
    bluetooth.configure(devices)
    bluetooth.register(peripheralID: discovery.id, deviceID: d.id, generation: d.generation)
  }
  func disconnectBand(_ id: UUID) async throws {
    if !demo { bluetooth.disconnect(deviceID: id) }
    fallbackTask?.cancel()
    await collectionTask?.value
    selector.release(id)
    let now = Date()
    if let segment = sourceSegments.last(where: { $0.deviceID == id && $0.end == nil }) {
      var closed = segment
      closed.end = max(now, segment.start)
      try await save(closed, kind: "source")
    }
    if var workout = activeWorkout {
      workout.closeSource(id, at: now)
      try await save(workout, kind: "workout")
    }
  }
  func removeBand(_ id: UUID) async throws {
    try await disconnectBand(id)
    try await delete(id: id, kind: "device")
  }
  func correctGeneration(_ id: UUID, to generation: DeviceGeneration) async throws {
    guard let device = devices.first(where: { $0.id == id }) else { return }
    try await save(BandGenerationEvidence.correct(device, to: generation), kind: "device")
    bluetooth.configure(devices)
  }
  func startWorkout(_ activity: TempoCore.Activity) async throws {
    guard activeWorkout == nil else { return }
    var w = Workout(activity: activity, start: Date())
    if let id = selector.activeID { w.switchSource(to: id, at: w.start) }
    try await save(w, kind: "workout")
    if !demo { await updateLive(w) }
  }
  func pauseResume() async throws {
    guard var w = activeWorkout else { return }
    if w.pausedAt == nil { w.pause(at: Date()) } else { w.resume(at: Date()) }
    try await save(w, kind: "workout")
    if !demo { await updateLive(w) }
  }
  func finishWorkout() async throws {
    guard var w = activeWorkout else { return }
    w.finish(at: Date())
    try await save(w, kind: "workout")
    finishedWorkout = w
    if !demo { await live.end() }
  }
  private func updateLive(_ w: Workout) async {
    await live.update(
      workoutID: w.id.uuidString, name: w.activity.rawValue.capitalized,
      state: .init(
        startedAt: w.start, elapsed: w.activeDuration(at: Date()),
        heartRate: lastSample.flatMap {
          Date().timeIntervalSince($0.timestamp) < 90 ? Int($0.value) : nil
        }, paused: w.pausedAt != nil, updatedAt: Date(), source: activeDevice?.name ?? "No source"))
  }
  var pendingDetectedActivities: [DetectedActivityDecision] {
    detectedActivities.filter { decision in
      decision.status == .pending
        && !workouts.contains(where: { workout in
          workout.detectionID == decision.id
            || (workout.start < decision.candidate.end
              && (workout.end ?? .distantFuture) > decision.candidate.start)
        })
    }
  }
  private func scheduleAutomaticScan(force: Bool = false) {
    guard automaticDetectionEnabled, !transitioningDataset else { return }
    let now = Date()
    if !force, let previous = lastActivityScanRequest, now.timeIntervalSince(previous) < 60 {
      return
    }
    lastActivityScanRequest = now
    mutate { [weak self] in try await self?.scanAutomaticActivities() }
  }
  var refreshingToday = false
  var refreshOutcome: ManualRefreshOutcome?
  func refreshToday() async {
    guard !refreshingToday, !transitioningDataset, let refreshStore = store else { return }
    refreshingToday = true
    refreshOutcome = nil
    defer { refreshingToday = false }
    let startedAt = Date()
    await collectionTask?.value
    await mutationTail?.value
    guard !transitioningDataset, self.store === refreshStore else { return }
    if !demo {
      bluetooth.resumeCollection(
        preferred: selector.activeID ?? devices.first(where: { !bluetooth.isPaused($0.id) })?.id)
      bluetooth.refreshBatteryIfNeeded()
      scheduleFallback(immediate: true)
      if syncEnabled { await sync() }
    }
    guard !transitioningDataset, self.store === refreshStore else { return }
    do { try await load() } catch {
      errorMessage = "Local history could not refresh"
      return
    }
    guard !transitioningDataset, self.store === refreshStore else { return }
    refreshOutcome = ManualRefreshOutcome.resolve(
      demo: demo, cloudEnabled: syncEnabled,
      cloudBusy: cloud?.busy ?? false, cloudError: cloud?.errorMessage,
      pending: pendingCloudChanges, lastSuccess: lastCloudSync, startedAt: startedAt)
  }
  private var lastAutomaticSyncAttempt: Date?
  private func syncIfNeeded() async {
    guard !demo, syncEnabled,
      SyncFreshness.shouldSync(
        lastSuccess: lastCloudSync, pending: pendingCloudChanges, now: Date()),
      lastAutomaticSyncAttempt.map({ Date().timeIntervalSince($0) >= 60 }) ?? true
    else { return }
    lastAutomaticSyncAttempt = Date()
    await sync()
  }
  func onForegroundActive() async {
    guard !demo else { return }
    bluetooth.resumeCollection(
      preferred: selector.activeID ?? devices.first(where: { !bluetooth.isPaused($0.id) })?.id)
    bluetooth.refreshBatteryIfNeeded()
    refreshPresentedSummary()
    scheduleFallback(immediate: true)
    await refreshSyncSummary()
    await syncIfNeeded()
    scheduleAutomaticScan(force: true)
  }
  func setAutomaticDetectionEnabled(_ enabled: Bool) async throws {
    automaticDetectionEnabled = enabled
    try await persistPreferences()
    if enabled { try await scanAutomaticActivities() }
  }
  func scanAutomaticActivities() async throws {
    guard automaticDetectionEnabled, !transitioningDataset, let store else { return }
    guard !activityScanning else { return }
    activityScanning = true
    defer { activityScanning = false }
    for decision in detectedActivities
    where decision.status == .pending
      && workouts.contains(where: { $0.id == decision.candidate.workoutID })
    {
      var recovered = decision
      recovered.status = .confirmed
      try await save(recovered, kind: "detectedActivity")
    }
    let now = Date()
    let candidates = try await store.detectedActivities(
      from: now.addingTimeInterval(-12 * 3600), to: now, maxHeartRate: maxHeartRate,
      sourceSegments: sourceSegments, existingWorkouts: workouts, allowSynthetic: demo)
    for candidate in candidates {
      // Suppress earlier decisions by interval too, so threshold/algorithm changes do not resurrect dismissals.
      guard
        !detectedActivities.contains(where: {
          $0.candidate.start < candidate.end && $0.candidate.end > candidate.start
        }),
        !workouts.contains(where: {
          $0.start < candidate.end && ($0.end ?? .distantFuture) > candidate.start
        })
      else { continue }
      try await save(DetectedActivityDecision(candidate: candidate), kind: "detectedActivity")
    }
    activityLastScan = now
    try await store.setMetadata("activity.lastScan", value: JSONEncoder().encode(now))
  }
  func dismissDetectedActivity(_ decision: DetectedActivityDecision) async throws {
    guard let latest = detectedActivities.first(where: { $0.id == decision.id }),
      latest.status == .pending
    else { return }
    var updated = latest
    updated.status = .dismissed
    try await save(updated, kind: "detectedActivity")
  }
  func confirmDetectedActivity(
    _ decision: DetectedActivityDecision, activity: TempoCore.Activity, start: Date, end: Date
  ) async throws {
    guard start < end, end.timeIntervalSince(start) <= 24 * 3600, end <= Date(),
      let latest = detectedActivities.first(where: { $0.id == decision.id }),
      latest.status == .pending
    else { throw ModelError.invalidDetectedTiming }
    if !workouts.contains(where: { $0.id == latest.candidate.workoutID }) {
      guard !workouts.contains(where: { $0.start < end && ($0.end ?? .distantFuture) > start })
      else { throw ModelError.overlappingWorkout }
      var w = Workout(activity: activity, start: start)
      w.id = latest.candidate.workoutID
      w.end = end
      w.origin = latest.candidate.origin
      w.detectionID = latest.id
      w.algorithmVersion = latest.candidate.algorithmVersion
      w.note = "Confirmed heart-rate-only activity estimate; timing reviewed by user."
      w.sources = sourceSegments.compactMap { s in
        let from = max(s.start, start)
        let until = min(s.end ?? end, end)
        guard from < until else { return nil }
        return SourceSegment(
          deviceID: s.deviceID, start: from, end: until, reason: "Confirmed detection; \(s.reason)")
      }
      try await save(w, kind: "workout")
    }
    // A crash between these writes cannot duplicate the deterministic workout ID.
    var updated = latest
    updated.status = .confirmed
    try await save(updated, kind: "detectedActivity")
  }
  func recordPlacement(
    deviceID: UUID, placement: BodyPlacement, effectiveFrom: Date, existing: PlacementRecord? = nil
  ) async throws {
    guard devices.contains(where: { $0.id == deviceID }), effectiveFrom <= Date() else {
      throw ModelError.invalidPlacement
    }
    var record =
      existing
      ?? PlacementRecord(deviceID: deviceID, placement: placement, effectiveFrom: effectiveFrom)
    guard record.deviceID == deviceID else { throw ModelError.invalidPlacement }
    record.placement = placement
    record.effectiveFrom = effectiveFrom
    record.timeZoneID = TimeZone.current.identifier
    try await save(record, kind: "placement")
  }
  func setPreference(_ preference: SourcePreference) async throws {
    selector.preference = preference
    selector.overrideID = nil
    try await persistPreferences()
    let desired =
      (preference == .automatic ? activeDevice : nil)
      ?? devices.first {
        preference == .prefer4
          ? $0.generation == .whoop4 : (preference == .prefer5 ? $0.generation == .whoop5 : true)
      }
    if let desired, !demo { bluetooth.connect(deviceID: desired.id) }
  }
  func override(_ id: UUID) {
    selector.overrideID = id
    if !demo { bluetooth.connect(deviceID: id) }
  }
  func persistPreferences() async throws {
    guard let store else { return }
    let p = Preferences(
      preference: selector.preference, maxHeartRate: maxHeartRate,
      hideWidgetDetails: hideWidgetDetails, syncEnabled: syncEnabled,
      automaticDetectionEnabled: automaticDetectionEnabled)
    try await store.setMetadata("preferences.local", value: JSONEncoder().encode(p))
    try await save(
      PortablePreferences(
        preference: selector.preference, maxHeartRate: maxHeartRate,
        hideWidgetDetails: hideWidgetDetails, automaticDetectionEnabled: automaticDetectionEnabled),
      kind: "preferences")
    writeWidget()
  }
  func sync(forceRetry: Bool = false) async {
    guard !demo, !transitioningDataset, syncEnabled, let syncStore = store else { return }
    await collectionTask?.value
    await mutationTail?.value
    guard !demo, !transitioningDataset, syncEnabled, self.store === syncStore else { return }
    if cloud == nil { cloud = CloudSyncService(store: syncStore) }
    guard let service = cloud else { return }
    if forceRetry { try? await syncStore.resetRetrySchedule() }
    guard !demo, !transitioningDataset, self.store === syncStore else { return }
    await service.sync(forceRetry: forceRetry)
    guard !demo, !transitioningDataset, self.store === syncStore else { return }
    do {
      try await load()
      guard !demo, !transitioningDataset, self.store === syncStore else { return }
      bluetooth.configure(devices)
    } catch {
      if !demo, !transitioningDataset, self.store === syncStore {
        errorMessage = "Restored history could not load"
      }
    }
  }
  func refreshSyncSummary() async {
    guard !demo, let store else {
      lastCloudSync = nil
      pendingCloudChanges = 0
      return
    }
    let date = try? await store.metadata("cloud.lastSuccess")
    let pending = (try? await store.pendingCount()) ?? 0
    guard !demo, self.store === store else { return }
    lastCloudSync = date.flatMap { try? JSONDecoder().decode(Date.self, from: $0) }
    pendingCloudChanges = pending
  }
  func setDemo(_ enabled: Bool) async {
    guard !transitioningDataset, enabled != demo else { return }
    finishedWorkout = nil
    refreshOutcome = nil
    transitioningDataset = true
    loadGeneration += 1
    defer { transitioningDataset = false }
    fallbackTask?.cancel()
    bluetooth.suspend()
    await collectionTask?.value
    await mutationTail?.value
    if enabled {
      fallbackTask?.cancel()
      bluetooth.suspend()
      selector = SourceSelector()
      automaticDetectionEnabled = false
      detectedActivities = []
      store = try? TempoStore(path: ":memory:", allowSynthetic: true)
      demo = true
      cloud = nil
      health = nil
      let d = RegisteredDevice(generation: .whoop4, name: "Synthetic band")
      try? await save(d, kind: "device")
      let now = Date()
      var records: [TempoCore.Measurement] = []
      for day in 0..<28 {
        let end = Calendar.current.startOfDay(for: now).addingTimeInterval(
          Double(-day) * 86400 + 7 * 3600)
        let sleep = SleepSession(
          start: end.addingTimeInterval(-7.5 * 3600), end: end,
          timeZoneID: TimeZone.current.identifier, origin: .synthetic)
        if !ProcessInfo.processInfo.arguments.contains("--stale-sleep-demo") || day >= 3 {
          try? await save(sleep, kind: "sleep")
        }
        for i in 0..<300 {
          records.append(
            TempoCore.Measurement(
              deviceID: d.id, kind: .heartRate, timestamp: end.addingTimeInterval(Double(i - 300)),
              value: Double(58 + day % 6) + sin(Double(i) / 20) * 3, origin: .synthetic,
              transport: "demo", rrMilliseconds: [980, 1000, 1020]))
        }
      }
      if ProcessInfo.processInfo.arguments.contains("--live-dashboard-demo") {
        for i in stride(from: 0, to: 14400, by: 5) where !(6600..<7200).contains(i) {
          records.append(
            TempoCore.Measurement(
              deviceID: d.id, kind: .heartRate,
              timestamp: now.addingTimeInterval(Double(i - 14399)),
              value: 78 + sin(Double(i) / 500) * 12 + ((3000..<4500).contains(i) ? 40 : 0),
              origin: .synthetic, transport: "demo", rrMilliseconds: [800, 810], wear: .unknown))
        }
      }
      if ProcessInfo.processInfo.arguments.contains("--activity-detection-demo") {
        let end = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970 / 60) * 60 - 300)
        let start = end.addingTimeInterval(-900)
        for i in 0..<1200 {
          records.append(
            TempoCore.Measurement(
              deviceID: d.id, kind: .heartRate, timestamp: start.addingTimeInterval(Double(i)),
              value: i < 900 ? 140 : 70, origin: .synthetic, transport: "demo"))
        }
      }
      try? await store?.insert(records)
      try? await load()
    } else {
      store = nil
      demo = false
      devices = []
      measurements = []
      latestReadings = LatestBandReadings()
      displayedReadiness = nil
      displayedLoad = nil
      displayedStore = nil
      workouts = []
      sleeps = []
      selector = SourceSelector()
      await start()
    }
  }
  func writeWidget() {
    guard !demo, let group = Bundle.main.object(forInfoDictionaryKey: "TempoAppGroup") as? String,
      let defaults = UserDefaults(suiteName: group)
    else { return }
    defaults.set(Date().timeIntervalSince1970, forKey: "updated")
    defaults.set(hideWidgetDetails, forKey: "private")
    defaults.set(readiness.score ?? -1, forKey: "readiness")
    defaults.set(sleeps.first?.duration ?? -1, forKey: "sleep")
    WidgetCenter.shared.reloadAllTimelines()
  }
  struct PortablePreferences: Codable, Identifiable {
    var id: UUID { UUID(uuidString: "1D989900-6D48-4C5E-9392-D32E90F51BC0")! }
    var preference: SourcePreference
    var maxHeartRate: Double
    var hideWidgetDetails: Bool
    var automaticDetectionEnabled: Bool? = nil
  }
  struct Preferences: Codable {
    var preference: SourcePreference
    var maxHeartRate: Double
    var hideWidgetDetails: Bool
    var syncEnabled: Bool
    var automaticDetectionEnabled: Bool? = nil
  }
  enum ModelError: LocalizedError {
    case unresolvedConflict, invalidDetectedTiming, overlappingWorkout, invalidPlacement,
      identityMismatch
    var errorDescription: String? {
      switch self {
      case .identityMismatch:
        return
          "This phone already maps that band to another registered identity. Choose its existing registry entry."
      case .unresolvedConflict:
        return "This item has concurrent edits. Resolve them in Settings before changing it."
      case .invalidPlacement:
        return "Choose a registered band and a placement change in the past or present."
      case .invalidDetectedTiming:
        return "Review the proposed timing; it must be a completed session shorter than 24 hours."
      case .overlappingWorkout:
        return "This period overlaps a recorded workout. Review the existing workout instead."
      }
    }
  }
}
