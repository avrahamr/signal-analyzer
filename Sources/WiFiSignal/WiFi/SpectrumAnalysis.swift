import SwiftUI

/// Regulatory status of a 20 MHz channel. DFS channels require radar
/// detection; the weather-radar sub-band is disabled outright by many routers.
enum ChannelRegulation: Int, Comparable, Sendable {
    case unrestricted
    case dfs
    case dfsWeather

    static func < (a: ChannelRegulation, b: ChannelRegulation) -> Bool { a.rawValue < b.rawValue }

    var label: String {
        switch self {
        case .unrestricted: return "No DFS"
        case .dfs: return "DFS"
        case .dfsWeather: return "Weather radar"
        }
    }
}

/// A candidate operating channel of a given width: one or more contiguous
/// 20 MHz channels, the first being the primary.
struct ChannelBlock: Hashable, Sendable {
    let band: WiFiNetwork.Band
    let channels: [Int]
    let widthMHz: Int

    var primaryChannel: Int { channels.first ?? 0 }

    var label: String {
        guard let first = channels.first, let last = channels.last, first != last else {
            return "\(primaryChannel)"
        }
        return "\(first)–\(last)"
    }

    var regulation: ChannelRegulation {
        channels.map(band.regulation(forChannel:)).max() ?? .unrestricted
    }

    var frequencyRangeMHz: ClosedRange<Int>? {
        guard let first = channels.first, let last = channels.last,
              let lower = band.frequencyMHz(forChannel: first),
              let upper = band.frequencyMHz(forChannel: last) else { return nil }
        return (lower - 10)...(upper + 10)
    }
}

struct ChannelRecommendation: Sendable {
    let block: ChannelBlock
    let score: Double
    /// Networks that overlap the block, strongest first.
    let contenders: [WiFiNetwork]
    /// Runners-up for the tooltip.
    let alternatives: [(block: ChannelBlock, score: Double)]
}

extension WiFiNetwork.Band {
    /// Every 20 MHz channel in the band, used for axis ticks and scoring.
    var allChannels: [Int] { channelGroups.flatMap { $0 } }

    /// Runs of contiguous 20 MHz channels; wider channels never straddle a gap.
    var channelGroups: [[Int]] {
        switch self {
        case .ghz2: return [Array(1...14)]
        case .ghz5:
            return [
                Array(stride(from: 36, through: 64, by: 4)),
                Array(stride(from: 100, through: 144, by: 4)),
                Array(stride(from: 149, through: 165, by: 4)),
            ]
        case .ghz6: return [Array(stride(from: 1, through: 233, by: 4))]
        case .unknown: return []
        }
    }

    /// Label every Nth channel on the axis to avoid clutter.
    var channelLabelStride: Int { self == .ghz6 ? 4 : 1 }

    /// Channels conventionally preferred because they do not overlap each other.
    var preferredChannels: [Int] {
        self == .ghz2 ? [1, 6, 11] : []
    }

    var supportedWidthsMHz: [Int] {
        switch self {
        case .ghz2: return [20, 40]
        case .ghz5, .ghz6: return [20, 40, 80, 160]
        case .unknown: return []
        }
    }

    func regulation(forChannel channel: Int) -> ChannelRegulation {
        guard self == .ghz5 else { return .unrestricted }
        switch channel {
        case 120, 124, 128: return .dfsWeather
        case 52...144: return .dfs
        default: return .unrestricted
        }
    }

    /// All legal blocks of the given width, aligned to the start of each
    /// channel group the way the 802.11 channelisation defines them.
    func blocks(widthMHz: Int) -> [ChannelBlock] {
        let count = max(widthMHz / 20, 1)
        var blocks: [ChannelBlock] = []
        if self == .ghz2 {
            // 2.4 GHz channels are 5 MHz apart; 20 MHz needs one channel,
            // 40 MHz a primary plus a secondary four channels up. Channel 14 is
            // Japan-only, so it is excluded from recommendations.
            let usable = Array(1...13)
            if count == 1 {
                blocks = usable.map { ChannelBlock(band: self, channels: [$0], widthMHz: 20) }
            } else {
                blocks = usable.filter { $0 + 4 <= 13 }.map { ChannelBlock(band: self, channels: [$0, $0 + 4], widthMHz: 40) }
            }
            return blocks
        }
        for group in channelGroups {
            var index = 0
            while index + count <= group.count {
                blocks.append(ChannelBlock(band: self, channels: Array(group[index..<(index + count)]), widthMHz: widthMHz))
                index += count
            }
        }
        return blocks
    }
}

enum SpectrumAnalysis {
    /// Extra interference-equivalent added to DFS blocks so they only win when
    /// clearly quieter. Roughly one -75 dBm neighbour fully on the block.
    static let dfsPenalty = 25.0

    /// Stable colour per network so it matches across the table, spectrum and history.
    static func color(forNetworkID id: String) -> Color {
        var hash: UInt32 = 5381
        for byte in id.utf8 { hash = (hash &* 33) ^ UInt32(byte) }
        // Golden-angle hue spacing spreads similar hashes apart.
        let hue = (Double(hash % 1000) / 1000 * 0.618_033_988).truncatingRemainder(dividingBy: 1)
        return Color(hue: hue, saturation: 0.72, brightness: 0.95)
    }

    /// Fraction of `range` covered by the network's occupied spectrum, 0…1.
    static func overlap(of network: WiFiNetwork, with range: ClosedRange<Int>) -> Double {
        guard let occupied = network.frequencyRangeMHz else { return 0 }
        let lower = max(occupied.lowerBound, range.lowerBound)
        let upper = min(occupied.upperBound, range.upperBound)
        guard upper > lower, range.upperBound > range.lowerBound else { return 0 }
        return Double(upper - lower) / Double(range.upperBound - range.lowerBound)
    }

    /// How much a network's signal lands on a single 20 MHz channel.
    static func overlap(of network: WiFiNetwork, onChannelFrequency channelMHz: Int) -> Double {
        overlap(of: network, with: (channelMHz - 10)...(channelMHz + 10))
    }

    /// Interference score: overlap weighted by how far the signal sits above
    /// the -100 dBm floor. Higher = more crowded.
    static func congestion(of networks: [WiFiNetwork], on range: ClosedRange<Int>) -> Double {
        networks.reduce(0) { $0 + overlap(of: $1, with: range) * Double(max($1.rssi + 100, 0)) }
    }

    /// Per-channel congestion for the axis and simple displays.
    static func congestion(networks: [WiFiNetwork], band: WiFiNetwork.Band) -> [Int: Double] {
        var scores: [Int: Double] = [:]
        let inBand = networks.filter { $0.band == band }
        for channel in band.allChannels {
            guard let freq = band.frequencyMHz(forChannel: channel) else { continue }
            scores[channel] = congestion(of: inBand, on: (freq - 10)...(freq + 10))
        }
        return scores
    }

    /// The connected network plus BSSIDs that look like the same access point
    /// (five of six MAC octets equal, or a hidden twin at the same level), so a
    /// recommendation for "your router" does not count the router itself.
    static func ownNetworkIDs(in networks: [WiFiNetwork]) -> Set<String> {
        guard let connected = networks.first(where: \.isConnected) else { return [] }
        var ids: Set<String> = [connected.id]
        let ownOctets = connected.bssid?.lowercased().split(separator: ":")
        for n in networks where n.id != connected.id && n.band == connected.band {
            if let ownOctets, let octets = n.bssid?.lowercased().split(separator: ":"), octets.count == 6, ownOctets.count == 6 {
                let matching = zip(ownOctets, octets).filter { $0 == $1 }.count
                if matching >= 5 { ids.insert(n.id) }
            } else if n.bssid == nil, n.isHidden, n.channel == connected.channel, abs(n.rssi - connected.rssi) <= 4 {
                ids.insert(n.id)
            }
        }
        return ids
    }

    /// Best block of the requested width. Weather-radar blocks are never
    /// recommended; other DFS blocks carry `dfsPenalty`. Ties prefer the
    /// band's conventional non-overlapping channels, then the lowest channel.
    static func recommend(
        networks: [WiFiNetwork],
        band: WiFiNetwork.Band,
        widthMHz: Int,
        excluding excluded: Set<String> = []
    ) -> ChannelRecommendation? {
        let considered = networks.filter { $0.band == band && !excluded.contains($0.id) }
        let scored: [(block: ChannelBlock, score: Double)] = band.blocks(widthMHz: widthMHz)
            .filter { $0.regulation != .dfsWeather }
            .compactMap { block in
                guard let range = block.frequencyRangeMHz else { return nil }
                let penalty = block.regulation == .dfs ? dfsPenalty : 0
                return (block, congestion(of: considered, on: range) + penalty)
            }
            .sorted { a, b in
                if a.score != b.score { return a.score < b.score }
                let aPreferred = band.preferredChannels.contains(a.block.primaryChannel)
                let bPreferred = band.preferredChannels.contains(b.block.primaryChannel)
                if aPreferred != bPreferred { return aPreferred }
                return a.block.primaryChannel < b.block.primaryChannel
            }
        guard let best = scored.first, let range = best.block.frequencyRangeMHz else { return nil }
        let contenders = considered
            .filter { overlap(of: $0, with: range) > 0 }
            .sorted { $0.rssi > $1.rssi }
        return ChannelRecommendation(
            block: best.block,
            score: best.score,
            contenders: contenders,
            alternatives: Array(scored.dropFirst().prefix(3))
        )
    }

    /// Convenience used by the 20 MHz axis marker and tests.
    static func leastCrowdedChannel(networks: [WiFiNetwork], band: WiFiNetwork.Band) -> Int? {
        recommend(networks: networks, band: band, widthMHz: 20)?.block.primaryChannel
    }
}

/// What to tell the user about their router's channel choice.
struct ChannelAdvice: Sendable {
    enum Verdict: Sendable {
        /// Connected block is already best or within the margin of the best.
        case keepCurrent
        /// A clearly quieter block exists.
        case switchTo
        /// Not connected on this band; just report the quietest block.
        case noCurrent
    }

    let verdict: Verdict
    let widthMHz: Int
    let current: (block: ChannelBlock, score: Double)?
    let best: ChannelRecommendation

    /// Block to highlight on the axis.
    var highlightedBlock: ChannelBlock {
        verdict == .keepCurrent ? (current?.block ?? best.block) : best.block
    }

    var headline: String {
        switch verdict {
        case .keepCurrent:
            let block = current?.block ?? best.block
            return "Keep Auto · channel \(block.primaryChannel) (\(block.label), \(block.widthMHz) MHz) is fine"
        case .switchTo:
            return "Consider channels \(best.block.label) (\(best.block.widthMHz) MHz)"
        case .noCurrent:
            return "Quietest \(widthMHz) MHz block: \(best.block.label)"
        }
    }

    var detail: String {
        var lines: [String] = []
        if let current {
            lines.append("Current \(current.block.label): interference \(Int(current.score)) · \(current.block.regulation.label)")
        }
        lines.append("Best \(best.block.label): interference \(Int(best.score)) · \(best.block.regulation.label)")
        if !best.contenders.isEmpty {
            let names = best.contenders.prefix(3).map { "\($0.displayName) \($0.rssi) dBm" }
            lines.append("Overlapping: " + names.joined(separator: ", ") + (best.contenders.count > 3 ? ", …" : ""))
        }
        if !best.alternatives.isEmpty {
            lines.append("Next: " + best.alternatives.map { "\($0.block.label) (\(Int($0.score)))" }.joined(separator: ", "))
        }
        switch verdict {
        case .keepCurrent: lines.append("Switching would gain little; radar-detection (DFS) blocks are penalised and weather-radar channels excluded.")
        case .switchTo: lines.append("Clearly quieter than the current block. Your own network is excluded from the scores.")
        case .noCurrent: lines.append("Score = overlap × signal above -100 dBm, summed over neighbours, plus a DFS penalty.")
        }
        return lines.joined(separator: "\n")
    }
}

extension SpectrumAnalysis {
    /// A switch must beat the current block by this much to be worth the disruption.
    static func switchThreshold(currentScore: Double) -> Double {
        max(20, currentScore * 0.3)
    }

    static func advise(
        networks: [WiFiNetwork],
        band: WiFiNetwork.Band,
        widthMHz: Int,
        ignoreOwnNetwork: Bool = true
    ) -> ChannelAdvice? {
        let excluded = ignoreOwnNetwork ? ownNetworkIDs(in: networks) : []
        guard let best = recommend(networks: networks, band: band, widthMHz: widthMHz, excluding: excluded) else { return nil }

        guard let connected = networks.first(where: { $0.isConnected && $0.band == band }),
              let currentBlock = band.blocks(widthMHz: widthMHz).first(where: { $0.channels.contains(connected.channel) }),
              let range = currentBlock.frequencyRangeMHz else {
            return ChannelAdvice(verdict: .noCurrent, widthMHz: widthMHz, current: nil, best: best)
        }

        let considered = networks.filter { $0.band == band && !excluded.contains($0.id) }
        let penalty = currentBlock.regulation == .dfs ? dfsPenalty : 0
        let currentScore = congestion(of: considered, on: range) + penalty
        let current = (block: currentBlock, score: currentScore)

        let worthSwitching = currentBlock != best.block
            && currentScore - best.score >= switchThreshold(currentScore: currentScore)
        return ChannelAdvice(
            verdict: worthSwitching ? .switchTo : .keepCurrent,
            widthMHz: widthMHz,
            current: current,
            best: best
        )
    }
}
