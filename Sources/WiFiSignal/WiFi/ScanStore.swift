import AppKit
import Combine
import CoreWLAN
import Foundation
import UniformTypeIdentifiers

/// Owns scan results, per-network history and the auto-refresh timer.
/// Everything published here is read by SwiftUI, so it lives on the main actor.
@MainActor
final class ScanStore: ObservableObject {
    @Published private(set) var networks: [WiFiNetwork] = []
    @Published private(set) var interfaceStatus: InterfaceStatus?
    @Published private(set) var lastScan: Date?
    @Published private(set) var isScanning = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var history: [String: [RSSISample]] = [:]
    @Published private(set) var presence: [String: Presence] = [:]

    /// Feedback from join/disconnect actions.
    @Published private(set) var actionMessage: String?
    @Published private(set) var isPerformingAction = false

    let settings: AppSettings
    private var raw: RawNetworkBox?
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init(settings: AppSettings = .shared) {
        self.settings = settings
        settings.$autoRefresh
            .combineLatest(settings.$refreshInterval)
            .dropFirst()
            .sink { [weak self] _, _ in self?.scheduleTimer() }
            .store(in: &cancellables)
    }

    var interfaceName: String { interfaceStatus?.name ?? "" }

    func start() {
        refresh()
        scheduleTimer()
    }

    func refresh() {
        guard !isScanning else { return }
        isScanning = true
        Task.detached(priority: .userInitiated) { [weak self] in
            let result: Result<ScanSnapshot, Error>
            do {
                result = .success(try WiFiScanner.scan())
            } catch {
                result = .failure(error)
            }
            await self?.apply(result)
        }
    }

    func network(withID id: String?) -> WiFiNetwork? {
        guard let id else { return nil }
        return networks.first { $0.id == id }
    }

    func rawNetwork(withID id: String) -> CWNetwork? {
        raw?.byID[id]
    }

    /// RSSI history for the strongest `limit` networks currently in range.
    func historySeries(limit: Int) -> [HistorySeries] {
        networks.prefix(limit).compactMap { n in
            guard let samples = history[n.id], !samples.isEmpty else { return nil }
            return HistorySeries(id: n.id, label: n.chartLabel, samples: samples)
        }
    }

    // MARK: - Actions

    func join(id: String, password: String) {
        guard let network = rawNetwork(withID: id) else {
            actionMessage = ScanError.networkGone.localizedDescription
            return
        }
        let box = RawNetworkBox([id: network])
        runAction("Joined \(network.ssid ?? "network").") {
            guard let target = box.byID[id] else { throw ScanError.networkGone }
            try WiFiScanner.join(target, password: password)
        }
    }

    func disconnect() {
        runAction("Disconnected.") { try WiFiScanner.disconnect() }
    }

    func clearActionMessage() { actionMessage = nil }

    private func runAction(_ successMessage: String, _ work: @escaping @Sendable () throws -> Void) {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        actionMessage = nil
        Task.detached(priority: .userInitiated) { [weak self] in
            var message = successMessage
            do { try work() } catch { message = error.localizedDescription }
            await self?.finishAction(message: message)
        }
    }

    private func finishAction(message: String) {
        isPerformingAction = false
        actionMessage = message
        refresh()
    }

    /// Writes the current scan to a CSV file chosen by the user.
    func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "wifi-scan.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        func quote(_ s: String?) -> String { "\"" + (s ?? "").replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var lines = ["ssid,bssid,rssi_dbm,noise_dbm,snr_db,channel,band,width_mhz,security,connected,country"]
        for n in networks {
            lines.append([
                quote(n.ssid), quote(n.bssid), "\(n.rssi)", "\(n.noise)", "\(n.snr)", "\(n.channel)",
                quote(n.band.rawValue), "\(n.widthMHz)", quote(n.security), n.isConnected ? "yes" : "no",
                quote(n.countryCode),
            ].joined(separator: ","))
        }
        do {
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            actionMessage = "Exported \(networks.count) networks to \(url.lastPathComponent)."
        } catch {
            actionMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Internals

    private func apply(_ result: Result<ScanSnapshot, Error>) {
        isScanning = false
        switch result {
        case .success(let snapshot):
            networks = snapshot.networks
            interfaceStatus = snapshot.interfaceStatus
            lastScan = snapshot.timestamp
            raw = snapshot.raw
            errorMessage = nil
            record(snapshot)
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func record(_ snapshot: ScanSnapshot) {
        let limit = max(settings.historyLimit, 10)
        for n in snapshot.networks {
            var samples = history[n.id, default: []]
            samples.append(RSSISample(date: snapshot.timestamp, rssi: n.rssi))
            if samples.count > limit { samples.removeFirst(samples.count - limit) }
            history[n.id] = samples

            if var seen = presence[n.id] {
                seen.lastSeen = snapshot.timestamp
                seen.scanCount += 1
                presence[n.id] = seen
            } else {
                presence[n.id] = Presence(firstSeen: snapshot.timestamp, lastSeen: snapshot.timestamp, scanCount: 1)
            }
        }
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = nil
        guard settings.autoRefresh else { return }
        timer = Timer.scheduledTimer(withTimeInterval: settings.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }
}
