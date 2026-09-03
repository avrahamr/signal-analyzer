import SwiftUI

/// Four-bar signal indicator shared by the Wi-Fi and Bluetooth tables.
struct SignalBars: View {
    /// 0…4
    let level: Int

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i < level ? color : Color.secondary.opacity(0.25))
                    .frame(width: 4, height: CGFloat(6 + i * 3))
            }
        }
        .accessibilityLabel("\(level) of 4 bars")
    }

    private var color: Color {
        switch level {
        case 3, 4: return .green
        case 2: return .orange
        default: return .red
        }
    }
}

/// Maps an RSSI in dBm to 0…4 bars. Thresholds roughly match the macOS menu-bar indicator.
func signalBars(forRSSI rssi: Int) -> Int {
    if rssi >= -50 { return 4 }
    if rssi >= -60 { return 3 }
    if rssi >= -70 { return 2 }
    if rssi >= -80 { return 1 }
    return 0
}

/// Warning strip shown above a table when a permission or hardware state blocks results.
struct InfoBanner: View {
    let systemImage: String
    let message: String
    var buttonTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.orange)
            Text(message)
            Spacer()
            if let buttonTitle, let action {
                Button(buttonTitle, action: action)
            }
        }
        .font(.callout)
        .padding(10)
        .background(.orange.opacity(0.12))
    }
}

func openPrivacySettings(pane: String) {
    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!
    NSWorkspace.shared.open(url)
}
