import Foundation
import MapKit
import Observation

struct ParkedScooter: Codable, Equatable {
    let coordinate: Coordinate
    let at: Date

    func subtitle(now: Date, language: Language = .current) -> String {
        let elapsed = now.timeIntervalSince(at)
        guard elapsed >= 60 else { return Strings.tr("scooter.parked.now", language: language) }
        return Strings.format("scooter.parked.ago", Format.duration(seconds: elapsed, language: language), language: language)
    }
}

// Riders often switch the scooter off at the destination before tapping Stop, so a loss shortly before the ride ends still counts.
enum ParkingRule {
    static let beforeRideEndGraceS: TimeInterval = 120

    static func recordsLoss(rideActive: Bool) -> Bool {
        !rideActive
    }

    static func recordsPendingLoss(lostAt: Date, rideEndedAt: Date) -> Bool {
        (0 ... beforeRideEndGraceS).contains(rideEndedAt.timeIntervalSince(lostAt))
    }
}

@MainActor
@Observable
final class ParkedScooterStore {
    static let shared = ParkedScooterStore(url: defaultURL)

    private(set) var parked: ParkedScooter?
    @ObservationIgnored private let url: URL?

    init(url: URL?) {
        self.url = url
        parked = url.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(ParkedScooter.self, from: $0) }
    }

    static var defaultURL: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "parked-scooter.json")
    }

    func record(_ coordinate: Coordinate, at date: Date) {
        let spot = ParkedScooter(coordinate: coordinate, at: date)
        parked = spot
        guard let url, let data = try? JSONEncoder().encode(spot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func clear() {
        guard parked != nil else { return }
        parked = nil
        if let url { try? FileManager.default.removeItem(at: url) }
    }

    func openWalkingDirections() {
        guard let parked else { return }
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: parked.coordinate.lat, longitude: parked.coordinate.lon)))
        item.name = Strings.scooterParkedTitle
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }
}
