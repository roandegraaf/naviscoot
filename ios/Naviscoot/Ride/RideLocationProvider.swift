import CoreLocation
import FerrostarCore
import FerrostarCoreFFI

// Ferrostar's CoreLocationProvider keeps CoreLocation's automatic pausing, which stops updates (and so background guidance) after a wait at a light.
final class RideLocationProvider: NSObject, LocationProviding, CLLocationManagerDelegate {
    weak var delegate: LocationManagingDelegate?
    private(set) var authorizationStatus: CLAuthorizationStatus
    private(set) var lastLocation: UserLocation?
    private(set) var lastHeading: Heading?
    private let manager = CLLocationManager()

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.activityType = .otherNavigation
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        lastLocation = manager.location?.userLocation
    }

    func startUpdating() {
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
    }

    func stopUpdating() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    func locationManager(_: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastLocation = locations.last?.userLocation
        delegate?.locationManager(self, didUpdateLocations: locations.map(\.userLocation))
    }

    func locationManager(_: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard let heading = Heading(clHeading: newHeading) else { return }
        lastHeading = heading
        delegate?.locationManager(self, didUpdateHeading: heading)
    }

    func locationManager(_: CLLocationManager, didFailWithError error: Error) {
        delegate?.locationManager(self, didFailWithError: error)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
    }
}
