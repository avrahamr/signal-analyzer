import Charts
import SwiftUI

/// Tab 2: analyzer-style spectrum per band, and RSSI over time.
struct ChartsView: View {
    @EnvironmentObject private var store: ScanStore

    enum Mode: String, CaseIterable {
        case spectrum = "Spectrum"
        case history = "History"
    }

    @State private var mode: Mode = .spectrum
    @State private var band: WiFiNetwork.Band?
    @State private var widthMHz: Int?
    @State private var ignoreOwnNetwork = true

    private var effectiveBand: WiFiNetwork.Band {
        band ?? mostPopulatedBand ?? .ghz2
    }

    private var mostPopulatedBand: WiFiNetwork.Band? {
        let counts = Dictionary(grouping: store.networks, by: \.band).mapValues(\.count)
        return counts.filter { $0.key != .unknown }.max { $0.value < $1.value }?.key
    }

    private var connectedInBand: WiFiNetwork? {
        store.networks.first { $0.isConnected && $0.band == effectiveBand }
    }

    /// Default to the width the router is actually using, else a sensible one per band.
    private var effectiveWidth: Int {
        let supported = effectiveBand.supportedWidthsMHz
        if let widthMHz, supported.contains(widthMHz) { return widthMHz }
        if let connected = connectedInBand, supported.contains(connected.widthMHz) { return connected.widthMHz }
        return effectiveBand == .ghz2 ? 20 : 80
    }

    private var advice: ChannelAdvice? {
        guard count(in: effectiveBand) > 0 || connectedInBand != nil else { return nil }
        return SpectrumAnalysis.advise(
            networks: store.networks,
            band: effectiveBand,
            widthMHz: effectiveWidth,
            ignoreOwnNetwork: ignoreOwnNetwork
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 200)

                if mode == .spectrum {
                    Picker("Band", selection: Binding(get: { effectiveBand }, set: { band = $0 })) {
                        ForEach([WiFiNetwork.Band.ghz2, .ghz5, .ghz6], id: \.self) { b in
                            Text("\(b.rawValue) (\(count(in: b)))").tag(b)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 320)
                }

                Spacer()

                if mode == .spectrum {
                    Text("Hover a curve for details · click to pin")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, mode == .spectrum ? 8 : 12)

            if mode == .spectrum {
                recommendationBar
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
            Divider()

            Group {
                switch mode {
                case .spectrum:
                    SpectrumView(
                        networks: store.networks,
                        band: effectiveBand,
                        recommendation: advice.map { advice in
                            ChannelRecommendation(block: advice.highlightedBlock, score: advice.best.score, contenders: [], alternatives: [])
                        }
                    )
                case .history:
                    HistoryChart(series: store.historySeries(limit: 8))
                }
            }
            .padding(12)
        }
    }

    private var recommendationBar: some View {
        HStack(spacing: 12) {
            Text("Router channel")
                .foregroundStyle(.secondary)
            Picker("Width", selection: Binding(get: { effectiveWidth }, set: { widthMHz = $0 })) {
                ForEach(effectiveBand.supportedWidthsMHz, id: \.self) { w in
                    Text("\(w) MHz").tag(w)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: CGFloat(effectiveBand.supportedWidthsMHz.count) * 70)

            Toggle("Ignore my network", isOn: $ignoreOwnNetwork)
                .toggleStyle(.checkbox)
                .disabled(connectedInBand == nil)
                .help("Leave your own router's signal (and its sibling networks) out of the interference score")

            Spacer()

            if let advice {
                Label(advice.headline, systemImage: adviceIcon(advice.verdict))
                    .foregroundStyle(adviceColor(advice.verdict))
                    .help(advice.detail)
            } else {
                Text("No \(effectiveBand.rawValue) networks to evaluate")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
    }

    private func adviceIcon(_ verdict: ChannelAdvice.Verdict) -> String {
        switch verdict {
        case .keepCurrent: return "checkmark.circle"
        case .switchTo: return "arrow.right.circle"
        case .noCurrent: return "info.circle"
        }
    }

    private func adviceColor(_ verdict: ChannelAdvice.Verdict) -> Color {
        switch verdict {
        case .keepCurrent: return .green
        case .switchTo: return .orange
        case .noCurrent: return .secondary
        }
    }

    private func count(in band: WiFiNetwork.Band) -> Int {
        store.networks.filter { $0.band == band }.count
    }
}

struct HistoryChart: View {
    let series: [HistorySeries]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(SpectrumView.background)
            if series.isEmpty {
                Text("Samples accumulate with each scan.")
                    .foregroundStyle(.white.opacity(0.6))
            } else {
                Chart {
                    ForEach(series) { s in
                        ForEach(s.samples, id: \.date) { sample in
                            LineMark(
                                x: .value("Time", sample.date),
                                y: .value("RSSI", sample.rssi)
                            )
                            .foregroundStyle(by: .value("Network", s.label))
                            .interpolationMethod(.monotone)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                        }
                    }
                }
                .chartForegroundStyleScale(
                    domain: series.map(\.label),
                    range: series.map { SpectrumAnalysis.color(forNetworkID: $0.id) }
                )
                .chartYScale(domain: -100 ... -20)
                .chartYAxis {
                    AxisMarks(values: Array(stride(from: -100, through: -20, by: 10))) {
                        AxisGridLine().foregroundStyle(.white.opacity(0.18))
                        AxisValueLabel().foregroundStyle(.white.opacity(0.75))
                    }
                }
                .chartXAxis {
                    AxisMarks {
                        AxisGridLine().foregroundStyle(.white.opacity(0.1))
                        AxisValueLabel().foregroundStyle(.white.opacity(0.75))
                    }
                }
                .chartLegend(position: .bottom, alignment: .leading)
                .environment(\.colorScheme, .dark)
                .padding(16)
            }
        }
    }
}
