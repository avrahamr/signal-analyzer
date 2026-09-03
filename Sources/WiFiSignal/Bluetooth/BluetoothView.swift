import SwiftUI

/// Tab 3: live Bluetooth LE advertisers around the Mac, as a table, RSSI
/// history, or a proximity radar.
struct BluetoothView: View {
    @EnvironmentObject private var bluetooth: BluetoothScanner
    @EnvironmentObject private var settings: AppSettings

    enum Mode: String, CaseIterable {
        case devices = "Devices"
        case history = "History"
        case radar = "Radar"
    }

    @State private var mode: Mode = .devices

    var body: some View {
        VStack(spacing: 0) {
            if let problem = bluetooth.problemDescription {
                InfoBanner(
                    systemImage: "wave.3.right.circle",
                    message: problem,
                    buttonTitle: "Open System Settings"
                ) {
                    openPrivacySettings(pane: "Privacy_Bluetooth")
                }
                Divider()
            }

            HStack {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 260)
                Spacer()
                if mode == .radar {
                    Text("Hover a dot for details · click to pin")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            Divider()

            Group {
                switch mode {
                case .devices:
                    BluetoothTable(devices: bluetooth.devices, showEmptyState: bluetooth.problemDescription == nil)
                case .history:
                    HistoryChart(series: bluetooth.historySeries(limit: 8))
                        .padding(12)
                case .radar:
                    BluetoothRadarView(
                        devices: bluetooth.devices,
                        referenceRSSIAt1m: settings.bluetoothReferenceRSSIAt1m,
                        pathLossExponent: settings.pathLossExponent
                    )
                    .padding(12)
                }
            }

            Divider()
            HStack(spacing: 12) {
                if bluetooth.isScanning { ProgressView().controlSize(.small) }
                Text("\(bluetooth.devices.count) devices · Bluetooth LE only · identifiers are randomised by macOS")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .onAppear { bluetooth.start() }
        .onDisappear { bluetooth.stop() }
    }
}

private struct BluetoothTable: View {
    let devices: [BluetoothDevice]
    let showEmptyState: Bool

    var body: some View {
        Table(devices) {
            TableColumn("Signal") { d in
                HStack(spacing: 6) {
                    Circle()
                        .fill(SpectrumAnalysis.color(forNetworkID: d.id.uuidString))
                        .frame(width: 8, height: 8)
                    SignalBars(level: d.bars)
                    Text("\(d.rssi) dBm").monospacedDigit()
                }
            }
            .width(min: 120, ideal: 130)

            TableColumn("Name") { d in
                Text(d.displayName)
                    .foregroundStyle(d.name == nil ? .secondary : .primary)
            }
            .width(min: 150, ideal: 200)

            TableColumn("Manufacturer") { d in Text(d.manufacturer ?? "—") }
                .width(min: 110, ideal: 150)

            TableColumn("Type") { d in Text(d.kind ?? "—") }
                .width(min: 120, ideal: 190)

            TableColumn("Connectable") { d in
                Image(systemName: d.isConnectable ? "checkmark" : "minus")
                    .foregroundStyle(d.isConnectable ? .green : .secondary)
            }
            .width(80)

            TableColumn("Services") { d in
                Text(d.serviceCount > 0 ? "\(d.serviceCount)" : "—").monospacedDigit()
            }
            .width(60)

            TableColumn("Tx power") { d in
                Text(d.txPower.map { "\($0) dBm" } ?? "—").monospacedDigit()
            }
            .width(70)

            TableColumn("Last seen") { d in
                Text(d.lastSeen, style: .relative).monospacedDigit()
            }
            .width(80)

            TableColumn("ID") { d in
                Text(d.shortID).monospaced().foregroundStyle(.secondary)
            }
            .width(90)
        }
        .overlay {
            if devices.isEmpty && showEmptyState {
                ContentUnavailableView(
                    "Listening for devices",
                    systemImage: "wave.3.right",
                    description: Text("Bluetooth LE advertisements appear here as they arrive.")
                )
            }
        }
    }
}
