import CoreBluetooth
import Foundation
import Observation
import TempoCore

@MainActor @Observable
final class BluetoothService: NSObject, @preconcurrency CBCentralManagerDelegate,
  @preconcurrency CBPeripheralDelegate
{
  struct Discovery: Identifiable {
    let id: UUID
    let name: String
    let generation: DeviceGeneration?
    let seenAt = Date()
  }
  var discovered: [Discovery] = []
  var status = "Bluetooth has not started"
  var connected: Set<UUID> = []
  var lastSamples: [UUID: TempoCore.Measurement] = [:]
  var battery: [UUID: BatteryReading] = [:]
  var historyStatus: [UUID: String] = [:]
  var lastHistoryCommit: [UUID: Date] = [:]
  var onHistoryChunk: ((UUID, UUID, HistoryChunk) -> Void)?
  private final class HistoryLink {
    let session = UUID()
    let generation: DeviceGeneration
    var sequence = 1
    var pending: [UInt8: UInt8] = [:]
    var assemblers: [String: FrameAssembler] = [:]
    var applicationFirmware: String?
    var storedRecordEstimate: UInt32?
    var transfer: BandHistoryTransfer?
    var lastAttempt: Date?
    var started: Date?
    var committedRecords = 0
    init(_ generation: DeviceGeneration) { self.generation = generation }
    func stopTransfer() {
      transfer?.interrupt()
      transfer = nil
      pending = pending.filter { $0.value != 22 }
    }
  }
  private var historyLinks: [UUID: HistoryLink] = [:]
  private static func customUUID(_ generation: DeviceGeneration, _ suffix: Int) -> CBUUID {
    CBUUID(
      string: generation == .whoop4
        ? "6108000\(suffix)-8d6d-82b8-614a-1c8cb0f8dcc6"
        : "fd4b000\(suffix)-cce1-4033-93ce-002d5875f58a")
  }

  private var lastBatteryRequest: [UUID: Date] = [:]
  var firmware: [UUID: String] = [:]
  var identity: [UUID: String] = [:]
  var rejectedPackets = 0
  var onConnectionChange: (() -> Void)?
  var onSample: ((TempoCore.Measurement) -> Void)?
  var onGeneration: ((UUID, DeviceGeneration) -> Void)?
  var onMetadata: ((UUID, String?, String?) -> Void)?
  var receivedHRPackets: [UUID: Int] = [:]
  var lastHRNotification: [UUID: Date] = [:]
  var storedHRPackets: [UUID: Int] = [:]
  var lastHRStored: [UUID: Date] = [:]
  private var subscribedAt: [UUID: Date] = [:]
  private var discoveryFailedAt: [UUID: Date] = [:]
  private var recovery: [UUID: CollectionRecovery] = [:]
  private var retryPolicy: [UUID: ConnectionRetry] = [:]
  private var retryTasks: [UUID: Task<Void, Never>] = [:]
  private var scanIntent = ScanIntent()
  private var central: CBCentralManager?
  private var collectionSuspended = false
  private var restoredPeripherals: [CBPeripheral] = []
  private var peripherals: [UUID: CBPeripheral] = [:]
  private var mapping: [UUID: UUID] = [:]
  private var generations: [UUID: DeviceGeneration] = [:]
  var connectionLedger = BandConnectionLedger()
  private var target: UUID? { connectionLedger.target }
  private var inFlight: Set<UUID> = []
  private var registeredIDs: Set<UUID> = []
  private let pausedKey = "Tempo.phonePausedBands.v1"
  private let mappingKey = "Tempo.phonePeripheralMappings.v1"
  static let service4 = CBUUID(string: "61080001-8d6d-82b8-614a-1c8cb0f8dcc6")
  static let service5 = CBUUID(string: "fd4b0001-cce1-4033-93ce-002d5875f58a")
  override init() {
    super.init()
    if let data = UserDefaults.standard.data(forKey: pausedKey),
      let ids = try? JSONDecoder().decode(Set<UUID>.self, from: data)
    {
      connectionLedger = BandConnectionLedger(pausedIDs: ids)
    }
    if let data = UserDefaults.standard.data(forKey: mappingKey),
      let m = try? JSONDecoder().decode([UUID: UUID].self, from: data)
    {
      mapping = m
    }
  }
  func start() {
    guard central == nil else { return }
    central = CBCentralManager(
      delegate: self, queue: .main,
      options: [
        CBCentralManagerOptionRestoreIdentifierKey: "app.tempo.central.v1",
        CBCentralManagerOptionShowPowerAlertKey: true,
      ])
  }
  @discardableResult private func poweredCommand(
    cleanup: Bool = false,
    manager: CBCentralManager? = nil, action: (CBCentralManager) -> Void
  ) -> Bool {
    guard let manager = manager ?? central else { return false }
    return BluetoothCommandPolicy.perform(
      poweredOn: manager.state == .poweredOn,
      collectionAllowed: !collectionSuspended, cleanup: cleanup
    ) { action(manager) }
  }
  func scan() {
    collectionSuspended = false
    scanIntent.request()
    start()
    guard scanIntent.consume(poweredOn: central?.state == .poweredOn, allowed: !collectionSuspended)
    else {
      status = "Waiting for Bluetooth to discover your bands"
      return
    }
    discovered = []
    poweredCommand {
      $0.scanForPeripherals(
        withServices: [Self.service4, Self.service5, CBUUID(string: "180D")],
        options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }
    status = "Searching for bands in pairing/broadcast mode"
  }
  func isConnected(_ id: UUID) -> Bool { connected.contains(id) }
  func suspend() {
    collectionSuspended = true
    for task in retryTasks.values { task.cancel() }
    retryTasks = [:]
    connectionLedger.suspend()
    inFlight = []
    stopScan()
    for p in peripherals.values where p.state != .disconnected {
      poweredCommand(cleanup: true) { $0.cancelPeripheralConnection(p) }
    }
    connected = []
    historyLinks = [:]
    lastSamples = [:]
    status = "Collection suspended for demonstration"
  }
  func stopScan() {
    scanIntent.cancel()
    poweredCommand(cleanup: true) { $0.stopScan() }
  }
  func register(peripheralID: UUID, deviceID: UUID, generation: DeviceGeneration) {
    guard connectionLedger.canReplaceBinding(deviceID) || mapping[peripheralID] == deviceID else {
      status = "Disconnect the registered band before matching a different peripheral"
      return
    }
    mapping = mapping.filter { $0.value != deviceID || $0.key == peripheralID }
    mapping[peripheralID] = deviceID
    generations[deviceID] = generation
    persistMapping()
    connect(deviceID: deviceID)
  }
  func configure(_ devices: [RegisteredDevice]) {
    let ids = Set(devices.map(\.id))
    for id in registeredIDs.subtracting(ids) { disconnect(deviceID: id) }
    registeredIDs = ids
    generations = Dictionary(uniqueKeysWithValues: devices.map { ($0.id, $0.generation) })
  }
  func deviceID(for peripheralID: UUID) -> UUID? { mapping[peripheralID] }
  func isPaused(_ id: UUID) -> Bool { connectionLedger.pausedIDs.contains(id) }
  func state(_ id: UUID) -> BandLinkState { connectionLedger.state(id) }
  var availableDiscoveries: [Discovery] {
    discovered.filter { discovery in
      mapping[discovery.id].map { connectionLedger.canOfferConnection($0) } ?? true
    }
  }
  func resumeCollection(preferred: UUID?) {
    collectionSuspended = false
    start()
    if let id = target ?? preferred, !isPaused(id) { connect(deviceID: id) }
  }
  func bandStatus(_ id: UUID, now: Date = Date()) -> String {
    if isConnected(id) { return "Connected" }
    if state(id) == .connecting { return "Connecting" }
    if isPaused(id) { return "Disconnected by you" }
    if discovered.contains(where: { mapping[$0.id] == id && now.timeIntervalSince($0.seenAt) < 30 })
    {
      return "Nearby"
    }
    return "Disconnected"
  }
  func wearStatus(_ id: UUID, now: Date = Date()) -> String {
    switch WearEvidence.current(lastSamples[id], connected: isConnected(id), now: now) {
    case .onBody: return "On-body reported"
    case .offBody: return "Off-body reported"
    case .unknown: return "Wear not reported"
    }
  }
  func disconnect(deviceID: UUID) {
    retryTasks.removeValue(forKey: deviceID)?.cancel()
    retryPolicy.removeValue(forKey: deviceID)
    discoveryFailedAt.removeValue(forKey: deviceID)
    subscribedAt.removeValue(forKey: deviceID)
    recovery.removeValue(forKey: deviceID)
    connectionLedger.disconnect(deviceID)
    persistPaused()
    connected.remove(deviceID)
    historyLinks.removeValue(forKey: deviceID)
    historyStatus[deviceID] = "Interrupted · stored chunks retained"
    lastSamples.removeValue(forKey: deviceID)
    for (key, id) in mapping where id == deviceID {
      if let p = peripherals[key], p.state != .disconnected {
        poweredCommand(cleanup: true) { $0.cancelPeripheralConnection(p) }
      }
    }
    onConnectionChange?()
    if connected.isEmpty { status = "Disconnected by you; tap Connect to resume" }
  }
  private func persistPaused() {
    if let data = try? JSONEncoder().encode(connectionLedger.pausedIDs) {
      UserDefaults.standard.set(data, forKey: pausedKey)
    }
  }
  func connect(deviceID: UUID) {
    guard registeredIDs.contains(deviceID),
      let p = mapping.first(where: { $0.value == deviceID })?.key
    else {
      status = "Scan and explicitly match this band to reconnect"
      return
    }
    collectionSuspended = false
    start()
    let requested = connectionLedger.requestConnect(deviceID)
    if requested { persistPaused() }
    guard central?.state == .poweredOn else {
      status = "Waiting for Bluetooth to connect"
      return
    }
    let peripheral = peripherals[p] ?? central?.retrievePeripherals(withIdentifiers: [p]).first
    guard let peripheral else {
      connectionLedger.failedConnection(deviceID)
      status = "Band not found; scan to reconnect"
      return
    }
    if peripheral.state == .connected {
      if connectionLedger.shouldReconnect(deviceID) {
        _ = connectionLedger.didConnect(deviceID)
        connected.insert(deviceID)
      }
      peripherals[p] = peripheral
      peripheral.delegate = self
      peripheral.discoverServices([
        CBUUID(string: "180D"), CBUUID(string: "180A"), CBUUID(string: "180F"), Self.service4,
        Self.service5,
      ])
      status = "Connected; checking measurement services"
      return
    }
    guard !inFlight.contains(deviceID), connectionLedger.shouldReconnect(deviceID) else { return }
    for (key, id) in mapping where id != deviceID {
      if let old = peripherals[key], old.state != .disconnected {
        poweredCommand(cleanup: true) { $0.cancelPeripheralConnection(old) }
      }
    }
    peripherals[p] = peripheral
    peripheral.delegate = self
    inFlight.insert(deviceID)
    poweredCommand {
      $0.connect(peripheral, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
    }
    status = "Connecting to registered band"
  }
  private func persistMapping() {
    if let d = try? JSONEncoder().encode(mapping) {
      UserDefaults.standard.set(d, forKey: mappingKey)
    }
  }
  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    switch central.state {
    case .poweredOn:
      status = "Bluetooth ready"
      restoreWhenPoweredOn(central)
      if scanIntent.pending, !collectionSuspended { scan() }
      if !collectionSuspended, let target, !isConnected(target) { connect(deviceID: target) }
    case .poweredOff:
      historyLinks = [:]
      status = "Bluetooth is off"
      connected = []
      inFlight = []
      for id in registeredIDs { connectionLedger.failedConnection(id) }
    case .unauthorized:
      invalidatePeripherals()
      status = "Bluetooth permission denied. Enable it in Settings."
      connected = []
      inFlight = []
      for id in registeredIDs { connectionLedger.failedConnection(id) }
    case .unsupported:
      status = "Bluetooth unavailable"
      invalidatePeripherals()
    case .resetting:
      invalidatePeripherals()
      status = "Bluetooth is restarting"
      connected = []
      inFlight = []
      for id in registeredIDs { connectionLedger.failedConnection(id) }
    default:
      invalidatePeripherals()
      status = "Waiting for Bluetooth"
    }
  }
  private func invalidatePeripherals() {
    peripherals = [:]
    historyLinks = [:]
    restoredPeripherals = []
    discovered = []
    connected = []
    inFlight = []
    for id in registeredIDs { connectionLedger.failedConnection(id) }
  }
  func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
    restoredPeripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
    restoreWhenPoweredOn(central)
  }
  private func restoreWhenPoweredOn(_ manager: CBCentralManager) {
    guard manager.state == .poweredOn else { return }
    let restored = restoredPeripherals
    restoredPeripherals = []
    for p in restored {
      peripherals[p.identifier] = p
      p.delegate = self
      guard !collectionSuspended, let id = mapping[p.identifier], registeredIDs.contains(id),
        !isPaused(id), target == nil || target == id
      else {
        poweredCommand(cleanup: true, manager: manager) { $0.cancelPeripheralConnection(p) }
        continue
      }
      if target == nil { _ = connectionLedger.requestConnect(id) }
      if p.state == .connected {
        _ = connectionLedger.didConnect(id)
        connected.insert(id)
        onConnectionChange?()
        status = "Connection restored; checking services"
        poweredCommand(manager: manager) { _ in
          p.discoverServices([
            CBUUID(string: "180D"), CBUUID(string: "180A"), CBUUID(string: "180F"), Self.service4,
            Self.service5,
          ])
        }
      } else {
        connect(deviceID: id)
      }
    }
  }
  func centralManager(
    _ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any], rssi RSSI: NSNumber
  ) {
    guard central.state == .poweredOn, !collectionSuspended else { return }
    peripherals[peripheral.identifier] = peripheral
    let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
    let generation = BandGenerationEvidence.resolve(
      hasWhoop4Service: services.contains(Self.service4),
      hasWhoop5Service: services.contains(Self.service5))
    if !discovered.contains(where: { $0.id == peripheral.identifier }) {
      discovered.append(
        Discovery(
          id: peripheral.identifier, name: peripheral.name ?? "Unnamed heart-rate device",
          generation: generation))
    }
    // RSSI is deliberately not a wear signal.
  }
  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    guard central.state == .poweredOn, !collectionSuspended,
      let id = mapping[peripheral.identifier], registeredIDs.contains(id),
      connectionLedger.didConnect(id)
    else {
      poweredCommand(cleanup: true, manager: central) { $0.cancelPeripheralConnection(peripheral) }
      return
    }
    inFlight.remove(id)
    connected.insert(id)
    retryTasks.removeValue(forKey: id)?.cancel()
    retryPolicy[id] = ConnectionRetry()
    discoveryFailedAt.removeValue(forKey: id)
    subscribedAt.removeValue(forKey: id)
    discovered.removeAll { $0.id == peripheral.identifier }
    onConnectionChange?()
    peripheral.delegate = self
    poweredCommand(cleanup: true, manager: central) { $0.stopScan() }
    status = "Connected; discovering heart-rate service"
    peripheral.discoverServices([
      CBUUID(string: "180D"), CBUUID(string: "180A"), CBUUID(string: "180F"), Self.service4,
      Self.service5,
    ])
  }
  func centralManager(
    _ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?
  ) {
    if let id = mapping[peripheral.identifier] {
      inFlight.remove(id)
      connectionLedger.failedConnection(id)
      connected.remove(id)
      onConnectionChange?()
      scheduleConnectionRetry(id)
    }
    status = "Connection failed. Check pairing mode and competing connections."
  }
  func centralManager(
    _ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?
  ) {
    guard let id = mapping[peripheral.identifier] else { return }
    inFlight.remove(id)
    connected.remove(id)
    discoveryFailedAt.removeValue(forKey: id)
    subscribedAt.removeValue(forKey: id)
    historyLinks.removeValue(forKey: id)
    historyStatus[id] = "Interrupted · stored chunks retained"
    connectionLedger.lostConnection(id)
    onConnectionChange?()
    if connectionLedger.shouldReconnect(id), registeredIDs.contains(id), central.state == .poweredOn
    {
      inFlight.insert(id)
      poweredCommand(manager: central) { $0.connect(peripheral) }
      status = "Connection interrupted; waiting to reconnect"
    } else if connected.isEmpty {
      status = "Disconnected; tap Connect when ready"
    }
  }
  private func scheduleConnectionRetry(_ id: UUID) {
    guard
      let delay = retryPolicy[id, default: ConnectionRetry()].nextDelay(
        allowed: !collectionSuspended && registeredIDs.contains(id)
          && connectionLedger.shouldReconnect(id))
    else { return }
    retryTasks.removeValue(forKey: id)?.cancel()
    retryTasks[id] = Task { [weak self] in
      try? await Task.sleep(for: .seconds(delay))
      guard !Task.isCancelled, let self, !self.collectionSuspended,
        self.registeredIDs.contains(id), self.connectionLedger.shouldReconnect(id),
        self.central?.state == .poweredOn, !self.isConnected(id)
      else { return }
      self.connect(deviceID: id)
    }
  }
  func recordStoredSample(_ sample: TempoCore.Measurement) {
    storedHRPackets[sample.deviceID, default: 0] += 1
    lastHRStored[sample.deviceID] = Date()
  }
  /// Called only while the app is foreground active. No promise of background timer execution.
  func checkCollectionHealth(now: Date = Date()) {
    guard !collectionSuspended, central?.state == .poweredOn else { return }
    for id in connected {
      guard historyLinks[id]?.transfer == nil, let p = historyPeripheral(id),
        let since = subscribedAt[id] ?? discoveryFailedAt[id]
      else { continue }
      let action = recovery[id, default: CollectionRecovery()].check(
        now: now, subscribedAt: since,
        lastNotification: lastHRNotification[id].flatMap { $0 >= since ? $0 : nil },
        offBody: WearEvidence.current(lastSamples[id], connected: true, now: now) == .offBody)
      switch action {
      case .none: break
      case .resubscribe:
        status = "Heart-rate stream quiet; checking subscription"
        if discoveryFailedAt[id] != nil {
          p.discoverServices([
            CBUUID(string: "180D"), CBUUID(string: "180A"), CBUUID(string: "180F"), Self.service4,
            Self.service5,
          ])
        } else {
          for service in p.services ?? [] where service.uuid == CBUUID(string: "180D") {
            p.discoverCharacteristics([CBUUID(string: "2A37")], for: service)
          }
        }
      case .reconnect:
        status = "Heart-rate stream interrupted; reconnecting selected band"
        historyLinks.removeValue(forKey: id)
        poweredCommand { $0.cancelPeripheralConnection(p) }
      }
    }
    refreshHistoryIfNeeded()
  }
  func historyApplicationFirmware(_ id: UUID) -> String? { historyLinks[id]?.applicationFirmware }
  private func historyPeripheral(_ id: UUID) -> CBPeripheral? {
    peripherals.values.first { mapping[$0.identifier] == id && canUsePeripheral($0) }
  }
  private func prepareHistoryLink(_ p: CBPeripheral, id: UUID) {
    guard canUsePeripheral(p), let link = historyLinks[id], link.lastAttempt == nil,
      let service = p.services?.first(where: {
        $0.uuid == (link.generation == .whoop4 ? Self.service4 : Self.service5)
      }),
      let chars = service.characteristics,
      chars.contains(where: {
        $0.uuid == Self.customUUID(link.generation, 2) && $0.properties.contains(.write)
      }),
      ([3, 4, 5] + (link.generation == .whoop5 ? [7] : [])).allSatisfy({ n in
        chars.contains { $0.uuid == Self.customUUID(link.generation, n) && $0.isNotifying }
      })
    else { return }
    link.lastAttempt = Date()
    historyStatus[id] = "Checking history connection and application firmware"
    sendHistoryCommand(
      id, command: link.generation == .whoop4 ? 26 : 145,
      body: Data([link.generation == .whoop4 ? 0 : 1]))
  }
  private func sendHistoryCommand(_ id: UUID, command: UInt8, body: Data) {
    guard let p = historyPeripheral(id), let link = historyLinks[id], link.sequence <= 250,
      link.pending.count < 4,
      let c = p.services?.first(where: {
        $0.uuid == (link.generation == .whoop4 ? Self.service4 : Self.service5)
      })?.characteristics?.first(where: {
        $0.uuid == Self.customUUID(link.generation, 2) && $0.properties.contains(.write)
      })
    else {
      historyStatus[id] = "History connection unavailable; reconnect to retry"
      return
    }
    guard [UInt8(7), 20, 22, 23, 26, 34, 145].contains(command) else { return }
    let sequence = UInt8(link.sequence)
    link.sequence += 1
    if command != 23 && command != 20 { link.pending[sequence] = command }
    p.writeValue(
      WhoopReadProtocol.command(
        generation: link.generation, sequence: sequence,
        command: command, body: body), for: c, type: .withResponse)
    guard command != 23 && command != 20 else { return }
    let session = link.session
    Task { [weak self] in
      try? await Task.sleep(for: .seconds(20))
      guard let self, let current = self.historyLinks[id], current.session == session,
        current.pending[sequence] == command
      else { return }
      guard
        HistoryRequestDeadline.shouldExpire(
          command: command, streamStarted: current.transfer?.hasStarted == true)
      else { return }
      current.pending.removeValue(forKey: sequence)
      current.stopTransfer()
      self.historyStatus[id] = "History request timed out · gaps remain"
    }
  }
  func refreshHistoryIfNeeded(force: Bool = false) {
    for (id, link) in historyLinks where historyPeripheral(id) != nil {
      let due = force || link.lastAttempt.map({ Date().timeIntervalSince($0) >= 900 }) ?? true
      if link.pending.isEmpty, link.transfer == nil, due {
        if link.applicationFirmware == nil, let p = historyPeripheral(id) {
          link.lastAttempt = nil
          prepareHistoryLink(p, id: id)
          continue
        }
        if link.generation == .whoop5, link.applicationFirmware == "50.42.1.0" {
          link.lastAttempt = Date()
          link.storedRecordEstimate = nil
          sendHistoryCommand(id, command: 34, body: Data())
          continue
        }
      }
      if let started = link.started, link.transfer != nil, Date().timeIntervalSince(started) > 120 {
        link.stopTransfer()
        sendHistoryCommand(id, command: 20, body: Data([0]))
        historyStatus[id] = "History interrupted · committed data retained"
      }
      guard link.transfer == nil, link.pending.isEmpty,
        WhoopReadProtocol.canRetrieve(
          generation: link.generation, applicationFirmware: link.applicationFirmware),
        force || link.lastAttempt.map({ Date().timeIntervalSince($0) >= 900 }) ?? true
      else { continue }
      beginHistoryTransfer(id, link: link)
    }
  }
  private func beginHistoryTransfer(_ id: UUID, link: HistoryLink) {
    guard link.transfer == nil, link.pending.isEmpty,
      WhoopReadProtocol.canRetrieve(
        generation: link.generation, applicationFirmware: link.applicationFirmware,
        storedRecordEstimate: link.storedRecordEstimate)
    else { return }
    link.lastAttempt = Date()
    link.started = Date()
    link.committedRecords = 0
    link.transfer = BandHistoryTransfer(generation: link.generation)
    historyStatus[id] = "Requesting stored band records · experimental"
    sendHistoryCommand(id, command: 22, body: Data([0]))
    let session = link.session
    let attemptID = link.transfer?.attemptID
    Task { [weak self] in
      try? await Task.sleep(for: .seconds(120))
      guard !Task.isCancelled, let self, let current = self.historyLinks[id],
        current.session == session, current.transfer?.attemptID == attemptID,
        current.transfer != nil
      else { return }
      current.stopTransfer()
      self.sendHistoryCommand(id, command: 20, body: Data([0]))
      self.historyStatus[id] = "History interrupted · committed data retained"
    }

  }

  private func receiveHistory(
    _ data: Data, peripheral: CBPeripheral, characteristic: CBCharacteristic, id: UUID
  ) {
    guard let link = historyLinks[id] else { return }
    let key = characteristic.uuid.uuidString
    var assembler = link.assemblers[key] ?? FrameAssembler(generation: link.generation)
    let previouslyDiscarded = assembler.discardedBytes
    let frames = assembler.append(data)
    link.assemblers[key] = assembler
    if assembler.discardedBytes != previouslyDiscarded {
      link.stopTransfer()
      historyStatus[id] = "History bytes failed integrity · acknowledgement withheld"
      return
    }
    for raw in frames {
      do {
        let frame = try WhoopFrame.parse(raw, generation: link.generation)
        if frame.type == 36 {
          let reply = try WhoopReadProtocol.reply(frame)
          guard link.pending[reply.origin] == reply.command else { continue }
          if reply.result == 2 { continue }
          link.pending.removeValue(forKey: reply.origin)
          guard reply.result == 1 else {
            link.stopTransfer()
            historyStatus[id] =
              "Band refused history request \(reply.command) (result \(reply.result)) · gaps remain"
            continue
          }
          if reply.command == 26 && link.generation == .whoop4 {
            sendHistoryCommand(id, command: 7, body: Data())
          } else if reply.command == 7 || reply.command == 145 {
            let version = try WhoopReadProtocol.applicationFirmware(frame)
            link.applicationFirmware = version
            firmware[id] = version
            onMetadata?(id, version, identity[id])
            if link.generation == .whoop4 {
              if WhoopReadProtocol.canRetrieve(generation: .whoop4, applicationFirmware: version) {
                refreshHistoryIfNeeded(force: true)
              } else {
                historyStatus[id] = "History unavailable for application firmware \(version)"
              }
            } else {
              historyStatus[id] = "Checking Whoop5 stored range · experimental"
              if version == "50.42.1.0" { sendHistoryCommand(id, command: 34, body: Data()) }
            }
          } else if reply.command == 34, link.generation == .whoop5 {
            let count = try WhoopReadProtocol.recordCountEstimate(reply.body)
            link.storedRecordEstimate = count
            historyStatus[id] =
              count == 0
              ? "Stored-range estimate is zero · gaps remain"
              : "Backlog estimate \(count) records · requesting transfer"
            if count > 0 { beginHistoryTransfer(id, link: link) }
          }
        } else if var transfer = link.transfer {
          if frame.type == 49, frame.command == 2,
            !HistoryAssemblyGate.canClose(
              bufferedBytes: link.assemblers.values.map(\.bufferedBytes))
          {
            throw PacketError.truncated
          }
          let event = try transfer.receive(frame)
          link.transfer = transfer
          switch event {
          case .none: break
          case .chunk(let chunk):
            historyStatus[id] = "Saving retrieved band records"
            onHistoryChunk?(id, link.session, chunk)
          case .repeatCommitted(let body): sendHistoryCommand(id, command: 23, body: body)
          case .complete:
            link.stopTransfer()
            historyStatus[id] =
              link.committedRecords == 0
              ? "Transfer returned no usable HR · gaps remain"
              : "Transfer complete · \(link.committedRecords) HR readings stored; coverage may remain incomplete"
          }
        }
      } catch {
        link.stopTransfer()
        historyStatus[id] = "History layout or integrity check failed · gaps remain"
      }
    }
  }
  func historyChunkCommitted(
    deviceID: UUID, session: UUID, attemptID: UUID, token: Data, count: Int
  ) {
    guard let link = historyLinks[deviceID], link.session == session, var transfer = link.transfer,
      let body = try? transfer.committed(token: token, attemptID: attemptID)
    else { return }
    link.transfer = transfer
    link.committedRecords += count
    lastHistoryCommit[deviceID] = Date()
    historyStatus[deviceID] = "\(link.committedRecords) historical HR readings stored · retrieving"
    sendHistoryCommand(deviceID, command: 23, body: body)
  }
  func historyChunkFailed(deviceID: UUID, session: UUID, attemptID: UUID) {
    guard let link = historyLinks[deviceID], link.session == session,
      link.transfer?.attemptID == attemptID
    else { return }
    link.stopTransfer()
    historyStatus[deviceID] = "History storage failed · acknowledgement withheld"
  }
  func peripheral(
    _ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?
  ) {
    guard error != nil, let id = mapping[peripheral.identifier],
      characteristic.service?.uuid == Self.service4 || characteristic.service?.uuid == Self.service5
    else { return }
    historyLinks[id]?.stopTransfer()
    historyStatus[id] = "History connection write failed · live HR is separate"
  }
  func refreshBatteryIfNeeded() {
    guard !collectionSuspended, central?.state == .poweredOn else { return }
    for p in peripherals.values where canUsePeripheral(p) {
      guard let id = mapping[p.identifier],
        lastBatteryRequest[id].map({ Date().timeIntervalSince($0) >= 900 }) ?? true
      else { continue }
      guard p.services?.filter({ $0.uuid == CBUUID(string: "180F") }).count == 1,
        let service = p.services?.first(where: { $0.uuid == CBUUID(string: "180F") }),
        let characteristic = service.characteristics?.first(where: {
          $0.uuid == CBUUID(string: "2A19") && $0.properties.contains(.read)
        })
      else { continue }
      lastBatteryRequest[id] = Date()
      p.readValue(for: characteristic)
    }
  }
  private func canUsePeripheral(_ peripheral: CBPeripheral) -> Bool {
    guard central?.state == .poweredOn, !collectionSuspended, peripheral.state == .connected,
      let id = mapping[peripheral.identifier], registeredIDs.contains(id)
    else { return false }
    return connectionLedger.shouldReconnect(id)
  }
  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    guard canUsePeripheral(peripheral) else {
      return
    }
    guard error == nil else {
      status = "Service discovery failed; recovery pending"
      if let id = mapping[peripheral.identifier], discoveryFailedAt[id] == nil {
        discoveryFailedAt[id] = Date()
      }
      return
    }
    if let id = mapping[peripheral.identifier] {
      let services = peripheral.services ?? []
      if let generation = BandGenerationEvidence.resolve(
        hasWhoop4Service: services.contains { $0.uuid == Self.service4 },
        hasWhoop5Service: services.contains { $0.uuid == Self.service5 })
      {
        generations[id] = generation
        onGeneration?(id, generation)
      }
      if !services.contains(where: { $0.uuid == CBUUID(string: "180D") }) {
        discoveryFailedAt.removeValue(forKey: id)
        status = "Connected, but no live HR service exposed. Enable broadcast if supported."
      }
    }
    for s in peripheral.services ?? [] {
      if s.uuid == CBUUID(string: "180D") {
        peripheral.discoverCharacteristics([CBUUID(string: "2A37")], for: s)
      } else if s.uuid == CBUUID(string: "180F"),
        peripheral.services?.filter({ $0.uuid == CBUUID(string: "180F") }).count == 1
      {
        peripheral.discoverCharacteristics([CBUUID(string: "2A19")], for: s)
      } else if s.uuid == Self.service4 || s.uuid == Self.service5,
        peripheral.services?.filter({ $0.uuid == Self.service4 || $0.uuid == Self.service5 }).count
          == 1
      {
        let generation: DeviceGeneration = s.uuid == Self.service4 ? .whoop4 : .whoop5
        peripheral.discoverCharacteristics(
          ([2, 3, 4, 5] + (generation == .whoop5 ? [7] : [])).map {
            Self.customUUID(generation, $0)
          }, for: s)
      } else if s.uuid == CBUUID(string: "180A") {
        peripheral.discoverCharacteristics(
          [CBUUID(string: "2A26"), CBUUID(string: "2A25"), CBUUID(string: "2A24")], for: s)
      }
    }
  }
  func peripheral(
    _ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?
  ) {
    guard canUsePeripheral(peripheral) else {
      return
    }
    guard error == nil else {
      status = "Characteristic discovery failed"
      if service.uuid == CBUUID(string: "180D"), let id = mapping[peripheral.identifier],
        discoveryFailedAt[id] == nil
      {
        discoveryFailedAt[id] = Date()
      }
      return
    }
    if service.uuid == Self.service4 || service.uuid == Self.service5,
      let id = mapping[peripheral.identifier]
    {
      let generation: DeviceGeneration = service.uuid == Self.service4 ? .whoop4 : .whoop5
      if historyLinks[id] == nil {
        historyLinks[id] = HistoryLink(generation)
        historyStatus[id] = "Checking stored-history notification channels"
      }
      for c in service.characteristics ?? [] where c.uuid != Self.customUUID(generation, 2) {
        if c.properties.contains(.notify) || c.properties.contains(.indicate) {
          peripheral.setNotifyValue(true, for: c)
        }
      }
      prepareHistoryLink(peripheral, id: id)
      return
    }
    if service.uuid == CBUUID(string: "180D"), let id = mapping[peripheral.identifier] {
      discoveryFailedAt.removeValue(forKey: id)
    }
    for c in service.characteristics ?? [] {
      if service.uuid == CBUUID(string: "180F"), c.uuid == CBUUID(string: "2A19") {
        if c.properties.contains(.read) {
          if let id = mapping[peripheral.identifier] { lastBatteryRequest[id] = Date() }
          peripheral.readValue(for: c)
        }
        if c.properties.contains(.notify) { peripheral.setNotifyValue(true, for: c) }
      } else if service.uuid == CBUUID(string: "180D"), c.uuid == CBUUID(string: "2A37"),
        c.properties.contains(.notify)
      {
        if let id = mapping[peripheral.identifier], subscribedAt[id] == nil {
          subscribedAt[id] = Date()
        }
        peripheral.setNotifyValue(true, for: c)
      } else if c.properties.contains(.read) {
        peripheral.readValue(for: c)
      }
    }
  }
  func peripheral(
    _ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic,
    error: Error?
  ) {
    guard canUsePeripheral(peripheral) else { return }
    if characteristic.service?.uuid == Self.service4
      || characteristic.service?.uuid == Self.service5,
      let id = mapping[peripheral.identifier]
    {
      if error != nil {
        historyStatus[id] = "History notification subscription failed"
      } else {
        prepareHistoryLink(peripheral, id: id)
      }
      return
    }
    guard characteristic.uuid == CBUUID(string: "2A37"),
      characteristic.service?.uuid == CBUUID(string: "180D")
    else { return }
    status =
      error == nil && characteristic.isNotifying
      ? "Listening for live heart rate"
      : "Band refused notifications. Enable HR broadcast if supported."
  }
  func peripheral(
    _ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?
  ) {
    guard central?.state == .poweredOn, !collectionSuspended, peripheral.state == .connected,
      error == nil, let data = characteristic.value, let id = mapping[peripheral.identifier],
      registeredIDs.contains(id), connectionLedger.state(id) == .connected, !isPaused(id)
    else { return }
    if characteristic.service?.uuid == Self.service4
      || characteristic.service?.uuid == Self.service5
    {
      receiveHistory(data, peripheral: peripheral, characteristic: characteristic, id: id)
    } else if characteristic.uuid == CBUUID(string: "2A19"),
      characteristic.service?.uuid == CBUUID(string: "180F"),
      peripheral.services?.filter({ $0.uuid == CBUUID(string: "180F") }).count == 1
    {
      if let reading = try? BatteryReading.parse(data, at: Date()) {
        battery[id] = reading
      } else {
        rejectedPackets += 1
      }
    } else if characteristic.uuid == CBUUID(string: "2A37"),
      characteristic.service?.uuid == CBUUID(string: "180D")
    {
      lastHRNotification[id] = Date()
      receivedHRPackets[id, default: 0] += 1
      recovery[id, default: CollectionRecovery()].received()
      do {
        let packet = try HeartRatePacket.parse(data)
        let m = TempoCore.Measurement(
          deviceID: id, kind: .heartRate, timestamp: Date(), value: Double(packet.bpm),
          origin: .measured, transport: "bluetooth-hrs", rrMilliseconds: packet.rrMilliseconds,
          wear: packet.contact)
        lastSamples[id] = m
        status = "Receiving live heart rate"
        onSample?(m)
      } catch {
        rejectedPackets += 1
        status = "Invalid heart-rate packet rejected"
      }
    } else if characteristic.uuid == CBUUID(string: "2A26"),
      let text = String(data: data, encoding: .utf8)
    {
      firmware[id] =
        historyLinks[id]?.applicationFirmware ?? text.trimmingCharacters(in: .controlCharacters)
      onMetadata?(id, firmware[id], identity[id])
    } else if characteristic.uuid == CBUUID(string: "2A25"), generations[id] == .whoop5,
      let serial = String(data: data, encoding: .utf8), !serial.isEmpty
    {
      identity[id] = StableID.hash(serial.trimmingCharacters(in: .controlCharacters))
      onMetadata?(id, firmware[id], identity[id])
    }
  }
}
