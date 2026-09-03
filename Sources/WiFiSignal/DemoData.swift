import Foundation

/// Fictional networks and devices for screenshots and UI work without
/// exposing anyone's real environment. Enabled with the `--demo` launch
/// argument; `--render-screenshots <dir>` writes PNGs and exits.
enum DemoData {
    static let isEnabled = CommandLine.arguments.contains("--demo")
        || CommandLine.arguments.contains("--render-screenshots")

    private struct Seed {
        let ssid: String?
        let bssid: String
        let rssi: Int
        let channel: Int
        let band: WiFiNetwork.Band
        let width: Int
        let security: String
        var connected = false
    }

    private static let seeds: [Seed] = [
        Seed(ssid: "Lighthouse", bssid: "02:1A:7B:3C:44:10", rssi: -41, channel: 149, band: .ghz5, width: 80, security: "WPA3", connected: true),
        Seed(ssid: nil, bssid: "02:1A:7B:3C:44:11", rssi: -42, channel: 149, band: .ghz5, width: 80, security: "WPA2"),
        Seed(ssid: "Blue Harbor Cafe", bssid: "02:5E:90:12:AB:01", rssi: -48, channel: 36, band: .ghz5, width: 80, security: "Open"),
        Seed(ssid: "Maple-Street-5G", bssid: "02:77:C2:0D:5F:20", rssi: -62, channel: 40, band: .ghz5, width: 80, security: "WPA2"),
        Seed(ssid: "Printer-DIRECT-9A", bssid: "02:33:4B:9A:9A:9A", rssi: -66, channel: 44, band: .ghz5, width: 20, security: "WPA2"),
        Seed(ssid: "Northwind", bssid: "02:AC:11:64:00:7E", rssi: -71, channel: 52, band: .ghz5, width: 80, security: "WPA2/WPA3"),
        Seed(ssid: "Orchard Guest", bssid: "02:D0:2F:8E:13:55", rssi: -83, channel: 100, band: .ghz5, width: 80, security: "Open"),
        Seed(ssid: nil, bssid: "02:D0:2F:8E:13:56", rssi: -85, channel: 100, band: .ghz5, width: 80, security: "WPA2"),
        Seed(ssid: "Lighthouse", bssid: "02:1A:7B:3C:44:12", rssi: -45, channel: 11, band: .ghz2, width: 20, security: "WPA3"),
        Seed(ssid: "Blue Harbor Cafe", bssid: "02:5E:90:12:AB:02", rssi: -55, channel: 1, band: .ghz2, width: 20, security: "Open"),
        Seed(ssid: "Maple-Street", bssid: "02:77:C2:0D:5F:21", rssi: -60, channel: 6, band: .ghz2, width: 20, security: "WPA2"),
        Seed(ssid: "SmartPlug-7F3A", bssid: "02:9B:E4:7F:3A:00", rssi: -70, channel: 6, band: .ghz2, width: 20, security: "WPA2"),
        Seed(ssid: "Northwind", bssid: "02:AC:11:64:00:7F", rssi: -74, channel: 11, band: .ghz2, width: 20, security: "WPA2/WPA3"),
        Seed(ssid: "Orchard", bssid: "02:D0:2F:8E:13:57", rssi: -80, channel: 3, band: .ghz2, width: 20, security: "WPA2"),
    ]

    /// Networks with a little per-call RSSI jitter so charts move.
    static func networks(jitter: Bool = true) -> [WiFiNetwork] {
        seeds.map { seed in
            let noise = jitter ? Int.random(in: -2...2) : 0
            return WiFiNetwork(
                id: seed.bssid, ssid: seed.ssid, bssid: seed.bssid, rssi: seed.rssi + noise, noise: -92,
                channel: seed.channel, band: seed.band, widthMHz: seed.width, security: seed.security,
                securities: [seed.security], isConnected: seed.connected, countryCode: "US",
                beaconIntervalMs: 100, isAdHoc: false, informationElements: nil
            )
        }
        .sorted { $0.rssi > $1.rssi }
    }

    static func snapshot() -> ScanSnapshot {
        let status = InterfaceStatus(
            name: "en0", hardwareAddress: "02:00:00:00:00:01", powerOn: true, ssid: "Lighthouse",
            bssid: "02:1A:7B:3C:44:10", rssi: -41, noise: -92, transmitRateMbps: 1201, phyMode: "802.11ax (Wi-Fi 6)",
            transmitPowerMw: 100, channel: 149, band: .ghz5, widthMHz: 80, security: "WPA3", countryCode: "US",
            ipv4Address: "192.168.1.23", router: "192.168.1.1", dnsServers: ["192.168.1.1"]
        )
        return ScanSnapshot(networks: networks(), interfaceStatus: status, timestamp: Date(), raw: RawNetworkBox([:]))
    }

    static func bluetoothDevices() -> [BluetoothDevice] {
        let now = Date()
        func make(_ name: String?, _ rssi: Int, _ manufacturer: String?, _ kind: String?, connectable: Bool = true, seed: UInt8) -> BluetoothDevice {
            let uuid = UUID(uuid: (seed, seed &* 37, 0x22, seed &* 91, 0x44, 0x55, 0x66, seed &* 13, 0x88, 0x99, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, seed))
            return BluetoothDevice(
                id: uuid, name: name, rssi: rssi + Int.random(in: -1...1), manufacturer: manufacturer, kind: kind,
                isConnectable: connectable, serviceCount: name == nil ? 0 : 2, txPower: nil,
                firstSeen: now.addingTimeInterval(-300), lastSeen: now, packetCount: 120
            )
        }
        return [
            make("Kitchen Speaker", -52, "Bose", nil, seed: 0x01),
            make("Fitness Band", -66, "Huami (Amazfit)", nil, seed: 0x02),
            make(nil, -38, "Apple", "Nearby (iPhone / iPad / Mac)", connectable: false, seed: 0x03),
            make("Desk Lamp", -74, "Xiaomi", nil, seed: 0x04),
            make("Car Key", -86, "Texas Instruments", nil, seed: 0x05),
            make(nil, -58, "Apple", "AirPods / accessory pairing", connectable: false, seed: 0x06),
            make(nil, -79, "Google", nil, connectable: false, seed: 0x07),
            make("Thermostat", -70, "Nordic Semiconductor", nil, seed: 0x08),
            make(nil, -91, "Samsung", nil, connectable: false, seed: 0x09),
            make(nil, -63, "Apple", "Find My", connectable: false, seed: 0x0A),
        ]
    }

    /// Ten minutes of drifting history for the strongest networks.
    static func historySeries() -> [HistorySeries] {
        let now = Date()
        return networks(jitter: false).prefix(6).enumerated().map { index, n in
            let samples = (0..<120).map { i -> RSSISample in
                let t = Double(i) / 120
                let drift = sin(t * .pi * Double(2 + index)) * 4 + Double.random(in: -1.5...1.5)
                return RSSISample(date: now.addingTimeInterval(-600 + Double(i) * 5), rssi: n.rssi + Int(drift.rounded()))
            }
            return HistorySeries(id: n.id, label: n.chartLabel, samples: samples)
        }
    }
}
