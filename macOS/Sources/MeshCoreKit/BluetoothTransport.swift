import Foundation
import CoreBluetooth
import Combine

public struct BLEDevice: Identifiable {
    public let id: UUID
    public let name: String
    public let rssi: Int
}

@MainActor public final class BluetoothTransport: NSObject, ObservableObject, MeshTransport, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    @Published public private(set) var devices: [BLEDevice] = []
    @Published public private(set) var state = "Bluetooth se připravuje…"
    @Published public private(set) var ready = false
    @Published public private(set) var scanning = false
    @Published public private(set) var connecting = false
    @Published public private(set) var connectedName = "Žádný companion"
    @Published public private(set) var retryDate: Date?
    public var connectedIdentifier: UUID? { peripheral?.identifier }
    public var automaticReconnect = true { didSet {
        policy.enabled = automaticReconnect
        if !automaticReconnect { let wasRetrying = retryDate != nil; cancelRetry(); if wasRetrying { state = "Automatické obnovení je vypnuté." } }
        else if !ready && !connecting { scheduleRetry() }
    } }
    private var policy = ReconnectPolicy()
    private var retryTask: Task<Void,Never>?
    private var sleeping = false
    private var retiring: [UUID:CBPeripheral] = [:]
    public var onFrame: ((Data) -> Void)?
    public var onDisconnect: (() -> Void)?
    public var onReady: (() -> Void)?
    private var central: CBCentralManager!
    private var found: [UUID: CBPeripheral] = [:]
    private var peripheral: CBPeripheral?
    private var rx: CBCharacteristic?
    private var tx: CBCharacteristic?
    private var writeCompletion: CheckedContinuation<Void, Error>?
    private var connectTimer: Task<Void,Never>?
    private var writeTimer: Task<Void,Never>?
    private var lastID: UUID?
    private var failureReason: String?
    public override convenience init() { self.init(startImmediately:true) }
    public init(startImmediately: Bool) {
        super.init()
        if startImmediately { central = CBCentralManager(delegate:self, queue:.main) }
        else { state = "Izolovaný náhled · Bluetooth je vypnutý" }
    }
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: state = "Bluetooth je připraven. Spusťte skenování."; scheduleRetry()
        case .poweredOff: state = "Bluetooth je vypnutý. Zapněte jej v Nastavení systému."
        case .unauthorized: state = "Chybí oprávnění Bluetooth. Povolte aplikaci v Nastavení systému → Soukromí a zabezpečení → Bluetooth."
        case .unsupported: state = "Tento Mac nepodporuje BLE."
        default: state = "Bluetooth není dostupný; vyčkejte."
        }
        if central.state != .poweredOn { cancelRetry(); retiring.removeAll(); clean() }
    }
    public func scan() {
        guard let central else { return }
        guard central.state == .poweredOn else { centralManagerDidUpdateState(central); return }
        policy.userDisconnect(); cancelRetry()
        devices.removeAll(); found.removeAll(); scanning = true
        central.scanForPeripherals(withServices:[CBUUID(string:MeshCodec.serviceUUID)], options:[CBCentralManagerScanOptionAllowDuplicatesKey:true])
        state = "Hledám companiony. Pokud vaše zařízení chybí, odpojte jej v telefonu."
    }
    public func stopScan() { central?.stopScan(); scanning = false }
    public func connect(_ id: UUID) {
        policy.userConnect(); cancelRetry(); lastID = id; beginConnect(id)
    }
    private func beginConnect(_ id: UUID) {
        guard let central else { return }
        guard central.state == .poweredOn, peripheral == nil, !sleeping else { return }
        guard retiring[id] == nil else { scheduleRetry(); return }
        guard let p = found[id] ?? central.retrievePeripherals(withIdentifiers:[id]).first else { state = "Zařízení není dostupné. Spusťte skenování."; scheduleRetry(); return }
        stopScan(); connecting = true; failureReason = nil; lastID = id; peripheral = p; p.delegate = self
        connectedName = p.name ?? "Companion"; state = "Připojuji \(connectedName). Případný PIN zadejte do systémového dialogu macOS."
        central.connect(p, options:nil)
        connectTimer?.cancel(); connectTimer = Task { [weak self] in
            do { try await Task.sleep(nanoseconds:60_000_000_000) } catch { return }
            guard let self, !self.ready else { return }
            self.failureReason = "Připojení vypršelo. Odpojte telefon, ověřte PIN a BLE oprávnění; zkuste znovu."
            self.state = self.failureReason ?? "Připojení vypršelo."
            self.drop(self.failureReason ?? "Připojení vypršelo.",retry:true)
        }
    }
    public func reconnect() { if let id = lastID { connect(id) } else { scan() } }
    public func disconnect() {
        policy.userDisconnect(); cancelRetry(); stopScan(); drop("Odpojeno ručně",retry:false)
    }
    public func prepareForSleep() { sleeping = true; cancelRetry() }
    public func resumeAfterWake() { sleeping = false; if !ready && !connecting { scheduleRetry() } }
    private func cancelRetry() { retryTask?.cancel(); retryTask = nil; retryDate = nil }
    private func scheduleRetry() {
        guard retryTask == nil, peripheral == nil, let central, let id = lastID,
              let delay = policy.nextDelay(poweredOn:central.state == .poweredOn,sleeping:sleeping) else { return }
        retryDate = Date().addingTimeInterval(delay)
        state = "Obnovím BLE za \(Int(delay)) s · pokus \(policy.attempt). Pro zrušení použijte Odpojit."
        retryTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds:UInt64(delay*1e9)) } catch { return }
            guard let self else { return }; self.retryTask = nil; self.retryDate = nil
            guard self.policy.enabled, self.policy.wanted else { return }; self.beginConnect(id)
        }
    }
    private func drop(_ message: String,retry: Bool) {
        if let p = peripheral, p.state != .disconnected { retiring[p.identifier] = p; central?.cancelPeripheralConnection(p) }
        clean(); state = message
        if retry { scheduleRetry() }
    }
    private func clean() {
        let hadConnection = peripheral != nil || ready || connecting || writeCompletion != nil
        ready = false; scanning = false; connecting = false; rx = nil; tx = nil; peripheral?.delegate = nil; peripheral = nil
        connectTimer?.cancel(); connectTimer = nil; writeTimer?.cancel(); writeTimer = nil
        writeCompletion?.resume(throwing:MeshError.disconnected); writeCompletion = nil; if hadConnection { onDisconnect?() }
    }
    public func centralManager(_ central: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String:Any], rssi RSSI: NSNumber) {
        found[p.identifier] = p
        let d = BLEDevice(id:p.identifier, name:advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? p.name ?? "MeshCore companion", rssi:RSSI.intValue)
        if let i = devices.firstIndex(where: { $0.id == d.id }) { devices[i] = d } else { devices.append(d) }
    }
    public func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
        guard p === peripheral else { return }
 state = "Zjišťuji BLE službu a zabezpečení…"; p.discoverServices([CBUUID(string:MeshCodec.serviceUUID)]) }
    public func centralManager(_ central: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        if retiring.removeValue(forKey:p.identifier) != nil { return }
        guard p === peripheral else { return }
        if let error = error as NSError?, error.domain == CBErrorDomain, error.code == CBError.Code.peerRemovedPairingInformation.rawValue { fail("Zařízení zrušilo párování. Odstraňte starý bond v Nastavení Bluetooth a připojte je ručně."); return }
        clean(); state = "Připojení selhalo. \(error?.localizedDescription ?? "Zařízení může být obsazené telefonem.")"; scheduleRetry()
    }
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        if retiring.removeValue(forKey:p.identifier) != nil { return }
        guard p === peripheral else { return }
        let failure = failureReason
        clean(); if central.state == .poweredOn { state = failure ?? "Spojení ukončeno. \(error?.localizedDescription ?? "")"; scheduleRetry() }
    }
    public func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard p === peripheral else { return }

        guard error == nil, let service = p.services?.first(where: { $0.uuid == CBUUID(string:MeshCodec.serviceUUID) }) else { fail(error?.localizedDescription ?? "Chybí MeshCore UART služba."); return }
        p.discoverCharacteristics([CBUUID(string:MeshCodec.rxUUID),CBUUID(string:MeshCodec.txUUID)], for:service)
    }
    public func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard p === peripheral else { return }

        guard error == nil else { fail(error!.localizedDescription); return }
        rx = service.characteristics?.first { $0.uuid == CBUUID(string:MeshCodec.rxUUID) }
        tx = service.characteristics?.first { $0.uuid == CBUUID(string:MeshCodec.txUUID) }
        guard let tx, let rx, rx.properties.contains(.write), tx.properties.contains(.notify) else { fail("Chybí zapisovací nebo notifikační charakteristika."); return }
        p.setNotifyValue(true, for:tx) // encrypted access triggers macOS pairing, never a custom PIN form
    }
    public func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard p === peripheral else { return }

        guard characteristic.uuid == CBUUID(string:MeshCodec.txUUID) else { return }
        guard error == nil, characteristic.isNotifying else { fail("Párování nebo notifikace selhaly. \(error?.localizedDescription ?? "") Zkontrolujte PIN; starý bond lze odstranit v Nastavení Bluetooth."); return }
        connectTimer?.cancel(); cancelRetry(); policy.connected(); connecting = false; ready = true; state = "BLE připojeno k \(connectedName)"; onReady?()
    }
    public func peripheral(_ p: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard p === peripheral else { return }

        guard characteristic.uuid == CBUUID(string:MeshCodec.txUUID), error == nil, let d = characteristic.value else { return }; onFrame?(d)
    }
    private func fail(_ message: String) { failureReason = message; policy.userDisconnect(); cancelRetry(); drop(message,retry:false) }
    public func write(_ frame: Data) async throws {
        guard ready, let p = peripheral, let rx else { throw MeshError.disconnected }
        guard writeCompletion == nil else { throw MeshError.busy }
        let d = try MeshCodec.bleFrame(frame, maximumWriteLength:p.maximumWriteValueLength(for:.withResponse))
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void,Error>) in
            writeCompletion = c
            writeTimer = Task { [weak self] in
                do { try await Task.sleep(nanoseconds:8_000_000_000) } catch { return }
                self?.drop("BLE zápis vypršel; obnovuji spojení bez opakování příkazu.",retry:true)
            }
            p.writeValue(d, for:rx, type:.withResponse)
        }
    }
    public func peripheral(_ p: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard p === peripheral else { return }

        writeTimer?.cancel(); writeTimer = nil
        let c = writeCompletion; writeCompletion = nil
        if let error { c?.resume(throwing:error) } else { c?.resume() }
    }
}
