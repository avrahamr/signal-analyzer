import Foundation

/// One Bluetooth LE advertiser seen nearby.
struct BluetoothDevice: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String?
    /// Smoothed RSSI in dBm.
    var rssi: Int
    var manufacturer: String?
    /// Best-effort description of what the advertisement is for.
    var kind: String?
    var isConnectable: Bool
    var serviceCount: Int
    var txPower: Int?
    var firstSeen: Date
    var lastSeen: Date
    var packetCount: Int

    var displayName: String { name?.isEmpty == false ? name! : "Unnamed device" }
    var bars: Int { signalBars(forRSSI: rssi) }
    var shortID: String { String(id.uuidString.prefix(8)) }

    /// Log-distance path-loss estimate; BLE RSSI is noisy so this is indicative only.
    func estimatedDistanceMeters(referenceRSSIAt1m: Int, pathLossExponent: Double) -> Double {
        pow(10, (Double(referenceRSSIAt1m) - Double(rssi)) / (10 * max(pathLossExponent, 1)))
    }
}

enum BluetoothDecoding {
    /// Bluetooth SIG company identifiers (little-endian in manufacturer data).
    static let companies: [UInt16: String] = [
        0x0002: "Intel", 0x0006: "Microsoft", 0x000A: "Qualcomm", 0x000D: "Texas Instruments",
        0x000F: "Broadcom", 0x004C: "Apple", 0x0059: "Nordic Semiconductor", 0x0075: "Samsung",
        0x0087: "Garmin", 0x009E: "Bose", 0x00E0: "Google", 0x012D: "Sony", 0x0157: "Huami (Amazfit)",
        0x0171: "Amazon", 0x038F: "Xiaomi", 0x046D: "Logitech", 0x01DA: "Logitech", 0x0310: "SGL Italia",
        0x0499: "Ruuvi", 0x0D00: "Unknown (test)",
    ]

    /// Apple Continuity message types, from the first byte after the company ID.
    static let appleKinds: [UInt8: String] = [
        0x02: "iBeacon",
        0x05: "AirDrop",
        0x07: "AirPods / accessory pairing",
        0x09: "AirPlay target",
        0x0A: "AirPlay source",
        0x0B: "Watch / Mac magic switch",
        0x0C: "Handoff",
        0x0D: "Tethering target",
        0x0E: "Tethering source",
        0x0F: "Nearby action",
        0x10: "Nearby (iPhone / iPad / Mac)",
        0x12: "Find My",
    ]

    /// Returns (manufacturer, kind) from a manufacturer-specific data blob.
    static func decodeManufacturerData(_ data: Data) -> (manufacturer: String?, kind: String?) {
        let bytes = [UInt8](data)
        guard bytes.count >= 2 else { return (nil, nil) }
        let company = UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
        let name = companies[company] ?? String(format: "Company 0x%04X", company)
        var kind: String?
        if company == 0x004C, bytes.count >= 3 {
            kind = appleKinds[bytes[2]] ?? String(format: "Apple type 0x%02X", bytes[2])
        }
        return (name, kind)
    }

    /// Exponential moving average so BLE's jittery RSSI is readable.
    static func smooth(previous: Int, new: Int) -> Int {
        Int((Double(previous) * 0.7 + Double(new) * 0.3).rounded())
    }
}
