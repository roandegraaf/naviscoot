import CoreLocation
import FerrostarCore
import FerrostarCoreFFI
import Foundation

enum RideError: Error, Equatable {
    case noDestination
}

final class PlanBook: @unchecked Sendable {
    private let lock = NSLock()
    private var plans: [RoutePlan] = []

    func store(_ plan: RoutePlan) {
        lock.lock()
        defer { lock.unlock() }
        plans.append(plan)
        if plans.count > 8 {
            plans.removeFirst(plans.count - 8)
        }
    }

    func plan(for route: Route) -> RoutePlan? {
        lock.lock()
        defer { lock.unlock() }
        return plans.last { $0.route == route }
    }
}

protocol RoutePlanning {
    func route(from origin: Coordinate, to destination: Coordinate, verifiedOnly: Bool) async throws -> RoutePlan
}

extension NaviscootClient: RoutePlanning {}

final class NaviscootRouteProvider: CustomRouteProvider {
    let planner: RoutePlanning
    let verifiedOnly: Bool
    let book: PlanBook

    init(planner: RoutePlanning, verifiedOnly: Bool, book: PlanBook) {
        self.planner = planner
        self.verifiedOnly = verifiedOnly
        self.book = book
    }

    func getRoutes(userLocation: UserLocation, waypoints: [Waypoint]) async throws -> [Route] {
        guard let destination = waypoints.last else { throw RideError.noDestination }
        let plan = try await planner.route(
            from: Coordinate(userLocation.coordinates),
            to: Coordinate(destination.coordinate),
            verifiedOnly: verifiedOnly
        )
        book.store(plan)
        return [plan.route]
    }
}

final class RideNavigationDelegate: FerrostarCoreDelegate {
    var onReroute: (Route) -> Void = { _ in }

    func core(_: FerrostarCore, didStartWith _: Route) {}

    func core(_: FerrostarCore, correctiveActionForDeviation _: DeviationKind, remainingWaypoints waypoints: [Waypoint]) -> CorrectiveAction {
        .getNewRoutes(waypoints: waypoints)
    }

    func core(_: FerrostarCore, loadedAlternateRoutes routes: [Route]) {
        guard let route = routes.first else { return }
        let onReroute = onReroute
        DispatchQueue.main.async { onReroute(route) }
    }
}

struct RideOptions {
    let simulate: Bool
    let simulatedSpeedKmh: Double
    let simulatedOrigin: Coordinate?
    let tickInterval: TimeInterval

    static let current = RideOptions(defaults: .standard)

    init(simulate: Bool, simulatedSpeedKmh: Double = 45, simulatedOrigin: Coordinate? = nil, tickInterval: TimeInterval = 0.5) {
        self.simulate = simulate
        self.simulatedSpeedKmh = simulatedSpeedKmh
        self.simulatedOrigin = simulatedOrigin
        self.tickInterval = tickInterval
    }

    init(defaults: UserDefaults) {
        #if targetEnvironment(simulator)
            let simulateByDefault = true
        #else
            let simulateByDefault = false
        #endif
        let simulate = defaults.object(forKey: "NaviscootSimulateRide") == nil
            ? simulateByDefault
            : defaults.bool(forKey: "NaviscootSimulateRide")
        let speed = defaults.double(forKey: "NaviscootSimSpeedKmh")
        let origin = defaults.string(forKey: "NaviscootSimOrigin").flatMap(Self.parseCoordinate)
        self.init(simulate: simulate, simulatedSpeedKmh: speed > 0 ? speed : 45, simulatedOrigin: simulate ? origin : nil)
    }

    static func parseCoordinate(_ text: String) -> Coordinate? {
        let parts = text.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2 else { return nil }
        return Coordinate(lat: parts[0], lon: parts[1])
    }

    static let navigationConfig = SwiftNavigationControllerConfig(
        waypointAdvance: .waypointWithinRange(100),
        stepAdvanceCondition: stepAdvanceDistanceEntryAndExit(
            distanceToEndOfStep: 30,
            distanceAfterEndOfStep: 5,
            minimumHorizontalAccuracy: 32
        ),
        arrivalStepAdvanceCondition: stepAdvanceDistanceToEndOfStep(distance: 10, minimumHorizontalAccuracy: 32),
        routeDeviationTracking: .staticThreshold(minimumHorizontalAccuracy: 25, maxAcceptableDeviation: 40),
        snappedLocationCourseFiltering: .snapToRoute
    )
}

final class RideSimulator: LocationProviding {
    weak var delegate: LocationManagingDelegate?
    let authorizationStatus: CLAuthorizationStatus = .authorizedAlways
    private(set) var lastLocation: UserLocation?
    let lastHeading: Heading? = nil

    var speedMps: Double
    let tickInterval: TimeInterval
    static let detourOffsetM: Double = 150

    private var geometry = RouteGeometry(points: [])
    private var alongM: Double = 0
    private var detourM: Double = 0
    private var task: Task<Void, Never>?

    init(speedKmh: Double, tickInterval: TimeInterval) {
        speedMps = speedKmh / 3.6
        self.tickInterval = tickInterval
    }

    func follow(_ route: Route) {
        geometry = RouteGeometry(route: route)
        alongM = 0
        detourM = 0
        lastLocation = location()
    }

    func detour() {
        detourM = Self.detourOffsetM
    }

    func startUpdating() {
        task?.cancel()
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                try? await Task.sleep(nanoseconds: UInt64(self.tickInterval * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self.tick()
            }
        }
    }

    func stopUpdating() {
        task?.cancel()
        task = nil
    }

    private func tick() {
        guard geometry.points.count >= 2 else { return }
        alongM = min(geometry.lengthM, alongM + speedMps * tickInterval)
        let location = location()
        lastLocation = location
        delegate?.locationManager(self, didUpdateLocations: [location])
    }

    private func location() -> UserLocation {
        var (coordinate, bearing) = geometry.position(atM: alongM)
        if detourM > 0 {
            coordinate = Geo.offset(coordinate, bearing: bearing + 90, distanceM: detourM)
        }
        let moving = alongM < geometry.lengthM
        return UserLocation(
            coordinates: GeographicCoordinate(lat: coordinate.lat, lng: coordinate.lon),
            horizontalAccuracy: 5,
            courseOverGround: CourseOverGround(degrees: UInt16(bearing.rounded()) % 360, accuracy: 5),
            timestamp: Date(),
            speed: Speed(value: moving ? speedMps : 0, accuracy: 1)
        )
    }
}
