import Combine
import CoreBluetooth
import Foundation

/// Continuous BLE advertisement scanner. Classic Bluetooth devices only expose
/// RSSI once connected, so this deliberately covers LE only.
@MainActor
final class BluetoothScanner: NSObject, ObservableObject {
    @Published private(set) var devices: [BluetoothDevice] = []
    @Published private(set) var state: CBManagerState = .unknown
    @Published private(set) var authorization: CBManagerAuthorization = .notDetermined
    @Published private(set) var isScanning = false
    /// Smoothed RSSI sampled on every publish tick, per device.
    @Published private(set) var history: [UUID: [RSSISample]] = [:]

    private let settings: AppSettings
    private var central: CBCentralManager?
    private var byID: [UUID: BluetoothDevice] = [:]
    private var publishTimer: Timer?

    init(settings: AppSettings = .shared) {
        self.settings = settings
        super.init()
    }

    /// Human-readable reason results are missing, or nil when scanning is healthy.
    var problemDescription: String? {
        switch authorization {
        case .denied: return "Bluetooth access denied — allow Signal Analyzer under Privacy & Security › Bluetooth."
        case .restricted: return "Bluetooth access is restricted on this Mac."
        default: break
        }
        switch state {
        case .poweredOff: return "Bluetooth is turned off."
        case .unsupported: return "This Mac does not support Bluetooth LE."
        case .unauthorized: return "Bluetooth access denied — allow Signal Analyzer under Privacy & Security › Bluetooth."
        default: return nil
        }
    }

    /// Creating the central manager triggers the system permission prompt, so
    /// this is called when the Bluetooth tab first appears rather than at launch.
    func start() {
        if DemoData.isEnabled {
            state = .poweredOn
            authorization = .allowedAlways
            isScanning = true
            for device in DemoData.bluetoothDevices() { byID[device.id] = device }
            publishTimer?.invalidate()
            publishTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    for device in DemoData.bluetoothDevices() { self.byID[device.id] = device }
                    self.publish()
                }
            }
            publish()
            return
        }
        if central == nil {
            central = CBCentralManager(delegate: self, queue: nil)
        } else {
            startScanIfReady()
        }
        publishTimer?.invalidate()
        publishTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.publish() }
        }
    }

    func stop() {
        central?.stopScan()
        isScanning = false
        publishTimer?.invalidate()
        publishTimer = nil
    }

    private func startScanIfReady() {
        guard let central, central.state == .poweredOn, !central.isScanning else { return }
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        isScanning = true
    }

    /// RSSI history for the strongest `limit` devices currently present.
    func historySeries(limit: Int) -> [HistorySeries] {
        devices.prefix(limit).compactMap { d in
            guard let samples = history[d.id], samples.count > 1 else { return nil }
            return HistorySeries(id: d.id.uuidString, label: "\(d.displayName) · \(d.shortID)", samples: samples)
        }
    }

    private func publish() {
        let now = Date()
        let cutoff = now.addingTimeInterval(-settings.bluetoothStaleSeconds)
        byID = byID.filter { $0.value.lastSeen >= cutoff }
        devices = byID.values.sorted { $0.rssi > $1.rssi }

        let limit = max(settings.historyLimit, 10)
        var updated = history.filter { byID[$0.key] != nil }
        for device in devices {
            var samples = updated[device.id, default: []]
            samples.append(RSSISample(date: now, rssi: device.rssi))
            if samples.count > limit { samples.removeFirst(samples.count - limit) }
            updated[device.id] = samples
        }
        history = updated
    }

    private func record(peripheral: CBPeripheral, advertisement: [String: Any], rssi: Int) {
        // 127 is CoreBluetooth's "RSSI unavailable" sentinel.
        guard rssi != 127 else { return }
        let now = Date()
        let advertisedName = advertisement[CBAdvertisementDataLocalNameKey] as? String
        let manufacturerData = advertisement[CBAdvertisementDataManufacturerDataKey] as? Data
        let decoded: (manufacturer: String?, kind: String?) = manufacturerData.map(BluetoothDecoding.decodeManufacturerData) ?? (nil, nil)
        let services = (advertisement[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?.count ?? 0
        let connectable = (advertisement[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue ?? false
        let txPower = (advertisement[CBAdvertisementDataTxPowerLevelKey] as? NSNumber)?.intValue

        if var existing = byID[peripheral.identifier] {
            existing.rssi = settings.smoothBluetoothRSSI
                ? BluetoothDecoding.smooth(previous: existing.rssi, new: rssi)
                : rssi
            existing.name = peripheral.name ?? advertisedName ?? existing.name
            existing.manufacturer = decoded.manufacturer ?? existing.manufacturer
            existing.kind = decoded.kind ?? existing.kind
            existing.isConnectable = existing.isConnectable || connectable
            existing.serviceCount = max(existing.serviceCount, services)
            existing.txPower = txPower ?? existing.txPower
            existing.lastSeen = now
            existing.packetCount += 1
            byID[peripheral.identifier] = existing
        } else {
            byID[peripheral.identifier] = BluetoothDevice(
                id: peripheral.identifier,
                name: peripheral.name ?? advertisedName,
                rssi: rssi,
                manufacturer: decoded.manufacturer,
                kind: decoded.kind,
                isConnectable: connectable,
                serviceCount: services,
                txPower: txPower,
                firstSeen: now,
                lastSeen: now,
                packetCount: 1
            )
        }
    }
}

extension BluetoothScanner: CBCentralManagerDelegate {
    // The central was created with the main queue, so these callbacks are on the main actor.
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            state = central.state
            authorization = CBManager.authorization
            if central.state == .poweredOn {
                startScanIfReady()
            } else {
                isScanning = false
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        MainActor.assumeIsolated {
            record(peripheral: peripheral, advertisement: advertisementData, rssi: RSSI.intValue)
        }
    }
}
