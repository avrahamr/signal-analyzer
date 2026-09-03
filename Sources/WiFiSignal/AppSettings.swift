import Combine
import Foundation

/// User preferences, persisted to UserDefaults. Shared so the stores and the
/// Settings window see the same instance.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var autoRefresh: Bool { didSet { defaults.set(autoRefresh, forKey: "autoRefresh") } }
    @Published var refreshInterval: Double { didSet { defaults.set(refreshInterval, forKey: "refreshInterval") } }
    @Published var showHiddenNetworks: Bool { didSet { defaults.set(showHiddenNetworks, forKey: "showHiddenNetworks") } }
    /// Number of RSSI samples kept per network for the history chart.
    @Published var historyLimit: Int { didSet { defaults.set(historyLimit, forKey: "historyLimit") } }
    /// Log-distance path-loss exponent: ~2 free space, ~3 typical indoors, ~4 many walls.
    @Published var pathLossExponent: Double { didSet { defaults.set(pathLossExponent, forKey: "pathLossExponent") } }
    /// Expected RSSI in dBm one metre from a 2.4 GHz access point.
    @Published var referenceRSSIAt1m: Int { didSet { defaults.set(referenceRSSIAt1m, forKey: "referenceRSSIAt1m") } }
    /// Bluetooth devices unseen for this long are dropped from the list.
    @Published var bluetoothStaleSeconds: Double { didSet { defaults.set(bluetoothStaleSeconds, forKey: "bluetoothStaleSeconds") } }
    @Published var smoothBluetoothRSSI: Bool { didSet { defaults.set(smoothBluetoothRSSI, forKey: "smoothBluetoothRSSI") } }
    /// Expected RSSI in dBm one metre from a typical BLE advertiser (~0 dBm transmitters).
    @Published var bluetoothReferenceRSSIAt1m: Int { didSet { defaults.set(bluetoothReferenceRSSIAt1m, forKey: "bluetoothReferenceRSSIAt1m") } }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        autoRefresh = defaults.object(forKey: "autoRefresh") as? Bool ?? true
        refreshInterval = defaults.object(forKey: "refreshInterval") as? Double ?? 5
        showHiddenNetworks = defaults.object(forKey: "showHiddenNetworks") as? Bool ?? true
        historyLimit = defaults.object(forKey: "historyLimit") as? Int ?? 240
        pathLossExponent = defaults.object(forKey: "pathLossExponent") as? Double ?? 3.0
        referenceRSSIAt1m = defaults.object(forKey: "referenceRSSIAt1m") as? Int ?? -40
        bluetoothStaleSeconds = defaults.object(forKey: "bluetoothStaleSeconds") as? Double ?? 20
        smoothBluetoothRSSI = defaults.object(forKey: "smoothBluetoothRSSI") as? Bool ?? true
        bluetoothReferenceRSSIAt1m = defaults.object(forKey: "bluetoothReferenceRSSIAt1m") as? Int ?? -59
    }

    func resetToDefaults() {
        autoRefresh = true
        refreshInterval = 5
        showHiddenNetworks = true
        historyLimit = 240
        pathLossExponent = 3.0
        referenceRSSIAt1m = -40
        bluetoothStaleSeconds = 20
        smoothBluetoothRSSI = true
        bluetoothReferenceRSSIAt1m = -59
    }
}
