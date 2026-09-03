import XCTest
@testable import WiFiSignal

final class BluetoothDecodingTests: XCTestCase {
    func testDecodesAppleFindMy() {
        let decoded = BluetoothDecoding.decodeManufacturerData(Data([0x4C, 0x00, 0x12, 0x19, 0x00]))
        XCTAssertEqual(decoded.manufacturer, "Apple")
        XCTAssertEqual(decoded.kind, "Find My")
    }

    func testDecodesKnownCompanyWithoutKind() {
        let decoded = BluetoothDecoding.decodeManufacturerData(Data([0xE0, 0x00, 0x01]))
        XCTAssertEqual(decoded.manufacturer, "Google")
        XCTAssertNil(decoded.kind)
    }

    func testUnknownCompanyIsHex() {
        let decoded = BluetoothDecoding.decodeManufacturerData(Data([0x34, 0x12]))
        XCTAssertEqual(decoded.manufacturer, "Company 0x1234")
    }

    func testTooShortDataIsIgnored() {
        let decoded = BluetoothDecoding.decodeManufacturerData(Data([0x4C]))
        XCTAssertNil(decoded.manufacturer)
    }

    func testSmoothingMovesTowardNewValue() {
        XCTAssertEqual(BluetoothDecoding.smooth(previous: -60, new: -80), -66)
        XCTAssertEqual(BluetoothDecoding.smooth(previous: -60, new: -60), -60)
    }
}

final class BluetoothDistanceTests: XCTestCase {
    private func device(rssi: Int) -> BluetoothDevice {
        BluetoothDevice(
            id: UUID(), name: nil, rssi: rssi, manufacturer: nil, kind: nil, isConnectable: false,
            serviceCount: 0, txPower: nil, firstSeen: Date(), lastSeen: Date(), packetCount: 1
        )
    }

    func testDistanceAtReferenceIsOneMetre() {
        XCTAssertEqual(device(rssi: -59).estimatedDistanceMeters(referenceRSSIAt1m: -59, pathLossExponent: 2), 1, accuracy: 0.001)
    }

    func testDistanceTenTimesFartherPerTwentyDBAtExponentTwo() {
        XCTAssertEqual(device(rssi: -79).estimatedDistanceMeters(referenceRSSIAt1m: -59, pathLossExponent: 2), 10, accuracy: 0.001)
    }

    func testRadarRadiusIsMonotonicAndClamped() {
        let radar = BluetoothRadarView(devices: [], referenceRSSIAt1m: -59, pathLossExponent: 2)
        let r1 = radar.radius(forDistance: 1, maxRadius: 100)
        let r10 = radar.radius(forDistance: 10, maxRadius: 100)
        let rFar = radar.radius(forDistance: 500, maxRadius: 100)
        XCTAssertLessThan(r1, r10)
        XCTAssertEqual(rFar, 100, accuracy: 0.001)
    }
}
