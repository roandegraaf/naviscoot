import FerrostarCore
import FerrostarCoreFFI
@testable import Naviscoot
import XCTest

final class RideEditTests: XCTestCase {
    private final class Planner: RoutePlanning, @unchecked Sendable {
        struct Call: Equatable {
            let origin: Coordinate
            let destination: Coordinate
            let stops: [Coordinate]
            let avoid: RouteAvoid
            let verifiedOnly: Bool
            let language: Language
        }

        var plans: [RoutePlan]
        var failures: [Error] = []
        private(set) var calls: [Call] = []

        init(plans: [RoutePlan]) {
            self.plans = plans
        }

        func route(from origin: Coordinate, to destination: Coordinate, stops: [Coordinate], avoid: RouteAvoid, verifiedOnly: Bool, language: Language) async throws -> RoutePlan {
            calls.append(Call(origin: origin, destination: destination, stops: stops, avoid: avoid, verifiedOnly: verifiedOnly, language: language))
            if !failures.isEmpty { throw failures.removeFirst() }
            return plans.count > 1 ? plans.removeFirst() : plans[0]
        }
    }

    private let biltstraat = Destination(title: "Biltstraat 100", subtitle: "Utrecht", coordinate: Coordinate(lat: 52.09545846, lon: 5.13137094))
    private let soesterberg = Destination(title: "Kampweg 1", subtitle: "Soesterberg", coordinate: Coordinate(lat: 52.12033201, lon: 5.28612696))
    private let deBilt = Destination(title: "Utrechtseweg 368-TR", subtitle: "De Bilt", coordinate: Coordinate(lat: 52.09987599, lon: 5.16170801))
    private let amersfoort = Destination(title: "Lieve Vrouwestraat 33", subtitle: "Amersfoort", coordinate: Coordinate(lat: 52.15612897, lon: 5.38786971))
    private let here = Coordinate(lat: 52.0907, lon: 5.1214)

    private var ride: ActiveRide {
        ActiveRide(
            destination: amersfoort,
            stops: [soesterberg],
            verifiedOnly: true,
            avoid: RouteAvoid(ferries: true, unpaved: false, mainRoads: true),
            language: .dutch
        )
    }

    private func fixture(_ name: String, edit: (inout [String: Any]) -> Void = { _ in }) throws -> RoutePlan {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        edit(&json)
        return try RouteParser.parse(JSONSerialization.data(withJSONObject: json))
    }

    func testAddingAStopGoesThroughItFirstThenTheRemainingStopsWithTheRidesOptionsFromHere() async throws {
        let plan = try fixture("route-multi-stop")
        let planner = Planner(plans: [plan])

        let edited = try await RouteEdit.addStop(biltstraat).plan(for: ride, from: here, planner: planner)

        XCTAssertEqual(edited.ride.stops, [biltstraat, soesterberg])
        XCTAssertEqual(edited.ride.destination, amersfoort)
        XCTAssertEqual(edited.plan.meta.routeId, plan.meta.routeId)
        XCTAssertEqual(planner.calls, [Planner.Call(
            origin: here,
            destination: amersfoort.coordinate,
            stops: [biltstraat.coordinate, soesterberg.coordinate],
            avoid: RouteAvoid(ferries: true, unpaved: false, mainRoads: true),
            verifiedOnly: true,
            language: .dutch
        )])
    }

    func testChangingTheDestinationKeepsTheRemainingStopsAndTheOptions() async throws {
        let planner = Planner(plans: [try fixture("route-multi-stop")])

        let edited = try await RouteEdit.changeDestination(deBilt).plan(for: ride, from: here, planner: planner)

        XCTAssertEqual(edited.ride, ActiveRide(destination: deBilt, stops: [soesterberg], verifiedOnly: true, avoid: ride.avoid, language: .dutch))
        XCTAssertEqual(planner.calls.map(\.destination), [deBilt.coordinate])
        XCTAssertEqual(planner.calls.map(\.stops), [[soesterberg.coordinate]])
        XCTAssertEqual(RouteEdit.changeDestination(deBilt).applied(to: ActiveRide(destination: amersfoort, stops: [], verifiedOnly: false, avoid: RouteAvoid(), language: .english)).stops, [])
    }

    func testAFailedEditPlanThrowsAndLeavesTheRideAsItWas() async throws {
        let planner = Planner(plans: [try fixture("route-multi-stop")])
        planner.failures = [URLError(.cannotConnectToHost)]
        let before = ride
        do {
            _ = try await RouteEdit.addStop(biltstraat).plan(for: before, from: here, planner: planner)
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(Strings.message(for: error), Strings.networkFailed)
        }
        XCTAssertEqual(before, ride)
    }

    func testARerouteRequestedBeforeAnEditIsNotAcceptedAfterIt() async throws {
        let old = try fixture("route-default")
        let planner = Planner(plans: [old])
        let book = PlanBook()
        let provider = NaviscootRouteProvider(planner: planner, verifiedOnly: false, avoid: RouteAvoid(), language: .english, book: book)
        let user = UserLocation(coordinates: GeographicCoordinate(lat: 52.2, lng: 5.4), horizontalAccuracy: 5, courseOverGround: nil, timestamp: Date(), speed: nil)
        let destination = [Waypoint(coordinate: GeographicCoordinate(lat: 52.04, lng: 5.40), kind: .break)]

        let routes = try await provider.getRoutes(userLocation: user, waypoints: destination)
        XCTAssertEqual(book.plan(for: routes[0])?.meta.routeId, old.meta.routeId)

        let edited = try fixture("route-multi-stop")
        book.startNewGeneration()
        book.store(edited)
        XCTAssertNil(book.plan(for: routes[0]), "a route planned for the old waypoints replaced the edited one")
        XCTAssertEqual(book.plan(for: edited.route)?.meta.routeId, edited.meta.routeId)

        let after = try await provider.getRoutes(userLocation: user, waypoints: destination)
        XCTAssertNotNil(book.plan(for: after[0]), "a reroute requested after the edit must still be accepted")
    }

    @MainActor
    func testAnEditMidRideSwitchesTheRouteSavesTheRideAndWarnsAgainForTheNewRoute() async throws {
        let startsUnverified: (inout [String: Any]) -> Void = { json in
            var meta = json["naviscoot"] as! [String: Any]
            var stretches = meta["stretches"] as! [[String: Any]]
            stretches[0]["class"] = "unverified"
            stretches[0]["way_ids"] = [42]
            meta["stretches"] = stretches
            json["naviscoot"] = meta
        }
        let first = try fixture("route-default", edit: startsUnverified)
        let second = try fixture("route-default") { json in
            startsUnverified(&json)
            var meta = json["naviscoot"] as! [String: Any]
            meta["route_id"] = "00000000-0000-0000-0000-000000000002"
            json["naviscoot"] = meta
        }
        XCTAssertNotEqual(first.meta.routeId, second.meta.routeId)
        let planner = Planner(plans: [second])
        let url = FileManager.default.temporaryDirectory.appending(path: "active-ride-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let store = ActiveRideStore(url: url)
        let setup = ActiveRide(destination: amersfoort, stops: [], verifiedOnly: true, avoid: RouteAvoid(ferries: false, unpaved: true, mainRoads: false), language: .english)
        let model = RideModel(
            plan: first,
            ride: setup,
            planner: planner,
            reports: ReportQueue(sender: nil, storeURL: nil),
            store: store,
            options: RideOptions(simulate: true, simulatedSpeedKmh: 30, tickInterval: 0.05)
        )
        model.start()
        addTeardownBlock { await MainActor.run { model.end() } }

        let warning: (SpokenLine) -> Bool = { $0.text.contains("unverified") }
        try await waitUntil(seconds: 10) { model.spoken.contains(where: warning) && model.userCoordinate != nil }
        XCTAssertEqual(model.spoken.filter(warning).count, 1)

        model.edit(.changeDestination(deBilt))
        try await waitUntil(seconds: 10) { model.routeId == second.meta.routeId }

        XCTAssertNil(model.editState)
        XCTAssertEqual(model.destination, deBilt)
        XCTAssertEqual(model.ride.destination, deBilt)
        XCTAssertEqual(store.load(), ActiveRide(destination: deBilt, stops: [], verifiedOnly: true, avoid: setup.avoid, language: .english))
        let call = try XCTUnwrap(planner.calls.first)
        XCTAssertEqual(call.destination, deBilt.coordinate)
        XCTAssertEqual(call.avoid, setup.avoid)
        XCTAssertTrue(call.verifiedOnly)
        XCTAssertEqual(call.language, .english)
        XCTAssertLessThan(Geo.distanceM(call.origin, Coordinate(first.route.geometry[0])), 200, "the edit did not plan from the current position")

        try await waitUntil(seconds: 10) { model.spoken.filter(warning).count == 2 }
        XCTAssertNotNil(model.alert)

        planner.failures = [URLError(.notConnectedToInternet)]
        model.edit(.addStop(biltstraat))
        try await waitUntil(seconds: 10) { model.editState != nil && model.editState != .planning }
        XCTAssertEqual(model.editState, .failed(Strings.networkFailed))
        XCTAssertEqual(model.routeId, second.meta.routeId)
        XCTAssertEqual(model.remainingStops, [])
        XCTAssertEqual(store.load()?.stops, [])
    }

    func testTheCameraFollowsUntilTheRiderMovesTheMapAndRecenterOrOverviewChangeThat() {
        var camera = RideCamera()
        XCTAssertEqual(camera.mode, .following)
        XCTAssertTrue(camera.follows)
        XCTAssertFalse(camera.offersRecenter)
        XCTAssertFalse(camera.holdsStill)

        camera.userMovedMap()
        XCTAssertEqual(camera.mode, .free)
        XCTAssertFalse(camera.follows)
        XCTAssertTrue(camera.offersRecenter)
        XCTAssertTrue(camera.holdsStill)

        camera.recenter()
        XCTAssertEqual(camera, RideCamera())

        camera.showOverview()
        XCTAssertEqual(camera.mode, .overview)
        XCTAssertFalse(camera.follows)
        XCTAssertTrue(camera.offersRecenter)
        XCTAssertFalse(camera.holdsStill)

        camera.userMovedMap()
        XCTAssertEqual(camera.mode, .free)
        camera.recenter()
        XCTAssertTrue(camera.follows)
    }

    func testTheOverviewCoversThePositionAndTheRouteAheadOnly() throws {
        let points = [
            Coordinate(lat: 52.00, lon: 5.00),
            Coordinate(lat: 52.10, lon: 5.20),
            Coordinate(lat: 52.05, lon: 5.40),
            Coordinate(lat: 52.20, lon: 5.30),
        ]
        let user = Coordinate(lat: 52.09, lon: 5.21)
        let remaining = RideCamera.remainingRoute(points: points, from: 2, user: user)
        XCTAssertEqual(remaining, [user, points[2], points[3]])

        let bounds = try XCTUnwrap(RideCamera.bounds(of: remaining))
        XCTAssertEqual(bounds.southWest, Coordinate(lat: 52.05, lon: 5.21))
        XCTAssertEqual(bounds.northEast, Coordinate(lat: 52.20, lon: 5.40))

        XCTAssertEqual(RideCamera.remainingRoute(points: points, from: 99, user: nil), [points[3]])
        XCTAssertEqual(RideCamera.remainingRoute(points: [], from: 0, user: user), [user])
        XCTAssertNil(RideCamera.bounds(of: []))
    }

    private func waitUntil(seconds: Double, _ condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("condition never became true")
    }
}
