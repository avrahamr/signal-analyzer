import Foundation

/// One 802.11 information element (tag, length, payload). Element ID 255 is
/// the "extension" element whose first payload byte selects the real type.
struct InformationElement: Hashable, Sendable {
    let id: UInt8
    let extensionID: UInt8?
    let payload: Data

    var name: String {
        if let ext = extensionID { return InformationElement.extensionNames[ext] ?? "Extension \(ext)" }
        return InformationElement.names[id] ?? "Element \(id)"
    }

    var hexPayload: String {
        payload.map { String(format: "%02x", $0) }.joined(separator: " ")
    }

    static let names: [UInt8: String] = [
        0: "SSID", 1: "Supported Rates", 3: "DS Parameter Set", 5: "TIM", 7: "Country",
        11: "BSS Load", 32: "Power Constraint", 35: "TPC Report", 42: "ERP",
        45: "HT Capabilities", 48: "RSN", 50: "Extended Supported Rates",
        54: "Mobility Domain", 61: "HT Operation", 70: "RM Enabled Capabilities",
        74: "Overlapping BSS Scan", 107: "Interworking", 127: "Extended Capabilities",
        191: "VHT Capabilities", 192: "VHT Operation", 195: "Tx Power Envelope",
        201: "Reduced Neighbor Report", 221: "Vendor Specific", 255: "Extension",
    ]

    static let extensionNames: [UInt8: String] = [
        35: "HE Capabilities", 36: "HE Operation", 59: "HE 6 GHz Band Capabilities",
        106: "EHT Operation", 108: "EHT Capabilities", 107: "Multi-Link",
    ]

    /// Splits a beacon's tagged-parameter blob into elements. Stops at the
    /// first malformed length rather than throwing.
    static func parse(_ data: Data) -> [InformationElement] {
        var elements: [InformationElement] = []
        var index = data.startIndex
        while index + 2 <= data.endIndex {
            let id = data[index]
            let length = Int(data[index + 1])
            let start = index + 2
            let end = start + length
            guard end <= data.endIndex else { break }
            let payload = data[start..<end]
            if id == 255, let ext = payload.first {
                elements.append(InformationElement(id: id, extensionID: ext, payload: Data(payload.dropFirst())))
            } else {
                elements.append(InformationElement(id: id, extensionID: nil, payload: Data(payload)))
            }
            index = end
        }
        return elements
    }
}

/// Decoded RSN (WPA2/WPA3) or legacy WPA information.
struct RSNInfo: Hashable, Sendable {
    var version: Int
    var groupCipher: String
    var pairwiseCiphers: [String]
    var authenticationSuites: [String]
    var managementFrameProtectionCapable: Bool
    var managementFrameProtectionRequired: Bool

    var managementFrameProtection: String {
        if managementFrameProtectionRequired { return "Required" }
        if managementFrameProtectionCapable { return "Optional" }
        return "Off"
    }
}

/// Everything we can infer about an access point from its beacon.
struct NetworkCapabilities: Hashable, Sendable {
    var elements: [InformationElement] = []
    var standards: [String] = []
    var generation: String = "Legacy"
    var maxSpatialStreams: Int?
    var supportedRatesMbps: [Double] = []
    var stationCount: Int?
    var channelUtilizationPercent: Int?
    var dtimPeriod: Int?
    var countryCode: String?
    var supportsWPS = false
    var supportsWMM = false
    var fastRoaming80211r = false
    var radioMeasurement80211k = false
    var bssTransition80211v = false
    var rsn: RSNInfo?
    var legacyWPA: RSNInfo?
    var vendors: [String] = []

    var maxSupportedRateMbps: Double? { supportedRatesMbps.max() }

    var roamingSummary: String {
        var parts: [String] = []
        if radioMeasurement80211k { parts.append("k") }
        if bssTransition80211v { parts.append("v") }
        if fastRoaming80211r { parts.append("r") }
        return parts.isEmpty ? "None advertised" : "802.11" + parts.joined(separator: "/")
    }

    init() {}

    init(informationElements data: Data, band: WiFiNetwork.Band) {
        elements = InformationElement.parse(data)
        var vendorSet: [String] = []

        for element in elements {
            switch (element.id, element.extensionID) {
            case (1, _), (50, _):
                supportedRatesMbps += element.payload.compactMap { byte -> Double? in
                    let rate = byte & 0x7F
                    // 0x7F (127) is a BSS membership selector, not a rate.
                    return rate == 127 ? nil : Double(rate) * 0.5
                }
            case (5, _):
                if element.payload.count >= 2 { dtimPeriod = Int(element.payload[element.payload.startIndex + 1]) }
            case (7, _):
                if element.payload.count >= 2 {
                    countryCode = String(bytes: element.payload.prefix(2), encoding: .ascii)?
                        .trimmingCharacters(in: .whitespaces)
                }
            case (11, _):
                if element.payload.count >= 3 {
                    let p = element.payload
                    stationCount = Int(p[p.startIndex]) | (Int(p[p.startIndex + 1]) << 8)
                    channelUtilizationPercent = Int(p[p.startIndex + 2]) * 100 / 255
                }
            case (45, _):
                standards.append("802.11n")
                maxSpatialStreams = max(maxSpatialStreams ?? 0, Self.htSpatialStreams(element.payload))
            case (48, _):
                rsn = Self.parseRSN(element.payload)
            case (54, _):
                fastRoaming80211r = true
            case (70, _):
                radioMeasurement80211k = true
            case (127, _):
                // Extended Capabilities bit 19 = BSS Transition (802.11v).
                if element.payload.count >= 3 {
                    bssTransition80211v = element.payload[element.payload.startIndex + 2] & 0x08 != 0
                }
            case (191, _):
                standards.append("802.11ac")
                maxSpatialStreams = max(maxSpatialStreams ?? 0, Self.vhtSpatialStreams(element.payload))
            case (221, _):
                let p = element.payload
                guard p.count >= 3 else { break }
                let oui = p.prefix(3).map { String(format: "%02X", $0) }.joined(separator: ":")
                if let vendor = Self.vendorOUIs[oui], !vendorSet.contains(vendor) { vendorSet.append(vendor) }
                if oui == "00:50:F2", p.count >= 4 {
                    switch p[p.startIndex + 3] {
                    case 1: legacyWPA = Self.parseRSN(p.dropFirst(4))
                    case 2: supportsWMM = true
                    case 4: supportsWPS = true
                    default: break
                    }
                }
            case (255, 35?):
                standards.append("802.11ax")
                maxSpatialStreams = max(maxSpatialStreams ?? 0, Self.heSpatialStreams(element.payload))
            case (255, 108?):
                standards.append("802.11be")
            default:
                break
            }
        }

        if standards.isEmpty {
            switch band {
            case .ghz2:
                let onlyDSSS = supportedRatesMbps.allSatisfy { [1, 2, 5.5, 11].contains($0) }
                standards = [onlyDSSS && !supportedRatesMbps.isEmpty ? "802.11b" : "802.11g"]
            case .ghz5: standards = ["802.11a"]
            default: break
            }
        }

        vendors = vendorSet
        generation = Self.generationLabel(standards: standards, band: band)
        supportedRatesMbps = Array(Set(supportedRatesMbps)).sorted()
        if maxSpatialStreams == 0 { maxSpatialStreams = nil }
    }

    // MARK: - Decoding helpers

    static func generationLabel(standards: [String], band: WiFiNetwork.Band) -> String {
        if standards.contains("802.11be") { return "Wi-Fi 7 (802.11be)" }
        if standards.contains("802.11ax") { return band == .ghz6 ? "Wi-Fi 6E (802.11ax)" : "Wi-Fi 6 (802.11ax)" }
        if standards.contains("802.11ac") { return "Wi-Fi 5 (802.11ac)" }
        if standards.contains("802.11n") { return "Wi-Fi 4 (802.11n)" }
        if let first = standards.first { return "Legacy (\(first))" }
        return "Legacy"
    }

    /// HT Capabilities: 2 bytes info, 1 byte A-MPDU, then a 16-byte MCS set
    /// whose first four bytes are one bitmask byte per spatial stream.
    static func htSpatialStreams(_ payload: Data) -> Int {
        guard payload.count >= 7 else { return 0 }
        let mcs = payload.dropFirst(3).prefix(4)
        return mcs.filter { $0 != 0 }.count
    }

    /// VHT Capabilities: 4 bytes info, then Rx MCS map (2 bytes, 2 bits per
    /// stream, value 3 = unsupported).
    static func vhtSpatialStreams(_ payload: Data) -> Int {
        guard payload.count >= 6 else { return 0 }
        let p = payload
        let map = Int(p[p.startIndex + 4]) | (Int(p[p.startIndex + 5]) << 8)
        return streams(inMCSMap: map)
    }

    /// HE Capabilities: 6 bytes MAC caps, 11 bytes PHY caps, then Rx MCS map
    /// for ≤80 MHz (2 bytes, same encoding as VHT).
    static func heSpatialStreams(_ payload: Data) -> Int {
        guard payload.count >= 19 else { return 0 }
        let p = payload
        let map = Int(p[p.startIndex + 17]) | (Int(p[p.startIndex + 18]) << 8)
        return streams(inMCSMap: map)
    }

    private static func streams(inMCSMap map: Int) -> Int {
        var count = 0
        for stream in 0..<8 where (map >> (stream * 2)) & 0x3 != 3 { count += 1 }
        return count
    }

    /// RSN/WPA body: version(2) group(4) pairwise-count(2) pairwise(4×n)
    /// akm-count(2) akm(4×n) capabilities(2).
    static func parseRSN(_ body: Data) -> RSNInfo? {
        let bytes = [UInt8](body)
        guard bytes.count >= 8 else { return nil }
        var i = 0
        func u16() -> Int? {
            guard i + 2 <= bytes.count else { return nil }
            defer { i += 2 }
            return Int(bytes[i]) | (Int(bytes[i + 1]) << 8)
        }
        func suite() -> UInt8? {
            guard i + 4 <= bytes.count else { return nil }
            defer { i += 4 }
            return bytes[i + 3]
        }

        guard let version = u16(), let group = suite() else { return nil }
        var info = RSNInfo(
            version: version,
            groupCipher: cipherName(group),
            pairwiseCiphers: [],
            authenticationSuites: [],
            managementFrameProtectionCapable: false,
            managementFrameProtectionRequired: false
        )
        if let pairwiseCount = u16() {
            for _ in 0..<min(pairwiseCount, 8) {
                if let s = suite() { info.pairwiseCiphers.append(cipherName(s)) }
            }
        }
        if let akmCount = u16() {
            for _ in 0..<min(akmCount, 8) {
                if let s = suite() { info.authenticationSuites.append(akmName(s)) }
            }
        }
        if let caps = u16() {
            info.managementFrameProtectionRequired = caps & 0x40 != 0
            info.managementFrameProtectionCapable = caps & 0x80 != 0
        }
        return info
    }

    static func cipherName(_ type: UInt8) -> String {
        switch type {
        case 0: return "Group"
        case 1: return "WEP-40"
        case 2: return "TKIP"
        case 4: return "CCMP-128 (AES)"
        case 5: return "WEP-104"
        case 6: return "BIP-CMAC-128"
        case 8: return "GCMP-128"
        case 9: return "GCMP-256"
        case 10: return "CCMP-256"
        default: return "Cipher \(type)"
        }
    }

    static func akmName(_ type: UInt8) -> String {
        switch type {
        case 1: return "802.1X (EAP)"
        case 2: return "PSK"
        case 3: return "FT-802.1X"
        case 4: return "FT-PSK"
        case 5: return "802.1X-SHA256"
        case 6: return "PSK-SHA256"
        case 8: return "SAE (WPA3)"
        case 9: return "FT-SAE"
        case 11: return "Suite-B"
        case 12: return "Suite-B-192"
        case 13: return "FT-802.1X-SHA384"
        case 18: return "OWE"
        default: return "AKM \(type)"
        }
    }

    /// Vendor-specific element OUIs that hint at the AP's maker or chipset.
    static let vendorOUIs: [String: String] = [
        "00:50:F2": "Microsoft (WPA/WMM/WPS)",
        "00:17:F2": "Apple",
        "50:6F:9A": "Wi-Fi Alliance",
        "00:10:18": "Broadcom",
        "00:03:7F": "Atheros",
        "8C:FD:F0": "Qualcomm",
        "00:0C:43": "Ralink / MediaTek",
        "00:0C:E7": "MediaTek",
        "00:E0:4C": "Realtek",
        "00:40:96": "Cisco",
        "00:0B:86": "Aruba",
        "00:26:86": "Quantenna",
        "F4:F5:E8": "Google",
        "00:1C:E1": "Ubiquiti",
        "18:E8:29": "Ubiquiti",
    ]
}
