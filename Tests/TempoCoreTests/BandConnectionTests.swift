import XCTest

@testable import TempoCore

final class BandConnectionTests: XCTestCase {
  func testConnectIsIdempotentAndDiscoveryNotActionableWhileConnected() {
    let id = UUID()
    var ledger = BandConnectionLedger()
    XCTAssertTrue(ledger.requestConnect(id))
    XCTAssertFalse(ledger.requestConnect(id))
    XCTAssertFalse(ledger.canOfferConnection(id))
    XCTAssertTrue(ledger.didConnect(id))
    XCTAssertEqual(ledger.state(id), .connected)
    XCTAssertFalse(ledger.requestConnect(id))
    XCTAssertFalse(ledger.canOfferConnection(id))
  }
  func testExplicitDisconnectPersistsIntentAndBlocksReconnectAndLateConnect() {
    let id = UUID()
    var ledger = BandConnectionLedger()
    _ = ledger.requestConnect(id)
    _ = ledger.didConnect(id)
    ledger.disconnect(id)
    XCTAssertFalse(ledger.shouldReconnect(id))
    XCTAssertFalse(ledger.didConnect(id))
    var restored = BandConnectionLedger(pausedIDs: ledger.pausedIDs)
    XCTAssertFalse(restored.shouldReconnect(id))
    XCTAssertTrue(restored.requestConnect(id))
    XCTAssertTrue(restored.didConnect(id))
  }
  func testLinkLossCanReconnectButSuspendedOtherSourceCannot() {
    let a = UUID()
    let b = UUID()
    var ledger = BandConnectionLedger()
    _ = ledger.requestConnect(a)
    _ = ledger.didConnect(a)
    ledger.lostConnection(a)
    XCTAssertTrue(ledger.shouldReconnect(a))
    _ = ledger.requestConnect(b)
    XCTAssertFalse(ledger.shouldReconnect(a))
    XCTAssertFalse(ledger.didConnect(a))
    XCTAssertTrue(ledger.didConnect(b))
  }
  func testGenerationRequiresExclusiveKnownServiceAndCorrectsDefaultNameOnly() {
    XCTAssertNil(BandGenerationEvidence.resolve(hasWhoop4Service: false, hasWhoop5Service: false))
    XCTAssertNil(BandGenerationEvidence.resolve(hasWhoop4Service: true, hasWhoop5Service: true))
    XCTAssertEqual(
      BandGenerationEvidence.resolve(hasWhoop4Service: false, hasWhoop5Service: true), .whoop5)
    let original = RegisteredDevice(generation: .whoop4, name: "Whoop 4")
    let corrected = BandGenerationEvidence.correct(original, to: .whoop5)
    XCTAssertEqual(corrected.id, original.id)
    XCTAssertEqual(corrected.name, "Whoop 5")
    var custom = original
    custom.name = "My training band"
    XCTAssertEqual(BandGenerationEvidence.correct(custom, to: .whoop5).name, custom.name)
  }
  func testRemovingDeviceRevisionPreservesMeasurementsAndCanRestoreSameIdentity() async throws {
    let store = try TempoStore(path: ":memory:")
    let band = RegisteredDevice(generation: .whoop5, name: "Whoop 5")
    let first = Revision(
      entityID: band.id, kind: "device", parentIDs: [], payload: try JSONEncoder().encode(band))
    try await store.saveRevision(first)
    let measurement = Measurement(
      deviceID: band.id, kind: .heartRate, timestamp: Date(), value: 75, origin: .measured,
      transport: "fixture")
    try await store.insert([measurement])
    try await store.saveRevision(
      Revision(
        entityID: band.id, kind: "device", parentIDs: [first.id], payload: Data(), deleted: true))
    let readings = try await store.measurements(from: .distantPast, to: .distantFuture)
    XCTAssertEqual(readings, [measurement])
    let archived = try await store.revisions(kind: "device")
    XCTAssertEqual(
      BandGenerationEvidence.archivedDevice(id: band.id, revisions: archived)?.id, band.id)
  }
}

extension BandConnectionTests {
  func testWorkoutReconnectionToSameBandDoesNotFillSourceGap() {
    let id = UUID()
    let t = Date()
    var workout = Workout(activity: .padel, start: t)
    workout.switchSource(to: id, at: t)
    workout.closeSource(id, at: t.addingTimeInterval(30))
    workout.switchSource(to: id, at: t.addingTimeInterval(90))
    XCTAssertEqual(workout.sources.count, 2)
    XCTAssertEqual(workout.sources[0].end, t.addingTimeInterval(30))
    XCTAssertEqual(workout.sources[1].start, t.addingTimeInterval(90))
  }
  func testOnlyConnectedFreshReadingCanBeLive() {
    let now = Date()
    XCTAssertEqual(LiveReadingState(timestamp: now, connected: true, now: now), .live)
    XCTAssertEqual(LiveReadingState(timestamp: now, connected: false, now: now), .recent)
    XCTAssertEqual(
      LiveReadingState(timestamp: now.addingTimeInterval(-100), connected: true, now: now), .stale)
    XCTAssertEqual(LiveReadingState(timestamp: nil, connected: true, now: now), .waiting)
  }
}

extension BandConnectionTests {
  func testBothWornRetainsCurrentAutomaticSource() {
    let a = UUID()
    let b = UUID()
    let now = Date()
    var selector = SourceSelector()
    let first = DeviceEvidence(
      deviceID: a, generation: .whoop4, connected: true, lastValidSample: now, wear: .onBody)
    XCTAssertEqual(selector.update([first], now: now)?.deviceID, a)
    let second = DeviceEvidence(
      deviceID: b, generation: .whoop5, connected: true, lastValidSample: now, wear: .onBody)
    XCTAssertNil(selector.update([first, second], now: now.addingTimeInterval(40)))
    XCTAssertEqual(selector.activeID, a)
  }
  func testCloudFreshnessAndPendingChanges() {
    let now = Date()
    XCTAssertTrue(SyncFreshness.shouldSync(lastSuccess: nil, pending: 0, now: now))
    XCTAssertFalse(SyncFreshness.shouldSync(lastSuccess: now, pending: 0, now: now))
    XCTAssertTrue(
      SyncFreshness.shouldSync(lastSuccess: now.addingTimeInterval(-301), pending: 0, now: now))
    XCTAssertTrue(SyncFreshness.shouldSync(lastSuccess: now, pending: 1, now: now))
  }
}

extension BandConnectionTests {
  func testPendingConnectionCannotReplacePeripheralBinding() {
    let id = UUID()
    var ledger = BandConnectionLedger()
    XCTAssertTrue(ledger.canReplaceBinding(id))
    _ = ledger.requestConnect(id)
    XCTAssertFalse(ledger.canReplaceBinding(id))
    _ = ledger.didConnect(id)
    XCTAssertFalse(ledger.canReplaceBinding(id))
    ledger.disconnect(id)
    XCTAssertFalse(ledger.canReplaceBinding(id))
    ledger.lostConnection(id)
    XCTAssertTrue(ledger.canReplaceBinding(id))
    XCTAssertFalse(ledger.didConnect(id))
  }
}

extension BandConnectionTests {
  func testFinishingAfterDisconnectDoesNotExtendClosedSource() {
    let id = UUID()
    let now = Date()
    var workout = Workout(activity: .cycling, start: now)
    workout.switchSource(to: id, at: now)
    workout.closeSource(id, at: now.addingTimeInterval(30))
    workout.finish(at: now.addingTimeInterval(90))
    XCTAssertEqual(workout.sources[0].end, now.addingTimeInterval(30))
    XCTAssertEqual(workout.end, now.addingTimeInterval(90))
  }
}

extension BandConnectionTests {
  func testOffBodyContactIsVisibleButNotAValidPhysiologicalReading() {
    let now = Date()
    let sample = Measurement(
      deviceID: UUID(), kind: .heartRate, timestamp: now, value: 70, origin: .measured,
      transport: "fixture", wear: .offBody)
    XCTAssertFalse(sample.valid)
    XCTAssertEqual(WearEvidence.current(sample, connected: true, now: now), .offBody)
    XCTAssertEqual(WearEvidence.current(sample, connected: false, now: now), .unknown)
    XCTAssertEqual(
      WearEvidence.current(sample, connected: true, now: now.addingTimeInterval(91)), .unknown)
  }
}
