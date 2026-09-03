import Foundation

/// Snapshot of one access point seen during a scan. Plain value type so it can
/// cross from the scanning thread to the main actor.
struct WiFiNetwork: Identifiable, Hashable, Sendable {
    enum Band: String, Hashable, Sendable, CaseIterable {
        case ghz2 = "2.4 GHz"
        case ghz5 = "5 GHz"
        case ghz6 = "6 GHz"
        case unknown = "—"
    }

    let id: String
    let ssid: String?
    let bssid: String?
    /// Received signal strength in dBm (typically -30 strong … -90 weak).
    let rssi: Int
    /// Noise floor in dBm.
    let noise: Int
    let channel: Int
    let band: Band
    let widthMHz: Int
    /// Most specific security mode, e.g. "WPA3".
    let security: String
    /// Every security mode the AP advertises.
    let securities: [String]
    let isConnected: Bool
    let countryCode: String?
    let beaconIntervalMs: Int
    let isAdHoc: Bool
    /// Raw 802.11 information elements from the beacon; parsed lazily by `NetworkCapabilities`.
    let informationElements: Data?

    var displayName: String {
        if let ssid, !ssid.isEmpty { return ssid }
        return "Hidden network"
    }

    var isHidden: Bool { ssid?.isEmpty ?? true }

    /// Signal-to-noise ratio in dB.
    var snr: Int { rssi - noise }

    /// 0–4 bars.
    var bars: Int { signalBars(forRSSI: rssi) }

    /// Linear 0–100 % between -100 dBm and -50 dBm, the scale most Wi-Fi tools use.
    var qualityPercent: Int { min(100, max(0, 2 * (rssi + 100))) }

    /// Label that stays distinct for mesh nodes sharing one SSID.
    var chartLabel: String { "\(displayName) · ch \(channel)" }

    var centerFrequencyMHz: Int? { band.frequencyMHz(forChannel: channel) }

    /// Approximate occupied spectrum. The primary channel is used as the
    /// centre, which is exact for 20 MHz and approximate for wider channels.
    var frequencyRangeMHz: ClosedRange<Int>? {
        guard let center = centerFrequencyMHz else { return nil }
        let width = widthMHz > 0 ? widthMHz : 20
        return (center - width / 2)...(center + width / 2)
    }

    /// Log-distance path-loss estimate. Rough by nature: walls, antennas and
    /// transmit power vary, so treat this as an order of magnitude.
    func estimatedDistanceMeters(referenceRSSIAt1m: Int, pathLossExponent: Double) -> Double {
        let reference = Double(referenceRSSIAt1m + band.referenceOffsetDB)
        let exponent = max(pathLossExponent, 1.0)
        return pow(10, (reference - Double(rssi)) / (10 * exponent))
    }
}

extension WiFiNetwork.Band {
    /// Centre frequency in MHz for a channel number in this band.
    func frequencyMHz(forChannel channel: Int) -> Int? {
        guard channel > 0 else { return nil }
        switch self {
        case .ghz2: return channel == 14 ? 2484 : 2407 + 5 * channel
        case .ghz5: return 5000 + 5 * channel
        case .ghz6: return 5950 + 5 * channel
        case .unknown: return nil
        }
    }

    func channel(forFrequencyMHz frequency: Int) -> Int? {
        switch self {
        case .ghz2: return frequency == 2484 ? 14 : (frequency - 2407) / 5
        case .ghz5: return (frequency - 5000) / 5
        case .ghz6: return (frequency - 5950) / 5
        case .unknown: return nil
        }
    }

    /// Plot range for the spectrum chart.
    var frequencyDomain: ClosedRange<Int> {
        switch self {
        case .ghz2: return 2400...2495
        case .ghz5: return 5150...5850
        case .ghz6: return 5925...7125
        case .unknown: return 0...1
        }
    }

    /// Channels labelled on the spectrum chart's X axis.
    var axisChannels: [Int] {
        switch self {
        case .ghz2: return [1, 3, 5, 7, 9, 11, 13]
        case .ghz5: return [36, 44, 52, 60, 100, 108, 116, 124, 132, 140, 149, 157, 165]
        case .ghz6: return [1, 33, 65, 97, 129, 161, 193, 225]
        case .unknown: return []
        }
    }

    /// Higher bands attenuate faster; shift the 1 m reference accordingly.
    var referenceOffsetDB: Int {
        switch self {
        case .ghz2, .unknown: return 0
        case .ghz5: return -6
        case .ghz6: return -8
        }
    }

    var plottable: [WiFiNetwork.Band] { [.ghz2, .ghz5, .ghz6] }
}

struct RSSISample: Hashable, Sendable {
    let date: Date
    let rssi: Int
}

struct HistorySeries: Identifiable {
    let id: String
    let label: String
    let samples: [RSSISample]
}

/// How often and when a network has been seen across scans.
struct Presence: Sendable {
    var firstSeen: Date
    var lastSeen: Date
    var scanCount: Int
}
