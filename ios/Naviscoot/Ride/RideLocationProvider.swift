import CoreLocation
import FerrostarCore
import FerrostarCoreFFI
import UIKit

// Ferrostar's CoreLocationProvider keeps CoreLocation's automatic pausing, which stops updates (and so background guidance) after a wait at a light.
final class RideLocationProvider: NSObject, LocationProviding, CLLocationManagerDelegate {
    weak var delegate: LocationManagingDelegate?
    private(set) var authorizationStatus: CLAuthorizationStatus
    private(set) var lastLocation: UserLocation?
    private(set) var lastHeading: Heading?
    var onCompass: (CompassReading?) -> Void = { _ in }
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

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let orientation = Self.headingOrientation
        if manager.headingOrientation != orientation { manager.headingOrientation = orientation }
        let degrees = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        onCompass(newHeading.headingAccuracy >= 0 ? CompassReading(degrees: degrees, accuracy: newHeading.headingAccuracy) : nil)
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

    // The compass reads the direction the top of the device points at unless it is told how the screen is turned.
    private static var headingOrientation: CLDeviceOrientation {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        switch scene?.interfaceOrientation {
        case .landscapeLeft: return .landscapeRight
        case .landscapeRight: return .landscapeLeft
        case .portraitUpsideDown: return .portraitUpsideDown
        default: return .portrait
        }
    }
}
