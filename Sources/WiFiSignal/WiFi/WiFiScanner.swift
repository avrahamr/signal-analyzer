import CoreWLAN
import Darwin
import Foundation
import SystemConfiguration

/// CWNetwork objects are needed later to join a network, but they are not
/// Sendable. They are immutable snapshots, so hopping threads is safe.
final class RawNetworkBox: @unchecked Sendable {
    let byID: [String: CWNetwork]
    init(_ byID: [String: CWNetwork]) { self.byID = byID }
}

/// Live state of the Mac's own Wi-Fi interface.
struct InterfaceStatus: Sendable {
    let name: String
    let hardwareAddress: String?
    let powerOn: Bool
    let ssid: String?
    let bssid: String?
    let rssi: Int
    let noise: Int
    let transmitRateMbps: Double
    let phyMode: String
    let transmitPowerMw: Int
    let channel: Int
    let band: WiFiNetwork.Band
    let widthMHz: Int
    let security: String
    let countryCode: String?
    let ipv4Address: String?
    let router: String?
    let dnsServers: [String]
}

struct ScanSnapshot: Sendable {
    let networks: [WiFiNetwork]
    let interfaceStatus: InterfaceStatus
    let timestamp: Date
    let raw: RawNetworkBox
}

enum ScanError: LocalizedError {
    case noWiFiInterface
    case scanFailed(String)
    case networkGone
    case joinFailed(String)

    var errorDescription: String? {
        switch self {
        case .noWiFiInterface: return "No Wi-Fi interface found on this Mac."
        case .scanFailed(let reason): return "Scan failed: \(reason)"
        case .networkGone: return "That network is no longer in range. Rescan and try again."
        case .joinFailed(let reason): return "Could not join: \(reason)"
        }
    }
}

/// Thin wrapper over CoreWLAN. `scan()` blocks for a few seconds while the
/// radio sweeps channels, so always call it off the main thread.
enum WiFiScanner {
    static func scan() throws -> ScanSnapshot {
        guard let interface = CWWiFiClient.shared().interface() else {
            throw ScanError.noWiFiInterface
        }
        let status = interfaceStatus(interface)

        let found: Set<CWNetwork>
        do {
            found = try interface.scanForNetworks(withSSID: nil)
        } catch {
            throw ScanError.scanFailed(error.localizedDescription)
        }

        var seenIDs = Set<String>()
        var networks: [WiFiNetwork] = []
        var raw: [String: CWNetwork] = [:]
        for network in found.sorted(by: { $0.rssiValue > $1.rssiValue }) {
            // Without Location permission every BSSID is nil, so fall back to
            // SSID@channel and de-duplicate to keep SwiftUI's Table happy.
            let base = network.bssid ?? "\(network.ssid ?? "hidden")@\(network.wlanChannel?.channelNumber ?? 0)"
            var id = base
            var suffix = 1
            while !seenIDs.insert(id).inserted {
                suffix += 1
                id = "\(base)#\(suffix)"
            }
            networks.append(WiFiNetwork(
                network: network,
                id: id,
                connectedBSSID: status.bssid,
                connectedSSID: status.ssid
            ))
            raw[id] = network
        }

        return ScanSnapshot(
            networks: networks,
            interfaceStatus: status,
            timestamp: Date(),
            raw: RawNetworkBox(raw)
        )
    }

    static func join(_ network: CWNetwork, password: String?) throws {
        guard let interface = CWWiFiClient.shared().interface() else { throw ScanError.noWiFiInterface }
        do {
            try interface.associate(to: network, password: password?.isEmpty == true ? nil : password)
        } catch {
            throw ScanError.joinFailed(error.localizedDescription)
        }
    }

    static func disconnect() throws {
        guard let interface = CWWiFiClient.shared().interface() else { throw ScanError.noWiFiInterface }
        interface.disassociate()
    }

    static func interfaceStatus(_ interface: CWInterface) -> InterfaceStatus {
        let name = interface.interfaceName ?? "en0"
        let channel = interface.wlanChannel()
        let (band, width) = Self.bandAndWidth(channel)
        let (router, dns) = Self.globalRouting()
        return InterfaceStatus(
            name: name,
            hardwareAddress: interface.hardwareAddress(),
            powerOn: interface.powerOn(),
            ssid: interface.ssid(),
            bssid: interface.bssid(),
            rssi: interface.rssiValue(),
            noise: interface.noiseMeasurement(),
            transmitRateMbps: interface.transmitRate(),
            phyMode: Self.phyModeName(interface.activePHYMode()),
            transmitPowerMw: interface.transmitPower(),
            channel: channel?.channelNumber ?? 0,
            band: band,
            widthMHz: width,
            security: Self.securityName(interface.security()),
            countryCode: interface.countryCode(),
            ipv4Address: Self.ipv4Address(interfaceName: name),
            router: router,
            dnsServers: dns
        )
    }

    // MARK: - Helpers

    static func bandAndWidth(_ channel: CWChannel?) -> (WiFiNetwork.Band, Int) {
        let band: WiFiNetwork.Band
        switch channel?.channelBand {
        case .band2GHz?: band = .ghz2
        case .band5GHz?: band = .ghz5
        case .band6GHz?: band = .ghz6
        default: band = .unknown
        }
        let width: Int
        switch channel?.channelWidth {
        case .width20MHz?: width = 20
        case .width40MHz?: width = 40
        case .width80MHz?: width = 80
        case .width160MHz?: width = 160
        default: width = 0
        }
        return (band, width)
    }

    static func phyModeName(_ mode: CWPHYMode) -> String {
        switch mode {
        case .modeNone: return "—"
        case .mode11a: return "802.11a"
        case .mode11b: return "802.11b"
        case .mode11g: return "802.11g"
        case .mode11n: return "802.11n (Wi-Fi 4)"
        case .mode11ac: return "802.11ac (Wi-Fi 5)"
        case .mode11ax: return "802.11ax (Wi-Fi 6)"
        @unknown default: return "Newer than 802.11ax"
        }
    }

    /// Ordered most-specific first so the first match is the headline label.
    static let securityCandidates: [(CWSecurity, String)] = [
        (.wpa3Enterprise, "WPA3 Enterprise"),
        (.wpa3Personal, "WPA3"),
        (.wpa3Transition, "WPA2/WPA3"),
        (.wpa2Enterprise, "WPA2 Enterprise"),
        (.wpa2Personal, "WPA2"),
        (.wpaEnterpriseMixed, "WPA/WPA2 Enterprise"),
        (.wpaPersonalMixed, "WPA/WPA2"),
        (.wpaEnterprise, "WPA Enterprise"),
        (.wpaPersonal, "WPA"),
        (.enterprise, "Enterprise"),
        (.personal, "Personal"),
        (.OWE, "OWE (Enhanced Open)"),
        (.oweTransition, "OWE Transition"),
        (.dynamicWEP, "Dynamic WEP"),
        (.WEP, "WEP"),
        (CWSecurity.none, "Open"),
    ]

    static func securityName(_ security: CWSecurity) -> String {
        securityCandidates.first { $0.0 == security }?.1 ?? "Unknown"
    }

    static func ipv4Address(interfaceName: String) -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard let address = entry.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET),
                  String(cString: entry.ifa_name) == interfaceName else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                return String(cString: host)
            }
        }
        return nil
    }

    static func globalRouting() -> (router: String?, dns: [String]) {
        guard let store = SCDynamicStoreCreate(nil, "WiFiSignal" as CFString, nil, nil) else { return (nil, []) }
        let ipv4 = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
        let dns = SCDynamicStoreCopyValue(store, "State:/Network/Global/DNS" as CFString) as? [String: Any]
        return (ipv4?["Router"] as? String, dns?["ServerAddresses"] as? [String] ?? [])
    }
}

extension WiFiNetwork {
    init(network n: CWNetwork, id: String, connectedBSSID: String?, connectedSSID: String?) {
        let (band, width) = WiFiScanner.bandAndWidth(n.wlanChannel)

        let connected: Bool
        if let bssid = n.bssid, let connectedBSSID {
            connected = bssid.caseInsensitiveCompare(connectedBSSID) == .orderedSame
        } else if let ssid = n.ssid, let connectedSSID {
            connected = ssid == connectedSSID
        } else {
            connected = false
        }

        let securities = WiFiScanner.securityCandidates
            .filter { n.supportsSecurity($0.0) }
            .map { $0.1 }

        self.init(
            id: id,
            ssid: n.ssid,
            bssid: n.bssid,
            rssi: n.rssiValue,
            noise: n.noiseMeasurement,
            channel: n.wlanChannel?.channelNumber ?? 0,
            band: band,
            widthMHz: width,
            security: securities.first ?? "Unknown",
            securities: securities,
            isConnected: connected,
            countryCode: n.countryCode,
            beaconIntervalMs: n.beaconInterval,
            isAdHoc: n.ibss,
            informationElements: n.informationElementData
        )
    }
}
