import CoreLocation
import Foundation

struct ActiveRide: Codable, Equatable {
    var destination: Destination
    var stops: [Destination]
    let verifiedOnly: Bool
    let avoid: RouteAvoid
    let language: Language
}

enum RouteEdit: Equatable {
    case addStop(Destination)
    case changeDestination(Destination)

    func applied(to ride: ActiveRide) -> ActiveRide {
        var edited = ride
        switch self {
        case let .addStop(stop):
            edited.stops = [stop] + ride.stops
        case let .changeDestination(destination):
            edited.destination = destination
        }
        return edited
    }

    func plan(for ride: ActiveRide, from origin: Coordinate, planner: RoutePlanning) async throws -> (ride: ActiveRide, plan: RoutePlan) {
        let edited = applied(to: ride)
        let plan = try await planner.route(
            from: origin,
            to: edited.destination.coordinate,
            stops: edited.stops.map(\.coordinate),
            avoid: edited.avoid,
            verifiedOnly: edited.verifiedOnly,
            language: edited.language
        )
        return (edited, plan)
    }
}

enum RideEditState: Equatable {
    case planning
    case failed(String)
}

final class ActiveRideStore {
    private let url: URL?

    init(url: URL?) {
        self.url = url
    }

    static var defaultURL: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "active-ride.json")
    }

    func load() -> ActiveRide? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ActiveRide.self, from: data)
    }

    func save(_ ride: ActiveRide) {
        guard let url, let data = try? JSONEncoder().encode(ride) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func clear() {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

struct RerouteTrouble: Equatable {
    private(set) var failures = 0

    var isFailing: Bool { failures > 0 }

    mutating func record(_ outcome: Result<Void, Error>) {
        switch outcome {
        case .success: failures = 0
        case .failure: failures += 1
        }
    }

    mutating func backOnRoute() {
        failures = 0
    }
}

enum LocationTrouble: Equatable {
    case denied
    case reducedAccuracy

    init?(status: CLAuthorizationStatus, accuracy: CLAccuracyAuthorization) {
        switch status {
        case .denied, .restricted: self = .denied
        case .authorizedAlways, .authorizedWhenInUse:
            guard accuracy == .reducedAccuracy else { return nil }
            self = .reducedAccuracy
        default: return nil
        }
    }
}
