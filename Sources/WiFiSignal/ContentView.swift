import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: ScanStore

    var body: some View {
        TabView {
            NetworksView()
                .tabItem { Label("Networks", systemImage: "list.bullet") }
            ChartsView()
                .tabItem { Label("Charts", systemImage: "chart.bar.xaxis") }
            BluetoothView()
                .tabItem { Label("Bluetooth", systemImage: "wave.3.right") }
        }
        .onAppear { store.start() }
        .toolbar {
            ToolbarItem {
                Button {
                    store.refresh()
                } label: {
                    Label("Refresh Wi-Fi", systemImage: "arrow.clockwise")
                }
                .disabled(store.isScanning)
                .help("Scan Wi-Fi now (⌘R)")
            }
        }
    }
}
