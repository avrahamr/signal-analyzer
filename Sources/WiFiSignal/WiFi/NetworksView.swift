import SwiftUI

/// Tab 1: the sortable-by-signal table, with a detail inspector on the right.
struct NetworksView: View {
    @EnvironmentObject private var store: ScanStore
    @EnvironmentObject private var location: LocationPermission
    @EnvironmentObject private var settings: AppSettings
    @State private var selectedID: WiFiNetwork.ID?
    @State private var showInspector = false

    private var visibleNetworks: [WiFiNetwork] {
        settings.showHiddenNetworks ? store.networks : store.networks.filter { !$0.isHidden }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !location.isAuthorized {
                InfoBanner(
                    systemImage: "location.slash",
                    message: location.statusDescription,
                    buttonTitle: location.status == .notDetermined ? "Allow Location Access" : "Open System Settings"
                ) {
                    if location.status == .notDetermined {
                        location.request()
                    } else {
                        openPrivacySettings(pane: "Privacy_LocationServices")
                    }
                }
                Divider()
            }
            NetworkTable(networks: visibleNetworks, selection: $selectedID)
            Divider()
            WiFiStatusBar()
        }
        .onChange(of: selectedID) { _, newValue in
            if newValue != nil { showInspector = true }
        }
        .inspector(isPresented: $showInspector) {
            NetworkDetailView(networkID: selectedID)
                .inspectorColumnWidth(min: 340, ideal: 400, max: 560)
        }
        .toolbar {
            ToolbarItem {
                Button {
                    showInspector.toggle()
                } label: {
                    Label("Details", systemImage: "sidebar.trailing")
                }
                .help("Show or hide network details")
            }
        }
    }
}

struct NetworkTable: View {
    let networks: [WiFiNetwork]
    @Binding var selection: WiFiNetwork.ID?

    var body: some View {
        Table(networks, selection: $selection) {
            TableColumn("Signal") { n in
                HStack(spacing: 6) {
                    SignalBars(level: n.bars)
                    Text("\(n.rssi) dBm").monospacedDigit()
                }
            }
            .width(min: 110, ideal: 120)

            TableColumn("Network") { n in
                HStack(spacing: 6) {
                    Text(n.displayName)
                        .fontWeight(n.isConnected ? .semibold : .regular)
                        .foregroundStyle(n.isHidden ? .secondary : .primary)
                    if n.isConnected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .help("Connected")
                    }
                }
            }
            .width(min: 160, ideal: 220)

            TableColumn("BSSID") { n in
                Text(n.bssid ?? "—").monospaced()
            }
            .width(min: 140, ideal: 150)

            TableColumn("Channel") { n in
                Text("\(n.channel)").monospacedDigit()
            }
            .width(60)

            TableColumn("Band") { n in Text(n.band.rawValue) }
                .width(70)

            TableColumn("Width") { n in
                Text(n.widthMHz > 0 ? "\(n.widthMHz) MHz" : "—")
            }
            .width(70)

            TableColumn("Security") { n in Text(n.security) }
                .width(min: 90, ideal: 130)

            TableColumn("SNR") { n in
                Text("\(n.snr) dB").monospacedDigit()
            }
            .width(60)
        }
        .overlay {
            if networks.isEmpty {
                ContentUnavailableView(
                    "No networks yet",
                    systemImage: "wifi",
                    description: Text("The first scan takes a few seconds.")
                )
            }
        }
    }
}

struct WiFiStatusBar: View {
    @EnvironmentObject private var store: ScanStore
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        HStack(spacing: 12) {
            if store.isScanning {
                ProgressView().controlSize(.small)
            }
            Text(statusText).foregroundStyle(.secondary)
            if let error = store.errorMessage {
                Text(error).foregroundStyle(.red)
            }
            if let message = store.actionMessage {
                Text(message).foregroundStyle(.blue)
            }
            Spacer()
            Toggle("Auto-refresh", isOn: $settings.autoRefresh)
                .toggleStyle(.checkbox)
            Picker("Every", selection: $settings.refreshInterval) {
                Text("3 s").tag(3.0)
                Text("5 s").tag(5.0)
                Text("10 s").tag(10.0)
                Text("30 s").tag(30.0)
            }
            .frame(width: 120)
            .disabled(!settings.autoRefresh)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var statusText: String {
        guard let t = store.lastScan else { return "Scanning…" }
        let time = t.formatted(date: .omitted, time: .standard)
        return "\(store.networks.count) networks on \(store.interfaceName) · updated \(time)"
    }
}
