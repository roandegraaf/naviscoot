import CoreLocation

@MainActor
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var coordinate: Coordinate?
    @Published private(set) var denied = false
    @Published private(set) var trouble: LocationTrouble?
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func start() {
        if let origin = RideOptions.current.simulatedOrigin {
            coordinate = origin
            return
        }
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    nonisolated func locationManager(_: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        let coordinate = Coordinate(last.coordinate)
        Task { @MainActor in
            guard RideOptions.current.simulatedOrigin == nil else { return }
            self.coordinate = coordinate
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        let accuracy = manager.accuracyAuthorization
        Task { @MainActor in
            self.denied = status == .denied || status == .restricted
            self.trouble = LocationTrouble(status: status, accuracy: accuracy)
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                self.manager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_: CLLocationManager, didFailWithError _: Error) {}
}
