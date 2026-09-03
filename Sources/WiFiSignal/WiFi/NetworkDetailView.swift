import Charts
import SwiftUI

/// Everything we know about one access point, shown in the inspector.
struct NetworkDetailView: View {
    let networkID: WiFiNetwork.ID?
    @EnvironmentObject private var store: ScanStore
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        if let network = store.network(withID: networkID) {
            NetworkDetailContent(network: network)
                .id(network.id)
        } else if networkID != nil {
            ContentUnavailableView(
                "Out of range",
                systemImage: "wifi.slash",
                description: Text("This network was not seen in the latest scan.")
            )
        } else {
            ContentUnavailableView(
                "Select a network",
                systemImage: "info.circle",
                description: Text("Click a row to see its details.")
            )
        }
    }
}

private struct NetworkDetailContent: View {
    let network: WiFiNetwork
    @EnvironmentObject private var store: ScanStore
    @EnvironmentObject private var settings: AppSettings
    @State private var password = ""
    @State private var confirmDisconnect = false
    @State private var showRawElements = false

    private var capabilities: NetworkCapabilities {
        guard let data = network.informationElements else { return NetworkCapabilities() }
        return NetworkCapabilities(informationElements: data, band: network.band)
    }

    private var isEnterprise: Bool { network.security.localizedCaseInsensitiveContains("Enterprise") }
    private var isOpen: Bool { network.security == "Open" || network.security.hasPrefix("OWE") }

    var body: some View {
        let caps = capabilities
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                DetailSection("Signal") {
                    row("Strength", "\(network.rssi) dBm · \(network.qualityPercent) %")
                    row("Noise floor", "\(network.noise) dBm")
                    row("SNR", "\(network.snr) dB", hint: snrHint)
                    row("Est. distance", distanceText, hint: "Log-distance model, very approximate")
                    if let seen = store.presence[network.id] {
                        row("Seen", "\(seen.scanCount) scans since \(seen.firstSeen.formatted(date: .omitted, time: .shortened))")
                    }
                    if let samples = store.history[network.id], samples.count > 1 {
                        MiniHistoryChart(samples: samples)
                            .frame(height: 90)
                            .padding(.top, 4)
                    }
                }

                DetailSection("Radio") {
                    row("Band / channel", "\(network.band.rawValue) · channel \(network.channel)")
                    if let f = network.centerFrequencyMHz { row("Frequency", "\(f) MHz") }
                    row("Channel width", network.widthMHz > 0 ? "\(network.widthMHz) MHz" : "Unknown")
                    row("Generation", caps.generation)
                    row("Standards", caps.standards.isEmpty ? "—" : caps.standards.joined(separator: ", "))
                    if let streams = caps.maxSpatialStreams { row("Spatial streams", "\(streams)×\(streams) MIMO") }
                    if let rate = caps.maxSupportedRateMbps { row("Legacy rates up to", "\(rate.formatted()) Mbps") }
                    row("Beacon interval", "\(network.beaconIntervalMs) ms" + (caps.dtimPeriod.map { " · DTIM \($0)" } ?? ""))
                    row("Country", network.countryCode ?? caps.countryCode ?? "—")
                    row("Mode", network.isAdHoc ? "Ad-hoc (IBSS)" : "Infrastructure")
                }

                DetailSection("Load & roaming") {
                    row("Connected clients", caps.stationCount.map { "\($0)" } ?? "Not advertised")
                    row("Channel utilisation", caps.channelUtilizationPercent.map { "\($0) %" } ?? "Not advertised")
                    row("Roaming assist", caps.roamingSummary, hint: "k = neighbour reports, v = BSS transition, r = fast transition")
                    row("WMM (QoS)", caps.supportsWMM ? "Yes" : "No")
                }

                DetailSection("Security") {
                    row("Modes", network.securities.isEmpty ? network.security : network.securities.joined(separator: ", "))
                    if let rsn = caps.rsn {
                        row("Pairwise ciphers", rsn.pairwiseCiphers.joined(separator: ", "))
                        row("Group cipher", rsn.groupCipher)
                        row("Authentication", rsn.authenticationSuites.joined(separator: ", "))
                        row("Frame protection", rsn.managementFrameProtection, hint: "802.11w protects against deauth attacks")
                    }
                    if let wpa = caps.legacyWPA {
                        row("Legacy WPA", "\(wpa.pairwiseCiphers.joined(separator: ", ")) · \(wpa.authenticationSuites.joined(separator: ", "))")
                    }
                    row("WPS", caps.supportsWPS ? "Advertised" : "No")
                    if !caps.vendors.isEmpty { row("Vendor elements", caps.vendors.joined(separator: ", ")) }
                }

                if network.isConnected, let status = store.interfaceStatus {
                    DetailSection("Your connection") {
                        row("Interface", "\(status.name) · \(status.hardwareAddress ?? "—")")
                        row("PHY mode", status.phyMode)
                        row("Link rate", "\(status.transmitRateMbps.formatted()) Mbps")
                        row("Transmit power", "\(status.transmitPowerMw) mW")
                        row("IP address", status.ipv4Address ?? "—")
                        row("Router", status.router ?? "—")
                        row("DNS", status.dnsServers.isEmpty ? "—" : status.dnsServers.joined(separator: ", "))
                    }
                }

                DetailSection("Advanced") {
                    advancedActions
                    DisclosureGroup("Raw information elements (\(caps.elements.count))", isExpanded: $showRawElements) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(caps.elements.enumerated()), id: \.offset) { _, element in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(element.name)
                                        .frame(width: 150, alignment: .leading)
                                        .foregroundStyle(.secondary)
                                    Text(element.hexPayload.isEmpty ? "(empty)" : element.hexPayload)
                                        .font(.system(.caption2, design: .monospaced))
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                    .font(.callout)
                }
            }
            .padding(16)
        }
        .confirmationDialog("Disconnect from \(network.displayName)?", isPresented: $confirmDisconnect) {
            Button("Disconnect", role: .destructive) { store.disconnect() }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            SignalBars(level: network.bars)
                .scaleEffect(1.6)
                .frame(width: 34, height: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(network.displayName)
                    .font(.title2.weight(.semibold))
                    .textSelection(.enabled)
                Text(network.bssid ?? "BSSID hidden without Location access")
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if network.isConnected {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.green)
                }
            }
        }
    }

    @ViewBuilder
    private var advancedActions: some View {
        if network.isConnected {
            Button("Disconnect…") { confirmDisconnect = true }
                .disabled(store.isPerformingAction)
        } else if isEnterprise {
            Text("Enterprise networks need a configuration profile; join them from System Settings.")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            HStack {
                if !isOpen {
                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                }
                Button(isOpen ? "Join" : "Join…") {
                    store.join(id: network.id, password: password)
                    password = ""
                }
                .disabled(store.isPerformingAction || (!isOpen && password.isEmpty))
                if store.isPerformingAction { ProgressView().controlSize(.small) }
            }
        }
        HStack {
            Button("Copy SSID") { copy(network.ssid ?? "") }.disabled(network.isHidden)
            Button("Copy BSSID") { copy(network.bssid ?? "") }.disabled(network.bssid == nil)
            Button("Export scan as CSV…") { store.exportCSV() }
        }
        Button("Open Wireless Diagnostics") {
            let url = URL(fileURLWithPath: "/System/Library/CoreServices/Applications/Wireless Diagnostics.app")
            NSWorkspace.shared.open(url)
        }
        .help("Apple's built-in tool for packet captures and detailed radio diagnostics")
    }

    private var distanceText: String {
        let meters = network.estimatedDistanceMeters(
            referenceRSSIAt1m: settings.referenceRSSIAt1m,
            pathLossExponent: settings.pathLossExponent
        )
        if meters < 1 { return "under 1 m" }
        if meters > 200 { return "over 200 m" }
        return "~\(meters.formatted(.number.precision(.fractionLength(0)))) m"
    }

    private var snrHint: String {
        switch network.snr {
        case 40...: return "Excellent"
        case 25..<40: return "Good"
        case 15..<25: return "Fair"
        default: return "Poor"
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func row(_ label: String, _ value: String, hint: String? = nil) -> some View {
        LabeledContent {
            Text(value)
                .textSelection(.enabled)
                .multilineTextAlignment(.trailing)
        } label: {
            Text(label)
        }
        .help(hint ?? "")
        .font(.callout)
    }
}

private struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
        } label: {
            Text(title).font(.headline)
        }
    }
}

private struct MiniHistoryChart: View {
    let samples: [RSSISample]

    var body: some View {
        Chart(samples, id: \.date) { sample in
            LineMark(x: .value("Time", sample.date), y: .value("RSSI", sample.rssi))
                .interpolationMethod(.monotone)
            AreaMark(x: .value("Time", sample.date), y: .value("RSSI", sample.rssi))
                .foregroundStyle(.linearGradient(colors: [.accentColor.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom))
        }
        .chartYScale(domain: -100 ... -20)
        .chartYAxis { AxisMarks(values: [-90, -70, -50, -30]) }
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
    }
}
