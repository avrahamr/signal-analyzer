import XCTest
@testable import WiFiSignal

final class SpectrumAnalysisTests: XCTestCase {
    func testOverlapIsFullOnSameChannelAndZeroFarAway() {
        let n = WiFiNetwork.fixture(channel: 6, band: .ghz2, widthMHz: 20)
        XCTAssertEqual(SpectrumAnalysis.overlap(of: n, onChannelFrequency: 2437), 1, accuracy: 0.001)
        XCTAssertEqual(SpectrumAnalysis.overlap(of: n, onChannelFrequency: 2412), 0)
        XCTAssertEqual(SpectrumAnalysis.overlap(of: n, onChannelFrequency: 2447), 0.5, accuracy: 0.001)
    }

    func testRegulation() {
        XCTAssertEqual(WiFiNetwork.Band.ghz5.regulation(forChannel: 48), .unrestricted)
        XCTAssertEqual(WiFiNetwork.Band.ghz5.regulation(forChannel: 52), .dfs)
        XCTAssertEqual(WiFiNetwork.Band.ghz5.regulation(forChannel: 120), .dfsWeather)
        XCTAssertEqual(WiFiNetwork.Band.ghz5.regulation(forChannel: 149), .unrestricted)
        XCTAssertEqual(WiFiNetwork.Band.ghz2.regulation(forChannel: 6), .unrestricted)
    }

    func testFiveGHzBlocksFollowChannelisation() {
        let b160 = WiFiNetwork.Band.ghz5.blocks(widthMHz: 160).map(\.channels)
        XCTAssertEqual(b160, [[36, 40, 44, 48, 52, 56, 60, 64], [100, 104, 108, 112, 116, 120, 124, 128]])
        let b80 = WiFiNetwork.Band.ghz5.blocks(widthMHz: 80).map(\.label)
        XCTAssertEqual(b80, ["36–48", "52–64", "100–112", "116–128", "132–144", "149–161"])
        XCTAssertEqual(WiFiNetwork.Band.ghz5.blocks(widthMHz: 20).count, 25)
    }

    func testTwoPointFourBlocks() {
        XCTAssertEqual(WiFiNetwork.Band.ghz2.blocks(widthMHz: 20).count, 13)
        XCTAssertEqual(WiFiNetwork.Band.ghz2.blocks(widthMHz: 40).first?.channels, [1, 5])
    }

    func testLeastCrowdedAvoidsOccupiedChannels() {
        let networks = [
            WiFiNetwork.fixture(ssid: "A", rssi: -40, channel: 1),
            WiFiNetwork.fixture(ssid: "B", rssi: -45, channel: 6),
        ]
        XCTAssertEqual(SpectrumAnalysis.leastCrowdedChannel(networks: networks, band: .ghz2), 11)
    }

    func testLeastCrowdedPrefersNonOverlappingChannelOnTie() {
        XCTAssertEqual(SpectrumAnalysis.leastCrowdedChannel(networks: [], band: .ghz2), 1)
    }

    func testWeatherRadarBlocksAreNeverRecommendedAndDFSIsPenalised() {
        // Neighbours fill 36–48 and 149–161; the empty non-weather DFS blocks remain.
        let networks = [
            WiFiNetwork.fixture(ssid: "A", rssi: -40, channel: 36, band: .ghz5, widthMHz: 80),
            WiFiNetwork.fixture(ssid: "B", rssi: -40, channel: 149, band: .ghz5, widthMHz: 80),
        ]
        let best = SpectrumAnalysis.recommend(networks: networks, band: .ghz5, widthMHz: 80)
        XCTAssertEqual(best?.block.label, "52–64")
        XCTAssertEqual(best?.score, SpectrumAnalysis.dfsPenalty)
        XCTAssertFalse(best!.alternatives.contains { $0.block.label == "116–128" })
    }

    func testNonDFSWinsWhenEquallyQuiet() {
        let best = SpectrumAnalysis.recommend(networks: [], band: .ghz5, widthMHz: 160)
        XCTAssertEqual(best?.block.label, "36–64")
    }

    func testOwnNetworkDetectionByMACSimilarity() {
        let own = WiFiNetwork(
            id: "da:d8:e5:b2:e4:3e", ssid: "Mine", bssid: "DA:D8:E5:B2:E4:3E", rssi: -35, noise: -90, channel: 48,
            band: .ghz5, widthMHz: 160, security: "WPA2", securities: [], isConnected: true,
            countryCode: nil, beaconIntervalMs: 100, isAdHoc: false, informationElements: nil
        )
        let sibling = WiFiNetwork(
            id: "da:d8:e5:b2:e4:3f", ssid: nil, bssid: "DA:D8:E5:B2:E4:3F", rssi: -36, noise: -90, channel: 48,
            band: .ghz5, widthMHz: 160, security: "WPA2", securities: [], isConnected: false,
            countryCode: nil, beaconIntervalMs: 100, isAdHoc: false, informationElements: nil
        )
        let neighbour = WiFiNetwork(
            id: "00:11:22:33:44:55", ssid: "Smith", bssid: "00:11:22:33:44:55", rssi: -55, noise: -90, channel: 48,
            band: .ghz5, widthMHz: 80, security: "WPA2", securities: [], isConnected: false,
            countryCode: nil, beaconIntervalMs: 100, isAdHoc: false, informationElements: nil
        )
        let ownIDs = SpectrumAnalysis.ownNetworkIDs(in: [own, sibling, neighbour])
        XCTAssertEqual(ownIDs, [own.id, sibling.id])
    }

    func testAdviceKeepsCurrentWhenGainIsSmall() {
        let own = WiFiNetwork(
            id: "own", ssid: "Mine", bssid: "DA:D8:E5:B2:E4:3E", rssi: -35, noise: -90, channel: 48,
            band: .ghz5, widthMHz: 160, security: "WPA2", securities: [], isConnected: true,
            countryCode: nil, beaconIntervalMs: 100, isAdHoc: false, informationElements: nil
        )
        let weak = WiFiNetwork.fixture(ssid: "Far", rssi: -90, channel: 40, band: .ghz5, widthMHz: 20)
        let advice = SpectrumAnalysis.advise(networks: [own, weak], band: .ghz5, widthMHz: 160)
        XCTAssertEqual(advice?.verdict, .keepCurrent)
        XCTAssertEqual(advice?.highlightedBlock.label, "36–64")
        XCTAssertTrue(advice!.headline.hasPrefix("Keep Auto"))
    }

    func testAdviceSuggestsSwitchWhenCurrentIsCrowded() {
        let own = WiFiNetwork(
            id: "own", ssid: "Mine", bssid: "DA:D8:E5:B2:E4:3E", rssi: -35, noise: -90, channel: 36,
            band: .ghz5, widthMHz: 80, security: "WPA2", securities: [], isConnected: true,
            countryCode: nil, beaconIntervalMs: 100, isAdHoc: false, informationElements: nil
        )
        let loud = WiFiNetwork.fixture(ssid: "Neighbour", rssi: -40, channel: 36, band: .ghz5, widthMHz: 80)
        let advice = SpectrumAnalysis.advise(networks: [own, loud], band: .ghz5, widthMHz: 80)
        XCTAssertEqual(advice?.verdict, .switchTo)
        XCTAssertEqual(advice?.best.block.label, "149–161")
    }

    func testColorIsStablePerID() {
        XCTAssertEqual(SpectrumAnalysis.color(forNetworkID: "aa:bb"), SpectrumAnalysis.color(forNetworkID: "aa:bb"))
        XCTAssertNotEqual(SpectrumAnalysis.color(forNetworkID: "aa:bb"), SpectrumAnalysis.color(forNetworkID: "cc:dd"))
    }
}
