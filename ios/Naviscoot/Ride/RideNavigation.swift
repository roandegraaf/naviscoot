import CoreLocation
import FerrostarCore
import FerrostarCoreFFI
import Foundation

enum RideError: Error, Equatable {
    case noDestination
}

final class PlanBook: @unchecked Sendable {
    private let lock = NSLock()
    private var plans: [(generation: Int, plan: RoutePlan)] = []
    private var current = 0

    var generation: Int {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func startNewGeneration() {
        lock.lock()
        defer { lock.unlock() }
        current += 1
    }

    func store(_ plan: RoutePlan, generation: Int? = nil) {
        lock.lock()
        defer { lock.unlock() }
        plans.append((generation ?? current, plan))
        if plans.count > 8 {
            plans.removeFirst(plans.count - 8)
        }
    }

    func plan(for route: Route) -> RoutePlan? {
        lock.lock()
        defer { lock.unlock() }
        return plans.last { $0.generation == current && $0.plan.route == route }?.plan
    }
}

protocol RoutePlanning {
    func route(from origin: Coordinate, to destination: Coordinate, stops: [Coordinate], avoid: RouteAvoid, verifiedOnly: Bool, language: Language) async throws -> RoutePlan
}

extension NaviscootClient: RoutePlanning {}

final class NaviscootRouteProvider: CustomRouteProvider {
    let planner: RoutePlanning
    let verifiedOnly: Bool
    let avoid: RouteAvoid
    let language: Language
    let book: PlanBook
    var onOutcome: (Result<Void, Error>) -> Void = { _ in }
    private let lock = NSLock()
    private var failuresToSimulate: Int

    init(planner: RoutePlanning, verifiedOnly: Bool, avoid: RouteAvoid, language: Language, book: PlanBook, simulatedFailures: Int = 0) {
        self.planner = planner
        self.verifiedOnly = verifiedOnly
        self.avoid = avoid
        self.language = language
        self.book = book
        failuresToSimulate = simulatedFailures
    }

    func getRoutes(userLocation: UserLocation, waypoints: [Waypoint]) async throws -> [Route] {
        guard let destination = waypoints.last else { throw RideError.noDestination }
        let generation = book.generation
        do {
            if consumeSimulatedFailure() { throw URLError(.cannotConnectToHost) }
            let plan = try await planner.route(
                from: Coordinate(userLocation.coordinates),
                to: Coordinate(destination.coordinate),
                stops: waypoints.dropLast().map { Coordinate($0.coordinate) },
                avoid: avoid,
                verifiedOnly: verifiedOnly,
                language: language
            )
            book.store(plan, generation: generation)
            onOutcome(.success(()))
            return [plan.route]
        } catch {
            onOutcome(.failure(error))
            throw error
        }
    }

    private func consumeSimulatedFailure() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard failuresToSimulate > 0 else { return false }
        failuresToSimulate -= 1
        return true
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
    let simulatedRerouteFailures: Int
    let simulatedEditFailures: Int
    let discardActiveRide: Bool

    static let current = RideOptions(defaults: .standard)

    init(
        simulate: Bool,
        simulatedSpeedKmh: Double = 45,
        simulatedOrigin: Coordinate? = nil,
        tickInterval: TimeInterval = 0.5,
        simulatedRerouteFailures: Int = 0,
        simulatedEditFailures: Int = 0,
        discardActiveRide: Bool = false
    ) {
        self.simulate = simulate
        self.simulatedSpeedKmh = simulatedSpeedKmh
        self.simulatedOrigin = simulatedOrigin
        self.tickInterval = tickInterval
        self.simulatedRerouteFailures = simulatedRerouteFailures
        self.simulatedEditFailures = simulatedEditFailures
        self.discardActiveRide = discardActiveRide
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
        self.init(
            simulate: simulate,
            simulatedSpeedKmh: speed > 0 ? speed : 45,
            simulatedOrigin: simulate ? origin : nil,
            simulatedRerouteFailures: simulate ? max(0, defaults.integer(forKey: "NaviscootSimRerouteFailures")) : 0,
            simulatedEditFailures: simulate ? max(0, defaults.integer(forKey: "NaviscootSimEditFailures")) : 0,
            discardActiveRide: defaults.bool(forKey: "NaviscootDiscardActiveRide")
        )
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
