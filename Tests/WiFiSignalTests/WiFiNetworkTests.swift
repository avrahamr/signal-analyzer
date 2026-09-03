import XCTest
@testable import WiFiSignal

final class WiFiNetworkTests: XCTestCase {
    func testBarsThresholds() {
        XCTAssertEqual(signalBars(forRSSI: -40), 4)
        XCTAssertEqual(signalBars(forRSSI: -55), 3)
        XCTAssertEqual(signalBars(forRSSI: -65), 2)
        XCTAssertEqual(signalBars(forRSSI: -75), 1)
        XCTAssertEqual(signalBars(forRSSI: -90), 0)
    }

    func testHiddenNetworkFallbacks() {
        let n = WiFiNetwork.fixture(ssid: nil, rssi: -60, noise: -90)
        XCTAssertEqual(n.displayName, "Hidden network")
        XCTAssertTrue(n.isHidden)
        XCTAssertEqual(n.snr, 30)
        XCTAssertEqual(n.qualityPercent, 80)
    }

    func testChannelFrequencies() {
        XCTAssertEqual(WiFiNetwork.Band.ghz2.frequencyMHz(forChannel: 6), 2437)
        XCTAssertEqual(WiFiNetwork.Band.ghz2.frequencyMHz(forChannel: 14), 2484)
        XCTAssertEqual(WiFiNetwork.Band.ghz5.frequencyMHz(forChannel: 36), 5180)
        XCTAssertEqual(WiFiNetwork.Band.ghz6.frequencyMHz(forChannel: 1), 5955)
        XCTAssertNil(WiFiNetwork.Band.unknown.frequencyMHz(forChannel: 1))
        XCTAssertEqual(WiFiNetwork.Band.ghz5.channel(forFrequencyMHz: 5180), 36)
    }

    func testFrequencyRangeUsesWidth() {
        let n = WiFiNetwork.fixture(channel: 36, band: .ghz5, widthMHz: 80)
        XCTAssertEqual(n.frequencyRangeMHz, 5140...5220)
    }

    func testDistanceEstimateGrowsAsSignalDrops() {
        let near = WiFiNetwork.fixture(rssi: -40)
        let far = WiFiNetwork.fixture(rssi: -70)
        let dNear = near.estimatedDistanceMeters(referenceRSSIAt1m: -40, pathLossExponent: 3)
        let dFar = far.estimatedDistanceMeters(referenceRSSIAt1m: -40, pathLossExponent: 3)
        XCTAssertEqual(dNear, 1, accuracy: 0.001)
        XCTAssertEqual(dFar, 10, accuracy: 0.001)
    }
}

extension WiFiNetwork {
    static func fixture(
        ssid: String? = "Test",
        rssi: Int = -60,
        noise: Int = -90,
        channel: Int = 6,
        band: Band = .ghz2,
        widthMHz: Int = 20
    ) -> WiFiNetwork {
        WiFiNetwork(
            id: "fixture", ssid: ssid, bssid: nil, rssi: rssi, noise: noise, channel: channel,
            band: band, widthMHz: widthMHz, security: "WPA2", securities: ["WPA2"], isConnected: false,
            countryCode: nil, beaconIntervalMs: 100, isAdHoc: false, informationElements: nil
        )
    }
}
