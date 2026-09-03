import SwiftUI

/// Analyzer-style spectrum: one bell curve per network covering its channel
/// width, peak height = RSSI, drawn on a dark plot with a channel axis.
struct SpectrumView: View {
    let networks: [WiFiNetwork]
    let band: WiFiNetwork.Band
    var recommendation: ChannelRecommendation? = nil

    @State private var hoveredID: String?
    @State private var pinnedID: String?
    @State private var hoverLocation: CGPoint?

    private let topDBm = -20.0
    private let floorDBm = -100.0
    private let insets = (left: CGFloat(70), right: CGFloat(20), top: CGFloat(30), bottom: CGFloat(64))

    static let background = Color(red: 0.06, green: 0.08, blue: 0.11)

    /// Weakest first so strong networks are drawn on top.
    private var shown: [WiFiNetwork] {
        networks
            .filter { $0.band == band && $0.frequencyRangeMHz != nil }
            .sorted { $0.rssi < $1.rssi }
    }

    private var activeID: String? { hoveredID ?? pinnedID }

    var body: some View {
        GeometryReader { geo in
            let plot = CGRect(
                x: insets.left,
                y: insets.top,
                width: max(geo.size.width - insets.left - insets.right, 10),
                height: max(geo.size.height - insets.top - insets.bottom, 10)
            )
            ZStack(alignment: .topLeading) {
                Self.background
                gridLines(in: plot)
                yAxisLabels(in: plot)
                channelAxis(in: plot)
                recommendedBlock(in: plot)
                ForEach(shown) { n in curve(for: n, in: plot) }
                labels(in: plot)
                bandBadge(in: plot)
                if band == .ghz5 { regulationLegend(in: plot) }
                if let id = activeID, let n = shown.first(where: { $0.id == id }), let location = hoverLocation ?? pinnedLocation(for: n, in: plot) {
                    tooltip(for: n, at: location, in: plot)
                }
                if shown.isEmpty {
                    Text("No \(band.rawValue) networks in the latest scan")
                        .foregroundStyle(.white.opacity(0.6))
                        .position(x: plot.midX, y: plot.midY)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    hoverLocation = point
                    hoveredID = hitTest(point, in: plot)
                case .ended:
                    hoverLocation = nil
                    hoveredID = nil
                }
            }
            .onTapGesture {
                pinnedID = hoveredID == pinnedID ? nil : hoveredID
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Geometry

    private func x(forFrequency frequency: Double, in plot: CGRect) -> CGFloat {
        let domain = band.frequencyDomain
        let fraction = (frequency - Double(domain.lowerBound)) / Double(domain.upperBound - domain.lowerBound)
        return plot.minX + CGFloat(fraction) * plot.width
    }

    private func y(forDBm dbm: Double, in plot: CGRect) -> CGFloat {
        let clamped = min(max(dbm, floorDBm), topDBm)
        return plot.minY + CGFloat((topDBm - clamped) / (topDBm - floorDBm)) * plot.height
    }

    /// Raised-cosine bell over the network's occupied spectrum.
    private func dbm(of network: WiFiNetwork, atFrequency frequency: Double) -> Double? {
        guard let range = network.frequencyRangeMHz else { return nil }
        let center = Double(range.lowerBound + range.upperBound) / 2
        let half = Double(range.upperBound - range.lowerBound) / 2
        guard half > 0, abs(frequency - center) <= half else { return nil }
        let shape = 0.5 * (1 + cos(.pi * (frequency - center) / half))
        return floorDBm + (Double(network.rssi) - floorDBm) * shape
    }

    private func curvePath(for network: WiFiNetwork, in plot: CGRect) -> Path {
        guard let range = network.frequencyRangeMHz else { return Path() }
        var path = Path()
        let steps = 48
        for i in 0...steps {
            let frequency = Double(range.lowerBound) + Double(range.upperBound - range.lowerBound) * Double(i) / Double(steps)
            let level = dbm(of: network, atFrequency: frequency) ?? floorDBm
            let point = CGPoint(x: x(forFrequency: frequency, in: plot), y: y(forDBm: level, in: plot))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    private func peakPoint(for network: WiFiNetwork, in plot: CGRect) -> CGPoint {
        let center = Double(network.centerFrequencyMHz ?? band.frequencyDomain.lowerBound)
        return CGPoint(x: x(forFrequency: center, in: plot), y: y(forDBm: Double(network.rssi), in: plot))
    }

    private func pinnedLocation(for network: WiFiNetwork, in plot: CGRect) -> CGPoint? {
        pinnedID == network.id ? peakPoint(for: network, in: plot) : nil
    }

    /// Networks whose curve is above the pointer; the lowest curve wins so the
    /// pointer selects the most specific (innermost) one.
    private func hitTest(_ point: CGPoint, in plot: CGRect) -> String? {
        guard plot.contains(point) else { return nil }
        let domain = band.frequencyDomain
        let frequency = Double(domain.lowerBound) + Double(domain.upperBound - domain.lowerBound) * Double((point.x - plot.minX) / plot.width)
        let pointerDBm = topDBm - Double((point.y - plot.minY) / plot.height) * (topDBm - floorDBm)
        var best: (id: String, level: Double)?
        for n in shown {
            guard let level = dbm(of: n, atFrequency: frequency), level >= pointerDBm else { continue }
            if best == nil || level < best!.level { best = (n.id, level) }
        }
        return best?.id
    }

    // MARK: - Layers

    private func gridLines(in plot: CGRect) -> some View {
        Path { path in
            for dbm in stride(from: Int(topDBm), through: Int(floorDBm), by: -10) {
                let yy = y(forDBm: Double(dbm), in: plot)
                path.move(to: CGPoint(x: plot.minX, y: yy))
                path.addLine(to: CGPoint(x: plot.maxX, y: yy))
            }
        }
        .stroke(.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
    }

    private func yAxisLabels(in plot: CGRect) -> some View {
        ForEach(Array(stride(from: Int(topDBm), through: Int(floorDBm) + 10, by: -10)), id: \.self) { dbm in
            Text("\(dbm) dBm")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: insets.left - 10, alignment: .trailing)
                .position(x: (insets.left - 10) / 2 + 2, y: y(forDBm: Double(dbm), in: plot))
        }
    }

    private func channelAxis(in plot: CGRect) -> some View {
        let channels = band.allChannels
        let counts = Dictionary(grouping: shown, by: \.channel).mapValues(\.count)
        let connectedChannel = shown.first(where: \.isConnected)?.channel
        let recommended = Set(recommendation?.block.channels ?? [])
        return ZStack(alignment: .topLeading) {
            Path { path in
                path.move(to: CGPoint(x: plot.minX, y: plot.maxY))
                path.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
            }
            .stroke(.white.opacity(0.5), lineWidth: 1)

            ForEach(Array(channels.enumerated()), id: \.element) { index, channel in
                if let frequency = band.frequencyMHz(forChannel: channel) {
                    let xx = x(forFrequency: Double(frequency), in: plot)
                    let regulation = band.regulation(forChannel: channel)
                    Path { path in
                        path.move(to: CGPoint(x: xx, y: plot.maxY))
                        path.addLine(to: CGPoint(x: xx, y: plot.maxY + 4))
                    }
                    .stroke(.white.opacity(0.5), lineWidth: 1)

                    if index % band.channelLabelStride == 0 {
                        Text("\(channel)")
                            .font(.caption.weight(channel == connectedChannel ? .bold : .regular).monospacedDigit())
                            .foregroundStyle(axisLabelColor(
                                channel: channel,
                                regulation: regulation,
                                isConnected: channel == connectedChannel,
                                isRecommended: recommended.contains(channel),
                                occupied: counts[channel] != nil
                            ))
                            .position(x: xx, y: plot.maxY + 14)
                            .help(regulation == .unrestricted ? "Channel \(channel)" : "Channel \(channel) · \(regulation.label)")
                    }

                    if let count = counts[channel] {
                        Text("\(count)")
                            .font(.caption2.bold().monospacedDigit())
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(.white.opacity(0.18)))
                            .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 1))
                            .position(x: xx, y: plot.maxY + 34)
                            .help("\(count) network\(count == 1 ? "" : "s") on channel \(channel)")
                    }
                }
            }
        }
    }

    private func axisLabelColor(channel: Int, regulation: ChannelRegulation, isConnected: Bool, isRecommended: Bool, occupied: Bool) -> Color {
        if isConnected { return .cyan }
        if isRecommended { return .green }
        switch regulation {
        case .dfsWeather: return Color(red: 1, green: 0.45, blue: 0.45).opacity(0.9)
        case .dfs: return .orange.opacity(occupied ? 0.95 : 0.7)
        case .unrestricted: return .white.opacity(occupied ? 0.9 : 0.5)
        }
    }

    /// Green bracket under the recommended block's channels.
    @ViewBuilder
    private func recommendedBlock(in plot: CGRect) -> some View {
        if let block = recommendation?.block,
           let first = block.channels.first, let last = block.channels.last,
           let lowerFreq = band.frequencyMHz(forChannel: first),
           let upperFreq = band.frequencyMHz(forChannel: last) {
            let x0 = x(forFrequency: Double(lowerFreq) - 10, in: plot)
            let x1 = x(forFrequency: Double(upperFreq) + 10, in: plot)
            let yy = plot.maxY + 46
            Path { path in
                path.move(to: CGPoint(x: x0, y: yy - 5))
                path.addLine(to: CGPoint(x: x0, y: yy))
                path.addLine(to: CGPoint(x: x1, y: yy))
                path.addLine(to: CGPoint(x: x1, y: yy - 5))
            }
            .stroke(.green, lineWidth: 2)
            Rectangle()
                .fill(.green.opacity(0.06))
                .frame(width: max(x1 - x0, 1), height: plot.height)
                .position(x: (x0 + x1) / 2, y: plot.midY)
                .allowsHitTesting(false)
        }
    }

    private func regulationLegend(in plot: CGRect) -> some View {
        HStack(spacing: 10) {
            legendItem(color: .white.opacity(0.7), text: "No DFS")
            legendItem(color: .orange, text: "DFS (radar detection)")
            legendItem(color: Color(red: 1, green: 0.45, blue: 0.45), text: "Weather radar (often disabled)")
        }
        .font(.caption2)
        .foregroundStyle(.white.opacity(0.75))
        .position(x: plot.maxX - 190, y: plot.minY - 14)
    }

    private func legendItem(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(text)
        }
    }

    private func curve(for network: WiFiNetwork, in plot: CGRect) -> some View {
        let path = curvePath(for: network, in: plot)
        let color = SpectrumAnalysis.color(forNetworkID: network.id)
        let (fill, stroke) = emphasis(for: network)
        return ZStack {
            path.fill(color.opacity(fill))
            path.stroke(color.opacity(stroke), lineWidth: network.isConnected ? 3 : 1.5)
        }
    }

    private func emphasis(for network: WiFiNetwork) -> (fill: Double, stroke: Double) {
        guard let activeID else { return (0.22, 0.9) }
        return activeID == network.id ? (0.5, 1) : (0.07, 0.3)
    }

    /// SSID labels at each peak, nudged upward when they would collide.
    private func labels(in plot: CGRect) -> some View {
        var placed: [CGRect] = []
        let items: [(WiFiNetwork, CGPoint)] = shown
            .sorted { $0.rssi > $1.rssi }
            .map { n in
                let peak = peakPoint(for: n, in: plot)
                let width = CGFloat(n.displayName.count) * 7 + 12
                var frame = CGRect(x: peak.x - width / 2, y: peak.y - 22, width: width, height: 16)
                frame.origin.x = min(max(frame.minX, plot.minX), plot.maxX - width)
                while placed.contains(where: { $0.intersects(frame) }) && frame.minY > plot.minY - 10 {
                    frame.origin.y -= 16
                }
                frame.origin.y = max(frame.minY, plot.minY - 12)
                placed.append(frame)
                return (n, CGPoint(x: frame.midX, y: frame.midY))
            }
        return ForEach(items, id: \.0.id) { network, point in
            let dimmed = activeID != nil && activeID != network.id
            Text(network.displayName)
                .font(network.isConnected ? .callout.bold() : .callout)
                .foregroundStyle(SpectrumAnalysis.color(forNetworkID: network.id).opacity(dimmed ? 0.35 : 1))
                .lineLimit(1)
                .shadow(color: .black.opacity(0.8), radius: 2)
                .position(point)
        }
    }

    private func bandBadge(in plot: CGRect) -> some View {
        Text(band.rawValue)
            .font(.caption.bold())
            .foregroundStyle(.green)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 4).stroke(.green, lineWidth: 1))
            .position(x: insets.left / 2, y: plot.maxY + 14)
    }

    private func tooltip(for network: WiFiNetwork, at location: CGPoint, in plot: CGRect) -> some View {
        let color = SpectrumAnalysis.color(forNetworkID: network.id)
        let card = VStack(alignment: .leading, spacing: 3) {
            Text(network.displayName).font(.callout.bold()).foregroundStyle(color)
            if let bssid = network.bssid { Text(bssid).font(.caption.monospaced()) }
            Text("\(network.rssi) dBm · SNR \(network.snr) dB · \(network.qualityPercent) %")
            Text("Channel \(network.channel) · \(network.widthMHz > 0 ? "\(network.widthMHz) MHz" : "width unknown") · \(network.security)")
            if network.isConnected { Text("Connected").foregroundStyle(.green) }
        }
        .font(.caption)
        .foregroundStyle(.white)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.85)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(color.opacity(0.7), lineWidth: 1))
        .fixedSize()

        let width: CGFloat = 230, height: CGFloat = 80
        let xx = min(max(location.x + 16 + width / 2, plot.minX + width / 2), plot.maxX - width / 2)
        let yy = min(max(location.y - 10 - height / 2, plot.minY + height / 2), plot.maxY - height / 2)
        return card.position(x: xx, y: yy)
    }
}
