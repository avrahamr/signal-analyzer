import SwiftUI

/// Devices as dots on distance rings around this Mac. Radius is the estimated
/// distance on a log scale; the angle is derived from the device ID purely to
/// spread dots apart, since BLE gives no direction.
struct BluetoothRadarView: View {
    let devices: [BluetoothDevice]
    let referenceRSSIAt1m: Int
    let pathLossExponent: Double

    @State private var hoveredID: UUID?
    @State private var pinnedID: UUID?
    private let hitRadius: CGFloat = 12

    private var activeID: UUID? { hoveredID ?? pinnedID }

    private let rings: [Double] = [1, 2, 5, 10, 20]
    private let maxDistance = 30.0

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2 + 6)
            let maxRadius = max(min(geo.size.width, geo.size.height) / 2 - 36, 40)
            ZStack {
                SpectrumView.background

                ForEach(rings, id: \.self) { distance in
                    let r = radius(forDistance: distance, maxRadius: maxRadius)
                    Circle()
                        .stroke(.white.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .frame(width: r * 2, height: r * 2)
                        .position(center)
                    Text(distance < 10 ? "\(Int(distance)) m" : "\(Int(distance)) m")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.55))
                        .position(x: center.x + 4 + 14, y: center.y - r + 9)
                }

                Path { path in
                    path.move(to: CGPoint(x: center.x - maxRadius, y: center.y))
                    path.addLine(to: CGPoint(x: center.x + maxRadius, y: center.y))
                    path.move(to: CGPoint(x: center.x, y: center.y - maxRadius))
                    path.addLine(to: CGPoint(x: center.x, y: center.y + maxRadius))
                }
                .stroke(.white.opacity(0.08), lineWidth: 1)

                Image(systemName: "laptopcomputer")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .position(center)

                ForEach(devices) { device in
                    let point = position(for: device, center: center, maxRadius: maxRadius)
                    let color = SpectrumAnalysis.color(forNetworkID: device.id.uuidString)
                    let dimmed = activeID != nil && activeID != device.id
                    let size: CGFloat = device.name == nil ? 9 : 13

                    Circle()
                        .fill(color.opacity(dimmed ? 0.3 : freshness(device)))
                        .overlay(Circle().stroke(.white.opacity(dimmed ? 0.2 : 0.8), lineWidth: 1))
                        .frame(width: size, height: size)
                        .position(point)

                    if device.name != nil {
                        Text(device.displayName)
                            .font(.caption)
                            .foregroundStyle(color.opacity(dimmed ? 0.35 : 1))
                            .lineLimit(1)
                            .shadow(color: .black.opacity(0.8), radius: 2)
                            .position(x: point.x, y: point.y - 13)
                    }
                }

                if let id = activeID, let device = devices.first(where: { $0.id == id }) {
                    tooltip(for: device, at: position(for: device, center: center, maxRadius: maxRadius), in: geo.size)
                        .allowsHitTesting(false)
                }

                Text("Ring = estimated distance (log scale). Angle is arbitrary; Bluetooth gives no direction.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
                    .position(x: geo.size.width / 2, y: geo.size.height - 12)

                if devices.isEmpty {
                    Text("No devices yet")
                        .foregroundStyle(.white.opacity(0.6))
                        .position(x: center.x, y: center.y - 30)
                }
            }
            .animation(.easeInOut(duration: 1.2), value: devices)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoveredID = nearestDevice(to: location, center: center, maxRadius: maxRadius)
                case .ended:
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

    /// Device whose dot is within `hitRadius` of the pointer, nearest first.
    private func nearestDevice(to location: CGPoint, center: CGPoint, maxRadius: CGFloat) -> UUID? {
        var best: (id: UUID, distance: CGFloat)?
        for device in devices {
            let point = position(for: device, center: center, maxRadius: maxRadius)
            let distance = hypot(point.x - location.x, point.y - location.y)
            if distance <= hitRadius, best == nil || distance < best!.distance {
                best = (device.id, distance)
            }
        }
        return best?.id
    }

    func radius(forDistance distance: Double, maxRadius: CGFloat) -> CGFloat {
        let clamped = min(max(distance, 0), maxDistance)
        return CGFloat(log10(1 + clamped) / log10(1 + maxDistance)) * maxRadius
    }

    func angle(for id: UUID) -> Double {
        // Hash all 16 bytes so IDs that share a prefix still spread out.
        var hash: UInt32 = 2_166_136_261
        withUnsafeBytes(of: id.uuid) { bytes in
            for byte in bytes { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
        }
        let scrambled = (hash &* 2_654_435_761) >> 8
        return Double(scrambled & 0xFFFF) / 65536 * 2 * .pi
    }

    private func position(for device: BluetoothDevice, center: CGPoint, maxRadius: CGFloat) -> CGPoint {
        let distance = device.estimatedDistanceMeters(referenceRSSIAt1m: referenceRSSIAt1m, pathLossExponent: pathLossExponent)
        let r = radius(forDistance: distance, maxRadius: maxRadius)
        let a = angle(for: device.id)
        return CGPoint(x: center.x + r * CGFloat(cos(a)), y: center.y + r * CGFloat(sin(a)))
    }

    /// Recently heard devices are solid; ones about to expire fade.
    private func freshness(_ device: BluetoothDevice) -> Double {
        let age = Date().timeIntervalSince(device.lastSeen)
        return age < 3 ? 1 : max(0.4, 1 - (age - 3) / 20)
    }

    private func tooltip(for device: BluetoothDevice, at point: CGPoint, in size: CGSize) -> some View {
        let color = SpectrumAnalysis.color(forNetworkID: device.id.uuidString)
        let distance = device.estimatedDistanceMeters(referenceRSSIAt1m: referenceRSSIAt1m, pathLossExponent: pathLossExponent)
        let card = VStack(alignment: .leading, spacing: 3) {
            Text(device.displayName).font(.callout.bold()).foregroundStyle(color)
            if let manufacturer = device.manufacturer { Text(manufacturer + (device.kind.map { " · \($0)" } ?? "")) }
            Text("\(device.rssi) dBm · ~\(distance.formatted(.number.precision(.fractionLength(distance < 10 ? 1 : 0)))) m")
            Text("\(device.packetCount) packets · \(device.isConnectable ? "connectable" : "not connectable")")
            Text(device.shortID).font(.caption2.monospaced()).foregroundStyle(.white.opacity(0.7))
        }
        .font(.caption)
        .foregroundStyle(.white)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.85)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(color.opacity(0.7), lineWidth: 1))
        .fixedSize()

        let width: CGFloat = 220, height: CGFloat = 90
        let xx = min(max(point.x + 16 + width / 2, width / 2 + 8), size.width - width / 2 - 8)
        let yy = min(max(point.y - 10 - height / 2, height / 2 + 8), size.height - height / 2 - 8)
        return card.position(x: xx, y: yy)
    }
}
