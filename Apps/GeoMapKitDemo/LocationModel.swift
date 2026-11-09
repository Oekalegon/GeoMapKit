import CoreLocation
import GeoCore
import Observation

/// Where the user is, for the dot on the map and "centre on me". The kit never starts location; the app does, while the map is shown.
@MainActor
@Observable
final class LocationModel: NSObject, CLLocationManagerDelegate {
    /// The last position, or `nil` before the first one.
    private(set) var coordinate: Coordinate?
    /// Whether the user said no, so the button can say what to do.
    private(set) var denied = false
    /// Whether the user asked to be found: the position is followed while the app is active.
    private(set) var following = false

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    /// Asks for permission the first time (when the user asks to be found), and then follows the position.
    func start() {
        following = true
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            followIfAllowed()
        }
    }

    /// Follows the position when the user allowed it; never asks.
    private func followIfAllowed() {
        switch manager.authorizationStatus {
        case .denied, .restricted:
            denied = true
        case .notDetermined:
            break
        default:
            denied = false
            manager.startUpdatingLocation()
        }
    }

    /// Stops following (when the app is no longer active, to save the battery); `resume()` starts again if the user had asked.
    func stop() { manager.stopUpdatingLocation() }

    func resume() { if following { followIfAllowed() } }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.followIfAllowed() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        let coordinate = Coordinate(latitude: last.coordinate.latitude, longitude: last.coordinate.longitude)
        Task { @MainActor in self.coordinate = coordinate }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // No position yet is not an error for the user; the button simply does nothing until there is one.
    }
}
