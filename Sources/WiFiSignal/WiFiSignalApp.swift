import SwiftUI

@main
struct WiFiSignalApp: App {
    @StateObject private var settings = AppSettings.shared
    @StateObject private var store = ScanStore()
    @StateObject private var location = LocationPermission()
    @StateObject private var bluetooth = BluetoothScanner()

    init() {
        if ScreenshotExporter.runIfRequested() { exit(0) }
    }

    var body: some Scene {
        WindowGroup("Signal Analyzer") {
            ContentView()
                .environmentObject(settings)
                .environmentObject(store)
                .environmentObject(location)
                .environmentObject(bluetooth)
                .frame(minWidth: 860, minHeight: 500)
        }
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Refresh Wi-Fi") { store.refresh() }
                    .keyboardShortcut("r", modifiers: .command)
            }
            CommandGroup(after: .saveItem) {
                Button("Export Scan as CSV…") { store.exportCSV() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
        }
    }
}
