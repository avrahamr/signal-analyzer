import SwiftUI

/// Preferences window (⌘,).
struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        TabView {
            Form {
                Toggle("Refresh automatically", isOn: $settings.autoRefresh)
                Picker("Scan every", selection: $settings.refreshInterval) {
                    Text("3 seconds").tag(3.0)
                    Text("5 seconds").tag(5.0)
                    Text("10 seconds").tag(10.0)
                    Text("30 seconds").tag(30.0)
                }
                .disabled(!settings.autoRefresh)
                Toggle("Show hidden networks", isOn: $settings.showHiddenNetworks)
                Picker("Keep history", selection: $settings.historyLimit) {
                    Text("60 samples").tag(60)
                    Text("240 samples").tag(240)
                    Text("720 samples").tag(720)
                    Text("2000 samples").tag(2000)
                }
            }
            .tabItem { Label("Scanning", systemImage: "wifi") }

            Form {
                Section {
                    LabeledContent("Path-loss exponent") {
                        HStack {
                            Slider(value: $settings.pathLossExponent, in: 2...5, step: 0.1)
                            Text(settings.pathLossExponent.formatted(.number.precision(.fractionLength(1))))
                                .monospacedDigit()
                                .frame(width: 32)
                        }
                    }
                    LabeledContent("RSSI at 1 m (2.4 GHz)") {
                        HStack {
                            Slider(value: Binding(
                                get: { Double(settings.referenceRSSIAt1m) },
                                set: { settings.referenceRSSIAt1m = Int($0) }
                            ), in: -60 ... -25, step: 1)
                            Text("\(settings.referenceRSSIAt1m) dBm")
                                .monospacedDigit()
                                .frame(width: 60)
                        }
                    }
                } footer: {
                    Text("Distance is estimated with the log-distance path-loss model. Use ~2 for open space, ~3 for a typical home, ~4 with many walls.")
                        .foregroundStyle(.secondary)
                }
            }
            .tabItem { Label("Distance model", systemImage: "ruler") }

            Form {
                Toggle("Smooth RSSI readings", isOn: $settings.smoothBluetoothRSSI)
                Picker("Forget devices after", selection: $settings.bluetoothStaleSeconds) {
                    Text("10 seconds").tag(10.0)
                    Text("20 seconds").tag(20.0)
                    Text("60 seconds").tag(60.0)
                }
                LabeledContent("RSSI at 1 m") {
                    HStack {
                        Slider(value: Binding(
                            get: { Double(settings.bluetoothReferenceRSSIAt1m) },
                            set: { settings.bluetoothReferenceRSSIAt1m = Int($0) }
                        ), in: -75 ... -40, step: 1)
                        Text("\(settings.bluetoothReferenceRSSIAt1m) dBm")
                            .monospacedDigit()
                            .frame(width: 60)
                    }
                }
                Text("Radar rings use this with the path-loss exponent from the Distance model tab.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .tabItem { Label("Bluetooth", systemImage: "wave.3.right") }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 300)
        .toolbar {
            ToolbarItem {
                Button("Reset to Defaults") { settings.resetToDefaults() }
            }
        }
    }
}
