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
  private var lastBatteryRequest: [UUID: Date] = [:]
  var firmware: [UUID: String] = [:]
  var identity: [UUID: String] = [:]
  var rejectedPackets = 0
  var onConnectionChange: (() -> Void)?
  var onSample: ((TempoCore.Measurement) -> Void)?
  var onGeneration: ((UUID, DeviceGeneration) -> Void)?
  var onMetadata: ((UUID, String?, String?) -> Void)?
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
    start()
    guard central?.state == .poweredOn else {
      status = "Enable Bluetooth to discover your bands"
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
    connectionLedger.suspend()
    inFlight = []
    stopScan()
    for p in peripherals.values where p.state != .disconnected {
      poweredCommand(cleanup: true) { $0.cancelPeripheralConnection(p) }
    }
    connected = []
    lastSamples = [:]
    status = "Collection suspended for demonstration"
  }
  func stopScan() { poweredCommand(cleanup: true) { $0.stopScan() } }
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
    connectionLedger.disconnect(deviceID)
    persistPaused()
    connected.remove(deviceID)
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
      if !collectionSuspended, let target, !isConnected(target) { connect(deviceID: target) }
    case .poweredOff:
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
    }
    status = "Connection failed. Check pairing mode and competing connections."
  }
  func centralManager(
    _ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?
  ) {
    guard let id = mapping[peripheral.identifier] else { return }
    inFlight.remove(id)
    connected.remove(id)
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
      status = "Service discovery failed"
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
        status = "Connected, but no live HR service exposed. Enable broadcast if supported."
      }
    }
    for s in peripheral.services ?? [] {
      if s.uuid == CBUUID(string: "180D") {
        peripheral.discoverCharacteristics([CBUUID(string: "2A37")], for: s)
      } else if s.uuid == CBUUID(string: "180F"),
        peripheral.services?.filter({ $0.uuid == CBUUID(string: "180F") }).count == 1 {
        peripheral.discoverCharacteristics([CBUUID(string: "2A19")], for: s)
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
      return
    }
    for c in service.characteristics ?? [] {
      if service.uuid == CBUUID(string: "180F"), c.uuid == CBUUID(string: "2A19") {
        if c.properties.contains(.read) {
          if let id = mapping[peripheral.identifier] { lastBatteryRequest[id] = Date() }
          peripheral.readValue(for: c)
        }
        if c.properties.contains(.notify) { peripheral.setNotifyValue(true, for: c) }
      } else if c.uuid == CBUUID(string: "2A37") && c.properties.contains(.notify) {
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
    guard canUsePeripheral(peripheral), characteristic.uuid == CBUUID(string: "2A37"),
      characteristic.service?.uuid == CBUUID(string: "180D") else { return }
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
    if characteristic.uuid == CBUUID(string: "2A19"),
      characteristic.service?.uuid == CBUUID(string: "180F"),
      peripheral.services?.filter({ $0.uuid == CBUUID(string: "180F") }).count == 1
    {
      if let reading = try? BatteryReading.parse(data, at: Date()) {
        battery[id] = reading
      } else {
        rejectedPackets += 1
      }
    } else if characteristic.uuid == CBUUID(string: "2A37") {
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
      firmware[id] = text.trimmingCharacters(in: .controlCharacters)
      onMetadata?(id, firmware[id], identity[id])
    } else if characteristic.uuid == CBUUID(string: "2A25"), generations[id] == .whoop5,
      let serial = String(data: data, encoding: .utf8), !serial.isEmpty
    {
      identity[id] = StableID.hash(serial.trimmingCharacters(in: .controlCharacters))
      onMetadata?(id, firmware[id], identity[id])
    }
  }
}
