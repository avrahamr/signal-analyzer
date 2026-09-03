import AppKit
import Combine
import CoreLocation
import Foundation

/// CoreWLAN returns nil SSIDs/BSSIDs unless the app has Location access, so
/// we ask for it up front and surface the state in the UI.
@MainActor
final class LocationPermission: NSObject, ObservableObject {
    @Published private(set) var status: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        status = manager.authorizationStatus
    }

    var isAuthorized: Bool {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse: return true
        default: return false
        }
    }

    var statusDescription: String {
        switch status {
        case .notDetermined: return "Location access not requested — network names will be hidden."
        case .restricted: return "Location access is restricted on this Mac."
        case .denied: return "Location access denied — network names are hidden."
        case .authorizedAlways, .authorizedWhenInUse: return "Location access granted."
        @unknown default: return "Unknown Location permission state."
        }
    }

    func request() {
        manager.requestWhenInUseAuthorization()
    }

    func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!
        NSWorkspace.shared.open(url)
    }
}

extension LocationPermission: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let newStatus = manager.authorizationStatus
        Task { @MainActor in self.status = newStatus }
    }
}
