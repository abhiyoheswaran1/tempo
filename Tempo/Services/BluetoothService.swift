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
  }
  var discovered: [Discovery] = []
  var status = "Bluetooth has not started"
  var connected: Set<UUID> = []
  var lastSamples: [UUID: TempoCore.Measurement] = [:]
  var firmware: [UUID: String] = [:]
  var identity: [UUID: String] = [:]
  var rejectedPackets = 0
  var onConnectionChange: (() -> Void)?
  var onSample: ((TempoCore.Measurement) -> Void)?
  var onMetadata: ((UUID, String?, String?) -> Void)?
  private var central: CBCentralManager?
  private var peripherals: [UUID: CBPeripheral] = [:]
  private var mapping: [UUID: UUID] = [:]
  private var generations: [UUID: DeviceGeneration] = [:]
  private var target: UUID?
  private let mappingKey = "Tempo.phonePeripheralMappings.v1"
  static let service4 = CBUUID(string: "61080001-8d6d-82b8-614a-1c8cb0f8dcc6")
  static let service5 = CBUUID(string: "fd4b0001-cce1-4033-93ce-002d5875f58a")
  override init() {
    super.init()
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
  func scan() {
    start()
    guard central?.state == .poweredOn else {
      status = "Enable Bluetooth to discover your bands"
      return
    }
    discovered = []
    central?.scanForPeripherals(
      withServices: [Self.service4, Self.service5, CBUUID(string: "180D")],
      options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    status = "Searching for bands in pairing/broadcast mode"
  }
  func isConnected(_ id: UUID) -> Bool { connected.contains(id) }
  func suspend() {
    target = nil
    central?.stopScan()
    for p in peripherals.values where p.state != .disconnected {
      central?.cancelPeripheralConnection(p)
    }
    connected = []
    lastSamples = [:]
    status = "Collection suspended for demonstration"
  }
  func stopScan() { central?.stopScan() }
  func register(peripheralID: UUID, deviceID: UUID, generation: DeviceGeneration) {
    mapping[peripheralID] = deviceID
    generations[deviceID] = generation
    persistMapping()
    connect(deviceID: deviceID)
  }
  func configure(_ devices: [RegisteredDevice]) {
    for d in devices { generations[d.id] = d.generation }
  }
  func connect(deviceID: UUID) {
    start()
    target = deviceID
    guard central?.state == .poweredOn else { return }
    // One connection by default until concurrent hardware behavior is validated.
    for (p, id) in mapping where id != deviceID {
      if let peripheral = peripherals[p], peripheral.state != .disconnected {
        central?.cancelPeripheralConnection(peripheral)
      }
    }
    guard let p = mapping.first(where: { $0.value == deviceID })?.key else {
      status = "Reconnect this restored band by scanning and explicitly matching it"
      return
    }
    let peripheral = peripherals[p] ?? central?.retrievePeripherals(withIdentifiers: [p]).first
    guard let peripheral else {
      status = "Band not found; scan to reconnect"
      return
    }
    peripherals[p] = peripheral
    peripheral.delegate = self
    central?.connect(peripheral, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
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
      if let target { connect(deviceID: target) }
    case .poweredOff:
      status = "Bluetooth is off"
      connected = []
    case .unauthorized:
      status = "Bluetooth permission denied. Enable it in Settings."
      connected = []
    case .unsupported: status = "Bluetooth unavailable"
    case .resetting:
      status = "Bluetooth is restarting"
      connected = []
    default: status = "Waiting for Bluetooth"
    }
  }
  func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
    for p in dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? [] {
      peripherals[p.identifier] = p
      p.delegate = self
      if mapping[p.identifier] != nil {
        if p.state == .connected {
          p.discoverServices([CBUUID(string: "180D"), CBUUID(string: "180A")])
        } else {
          central.connect(p)
        }
      } else {
        central.cancelPeripheralConnection(p)
      }
    }
  }
  func centralManager(
    _ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any], rssi RSSI: NSNumber
  ) {
    peripherals[peripheral.identifier] = peripheral
    let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
    let generation: DeviceGeneration? =
      services.contains(Self.service4)
      ? .whoop4 : (services.contains(Self.service5) ? .whoop5 : nil)
    if !discovered.contains(where: { $0.id == peripheral.identifier }) {
      discovered.append(
        Discovery(
          id: peripheral.identifier, name: peripheral.name ?? "Unnamed heart-rate device",
          generation: generation))
    }
    // RSSI is deliberately not a wear signal.
  }
  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    guard let id = mapping[peripheral.identifier] else {
      central.cancelPeripheralConnection(peripheral)
      return
    }
    connected.insert(id)
    onConnectionChange?()
    peripheral.delegate = self
    central.stopScan()
    status = "Connected; discovering heart-rate service"
    peripheral.discoverServices([
      CBUUID(string: "180D"), CBUUID(string: "180A"), Self.service4, Self.service5,
    ])
  }
  func centralManager(
    _ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?
  ) { status = "Connection failed. Check pairing mode and competing connections." }
  func centralManager(
    _ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?
  ) {
    if let id = mapping[peripheral.identifier] {
      connected.remove(id)
      onConnectionChange?()
      if target == id && central.state == .poweredOn { central.connect(peripheral) }
    }
    status =
      "Connection interrupted; waiting to reconnect. History catch-up is not yet hardware validated."
  }
  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    guard error == nil else {
      status = "Service discovery failed"
      return
    }
    for s in peripheral.services ?? [] {
      if s.uuid == CBUUID(string: "180D") {
        peripheral.discoverCharacteristics([CBUUID(string: "2A37")], for: s)
      } else if s.uuid == CBUUID(string: "180A") {
        peripheral.discoverCharacteristics(
          [CBUUID(string: "2A26"), CBUUID(string: "2A25"), CBUUID(string: "2A24")], for: s)
      }
    }
  }
  func peripheral(
    _ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?
  ) {
    guard error == nil else {
      status = "Characteristic discovery failed"
      return
    }
    for c in service.characteristics ?? [] {
      if c.uuid == CBUUID(string: "2A37") && c.properties.contains(.notify) {
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
    status =
      error == nil
      ? "Listening for live heart rate"
      : "Band refused notifications. Enable HR broadcast if supported."
  }
  func peripheral(
    _ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?
  ) {
    guard error == nil, let data = characteristic.value, let id = mapping[peripheral.identifier]
    else { return }
    if characteristic.uuid == CBUUID(string: "2A37") {
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
