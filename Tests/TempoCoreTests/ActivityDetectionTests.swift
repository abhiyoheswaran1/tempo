import XCTest

@testable import TempoCore

final class ActivityDetectionTests: XCTestCase, @unchecked Sendable {
  let t = Date(timeIntervalSince1970: 1_700_000_040)
  func samples(highSeconds: Int = 900, lowSeconds: Int = 240, device: UUID = UUID()) -> [TempoCore
    .Measurement]
  {
    (0..<(highSeconds + lowSeconds)).map {
      TempoCore.Measurement(
        deviceID: device, kind: .heartRate, timestamp: t.addingTimeInterval(Double($0)),
        value: $0 < highSeconds ? 140 : 70, origin: .measured, transport: "test")
    }
  }
  func testSustainedActivityProposesUntypedWorkoutAfterRecovery() {
    let result = AutomaticActivityDetector.detect(
      samples(), maxHeartRate: 190, now: t.addingTimeInterval(1200))
    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result[0].start, t)
    XCTAssertEqual(result[0].end, t.addingTimeInterval(900))
    XCTAssertGreaterThan(result[0].coverage, 0.95)
  }
  func testShortElevationsAndOngoingSessionDoNotEmit() {
    XCTAssertTrue(
      AutomaticActivityDetector.detect(
        samples(highSeconds: 300), maxHeartRate: 190, now: t.addingTimeInterval(600)
      ).isEmpty)
    XCTAssertTrue(
      AutomaticActivityDetector.detect(
        samples(highSeconds: 900, lowSeconds: 0), maxHeartRate: 190, now: t.addingTimeInterval(901)
      ).isEmpty)
  }
  func testGapSplitsInsteadOfFabricatingCoverage() {
    let data = samples(highSeconds: 1200).filter {
      let d = $0.timestamp.timeIntervalSince(t)
      return d < 300 || d >= 900
    }
    XCTAssertTrue(
      AutomaticActivityDetector.detect(data, maxHeartRate: 190, now: t.addingTimeInterval(1500))
        .isEmpty)
  }
  func testImportedOffBodyAndSyntheticDoNotTrigger() {
    for origin in [Origin.imported, .synthetic] {
      var data = samples()
      for i in data.indices { data[i].origin = origin }
      XCTAssertTrue(
        AutomaticActivityDetector.detect(data, maxHeartRate: 190, now: t.addingTimeInterval(1200))
          .isEmpty)
    }
    var data = samples()
    for i in data.indices { data[i].wear = .offBody }
    XCTAssertTrue(
      AutomaticActivityDetector.detect(data, maxHeartRate: 190, now: t.addingTimeInterval(1200))
        .isEmpty)
  }
  func testDuplicateDevicesAndSourceSwitchProduceOneStableCandidate() {
    let a = UUID()
    let b = UUID()
    let first = samples(device: a)
    let other = samples(device: b)
    let segments = [
      SourceSegment(deviceID: a, start: t, end: nil, reason: "initial"),
      SourceSegment(deviceID: b, start: t.addingTimeInterval(450), end: nil, reason: "switch"),
    ]
    let result = AutomaticActivityDetector.detect(
      first + other + first, maxHeartRate: 190, now: t.addingTimeInterval(1200),
      sourceSegments: segments)
    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(Set(result[0].sourceIDs), [a, b])
    XCTAssertEqual(
      result[0].id,
      AutomaticActivityDetector.detect(
        (first + other).reversed(), maxHeartRate: 190, now: t.addingTimeInterval(1200),
        sourceSegments: segments
      ).first?.id)
  }
  func testExistingWorkoutSuppressesProposal() {
    var workout = Workout(activity: .padel, start: t)
    workout.end = t.addingTimeInterval(900)
    XCTAssertTrue(
      AutomaticActivityDetector.detect(
        samples(), maxHeartRate: 190, now: t.addingTimeInterval(1200), existingWorkouts: [workout]
      ).isEmpty)
  }
  func testProposalDecisionAndProvenanceSurviveRestore() async throws {
    let candidate = AutomaticActivityDetector.detect(
      samples(), maxHeartRate: 190, now: t.addingTimeInterval(1200))[0]
    let store = try TempoStore(path: ":memory:")
    let decision = DetectedActivityDecision(candidate: candidate, status: .dismissed)
    try await store.saveRevision(
      Revision(
        entityID: decision.id, kind: "detectedActivity", parentIDs: [],
        payload: JSONEncoder().encode(decision)))
    let copy = try TempoStore(path: ":memory:")
    try await copy.importArchive(store.exportArchive())
    let revisions = try await copy.revisions(kind: "detectedActivity")
    let restored = try JSONDecoder().decode(
      DetectedActivityDecision.self, from: revisions[0].payload)
    XCTAssertEqual(restored.status, .dismissed)
    XCTAssertEqual(restored.candidate.inputDigest, candidate.inputDigest)
  }
}

extension ActivityDetectionTests {
  func testSyntheticDetectionRequiresAnExplicitDemoStoreAndFlag() async throws {
    let demo = try TempoStore(path: ":memory:", allowSynthetic: true)
    var data = samples()
    for i in data.indices {
      data[i].origin = .synthetic
      data[i].transport = "demo"
    }
    try await demo.insert(data)
    let excluded = try await demo.detectedActivities(
      from: t, to: t.addingTimeInterval(1200), maxHeartRate: 190, sourceSegments: [],
      existingWorkouts: [])
    XCTAssertTrue(excluded.isEmpty)
    let candidates = try await demo.detectedActivities(
      from: t, to: t.addingTimeInterval(1200), maxHeartRate: 190, sourceSegments: [],
      existingWorkouts: [], allowSynthetic: true)
    XCTAssertEqual(candidates.first?.origin, .synthetic)
    let normal = try TempoStore(path: ":memory:")
    do {
      try await normal.saveRevision(
        Revision(
          entityID: candidates[0].id, kind: "detectedActivity", parentIDs: [],
          payload: JSONEncoder().encode(DetectedActivityDecision(candidate: candidates[0]))))
      XCTFail("Synthetic candidate must not enter real history")
    } catch {}
  }
  func testConfirmedEstimateWinsOverOverlappingImportedWorkout() {
    var confirmed = Workout(activity: .other, start: t)
    confirmed.end = t.addingTimeInterval(900)
    confirmed.origin = .derived
    confirmed.detectionID = UUID()
    var imported = Workout(activity: .running, start: t)
    imported.end = confirmed.end
    imported.origin = .imported
    XCTAssertEqual(SessionReconciliation.workouts([imported, confirmed]).map(\.id), [confirmed.id])
  }
}

extension ActivityDetectionTests {
  func testSyntheticWorkoutAndCandidateArchivesCannotEnterRealHistory() async throws {
    var workout = Workout(activity: .other, start: t)
    workout.end = t.addingTimeInterval(900)
    workout.origin = .synthetic
    var candidate = AutomaticActivityDetector.detect(
      samples(), maxHeartRate: 190, now: t.addingTimeInterval(1200))[0]
    candidate.origin = .synthetic
    let payloads = [
      ("workout", try JSONEncoder().encode(workout)),
      (
        "detectedActivity", try JSONEncoder().encode(DetectedActivityDecision(candidate: candidate))
      ),
    ]
    for (kind, payload) in payloads {
      let revision = Revision(entityID: UUID(), kind: kind, parentIDs: [], payload: payload)
      let normal = try TempoStore(path: ":memory:")
      do {
        try await normal.saveRevision(revision)
        XCTFail("Synthetic revision accepted")
      } catch {}
      let demo = try TempoStore(path: ":memory:", allowSynthetic: true)
      try await demo.saveRevision(revision)
      let archive = try await demo.exportArchive()
      do {
        try await normal.importArchive(archive)
        XCTFail("Synthetic archive accepted")
      } catch {}
      let remaining = try await normal.revisions(kind: kind)
      XCTAssertTrue(remaining.isEmpty)
    }
  }
}
