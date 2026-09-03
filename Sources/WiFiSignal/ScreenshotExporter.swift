import AppKit
import SwiftUI

/// `--render-screenshots <dir>` renders the chart views with demo data to
/// PNG files (for the README) and exits. Runs offscreen; no window needed.
@MainActor
enum ScreenshotExporter {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--render-screenshots"), flag + 1 < args.count else { return false }
        let directory = URL(fileURLWithPath: args[flag + 1])
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let networks = DemoData.networks(jitter: false)
        let advice = SpectrumAnalysis.advise(networks: networks, band: .ghz5, widthMHz: 80)
        let recommendation = advice.map {
            ChannelRecommendation(block: $0.highlightedBlock, score: $0.best.score, contenders: [], alternatives: [])
        }

        render(
            SpectrumView(networks: networks, band: .ghz5, recommendation: recommendation)
                .frame(width: 1200, height: 560),
            to: directory.appendingPathComponent("spectrum.png")
        )
        render(
            HistoryChart(series: DemoData.historySeries())
                .frame(width: 1200, height: 460),
            to: directory.appendingPathComponent("history.png")
        )
        render(
            BluetoothRadarView(devices: DemoData.bluetoothDevices(), referenceRSSIAt1m: -59, pathLossExponent: 2.5)
                .frame(width: 900, height: 600),
            to: directory.appendingPathComponent("radar.png")
        )
        print("Wrote screenshots to \(directory.path)")
        return true
    }

    private static func render<V: View>(_ view: V, to url: URL) {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
        renderer.scale = 2
        guard let image = renderer.cgImage else {
            print("Failed to render \(url.lastPathComponent)")
            return
        }
        let rep = NSBitmapImageRep(cgImage: image)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: url)
        }
    }
}
