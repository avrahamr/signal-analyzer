import XCTest
@testable import WiFiSignal

final class InformationElementsTests: XCTestCase {
    private func element(_ id: UInt8, _ payload: [UInt8]) -> [UInt8] {
        [id, UInt8(payload.count)] + payload
    }

    func testParsesElementsAndStopsAtTruncation() {
        let bytes = element(0, Array("Home".utf8)) + element(3, [6]) + [45, 20, 0x01]
        let parsed = InformationElement.parse(Data(bytes))
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[0].name, "SSID")
        XCTAssertEqual(String(decoding: parsed[0].payload, as: UTF8.self), "Home")
        XCTAssertEqual(parsed[1].payload, Data([6]))
    }

    func testExtensionElementUsesFirstPayloadByte() {
        let bytes = element(255, [35] + [UInt8](repeating: 0, count: 20))
        let parsed = InformationElement.parse(Data(bytes))
        XCTAssertEqual(parsed.first?.extensionID, 35)
        XCTAssertEqual(parsed.first?.name, "HE Capabilities")
        XCTAssertEqual(parsed.first?.payload.count, 20)
    }

    func testDetectsWiFi6WithTwoStreamsAndBSSLoad() {
        // HT caps: 2 info + 1 ampdu + MCS set with 2 stream bytes set.
        let ht = element(45, [0xEF, 0x19, 0x1B, 0xFF, 0xFF] + [UInt8](repeating: 0, count: 21))
        // HE caps: 6 MAC + 11 PHY + rx map 0xFFFA -> streams 0,1 supported (values 2,2), rest 3.
        let he = element(255, [35] + [UInt8](repeating: 0, count: 17) + [0xFA, 0xFF])
        let bssLoad = element(11, [0x0C, 0x00, 0x80, 0x00, 0x00])
        let caps = NetworkCapabilities(informationElements: Data(ht + he + bssLoad), band: .ghz5)

        XCTAssertEqual(caps.standards, ["802.11n", "802.11ax"])
        XCTAssertEqual(caps.generation, "Wi-Fi 6 (802.11ax)")
        XCTAssertEqual(caps.maxSpatialStreams, 2)
        XCTAssertEqual(caps.stationCount, 12)
        XCTAssertEqual(caps.channelUtilizationPercent, 50)
    }

    func testSixGHzIsLabelled6E() {
        let he = element(255, [35] + [UInt8](repeating: 0, count: 19))
        let caps = NetworkCapabilities(informationElements: Data(he), band: .ghz6)
        XCTAssertEqual(caps.generation, "Wi-Fi 6E (802.11ax)")
    }

    func testLegacyBOnlyRates() {
        let rates = element(1, [0x82, 0x84, 0x8B, 0x96]) // 1, 2, 5.5, 11 basic
        let caps = NetworkCapabilities(informationElements: Data(rates), band: .ghz2)
        XCTAssertEqual(caps.standards, ["802.11b"])
        XCTAssertEqual(caps.maxSupportedRateMbps, 11)
    }

    func testParsesRSNWithSAEAndMFP() {
        let rsn = element(48, [
            0x01, 0x00,                         // version 1
            0x00, 0x0F, 0xAC, 0x04,             // group CCMP
            0x02, 0x00,                         // 2 pairwise
            0x00, 0x0F, 0xAC, 0x04,             // CCMP
            0x00, 0x0F, 0xAC, 0x09,             // GCMP-256
            0x02, 0x00,                         // 2 AKMs
            0x00, 0x0F, 0xAC, 0x02,             // PSK
            0x00, 0x0F, 0xAC, 0x08,             // SAE
            0xC0, 0x00,                         // MFPR + MFPC
        ])
        let caps = NetworkCapabilities(informationElements: Data(rsn), band: .ghz2)
        let info = caps.rsn
        XCTAssertEqual(info?.groupCipher, "CCMP-128 (AES)")
        XCTAssertEqual(info?.pairwiseCiphers, ["CCMP-128 (AES)", "GCMP-256"])
        XCTAssertEqual(info?.authenticationSuites, ["PSK", "SAE (WPA3)"])
        XCTAssertEqual(info?.managementFrameProtection, "Required")
    }

    func testVendorElementsDetectWPSAndWMM() {
        let wps = element(221, [0x00, 0x50, 0xF2, 0x04, 0x10, 0x4A])
        let wmm = element(221, [0x00, 0x50, 0xF2, 0x02, 0x01, 0x01])
        let apple = element(221, [0x00, 0x17, 0xF2, 0x0A])
        let caps = NetworkCapabilities(informationElements: Data(wps + wmm + apple), band: .ghz2)
        XCTAssertTrue(caps.supportsWPS)
        XCTAssertTrue(caps.supportsWMM)
        XCTAssertEqual(caps.vendors, ["Microsoft (WPA/WMM/WPS)", "Apple"])
    }

    func testRoamingFlags() {
        let mobility = element(54, [0x01, 0x02, 0x01])
        let rm = element(70, [0x02, 0x00, 0x00, 0x00, 0x00])
        let extCaps = element(127, [0x00, 0x00, 0x08])
        let caps = NetworkCapabilities(informationElements: Data(mobility + rm + extCaps), band: .ghz5)
        XCTAssertEqual(caps.roamingSummary, "802.11k/v/r")
    }
}
