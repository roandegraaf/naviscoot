@testable import Naviscoot
import XCTest

final class TripPlanTests: XCTestCase {
    private let here = Coordinate(lat: 52.0907, lon: 5.1214)
    private let zeist = Destination(title: "Slotlaan 10", subtitle: "Zeist", coordinate: Coordinate(lat: 52.08235683, lon: 5.24011346))
    private let soesterberg = Destination(title: "Kampweg 1", subtitle: "Soesterberg", coordinate: Coordinate(lat: 52.12033201, lon: 5.28612696))
    private let amersfoort = Destination(title: "Lieve Vrouwestraat 33", subtitle: "Amersfoort", coordinate: Coordinate(lat: 52.15612897, lon: 5.38786971))

    func testATwoPointTripAsksForTwoAlternativesFromTheCurrentLocation() throws {
        let trip = TripPlan(destination: amersfoort)
        XCTAssertNil(trip.request(currentLocation: nil, avoid: RouteAvoid()))

        let request = try XCTUnwrap(trip.request(currentLocation: here, avoid: RouteAvoid()))
        XCTAssertEqual(request.origin, here)
        XCTAssertEqual(request.destination, amersfoort.coordinate)
        XCTAssertEqual(request.options, RouteOptions(stops: [], alternatives: 2, time: nil, avoid: RouteAvoid()))
        XCTAssertTrue(trip.startsFromCurrentLocation)
    }

    func testStopsAreSentInOrderWithoutAlternatives() throws {
        var trip = TripPlan(destination: amersfoort)
        trip.addStop(zeist)
        trip.addStop(soesterberg)
        let request = try XCTUnwrap(trip.request(currentLocation: here, avoid: RouteAvoid()))
        XCTAssertEqual(request.options.stops, [zeist.coordinate, soesterberg.coordinate])
        XCTAssertEqual(request.options.alternatives, 0)

        trip.moveStopUp(at: 1)
        XCTAssertEqual(trip.stops, [soesterberg, zeist])
        XCTAssertEqual(trip.request(currentLocation: here, avoid: RouteAvoid())?.options.stops, [soesterberg.coordinate, zeist.coordinate])

        trip.moveStopUp(at: 0)
        XCTAssertEqual(trip.stops, [soesterberg, zeist])
        trip.removeStop(at: 0)
        XCTAssertEqual(trip.stops, [zeist])
        trip.removeStop(at: 0)
        XCTAssertEqual(trip.request(currentLocation: here, avoid: RouteAvoid())?.options.alternatives, 2)
    }

    func testStopsAreCappedAtEight() {
        var trip = TripPlan(destination: amersfoort)
        for index in 0 ..< 10 {
            trip.addStop(Destination(title: "\(index)", subtitle: "", coordinate: Coordinate(lat: 52 + Double(index) / 100, lon: 5.2)))
        }
        XCTAssertEqual(trip.stops.count, TripPlan.maxStops)
        XCTAssertFalse(trip.canAddStop)
        XCTAssertEqual(trip.stops.last?.title, "7")
    }

    func testAStopOnTopOfItsNeighbourIsNotSent() throws {
        let start = Destination(title: "Domplein", subtitle: "Utrecht", coordinate: here)
        let nearStart = Coordinate(lat: here.lat + 0.0001, lon: here.lon)
        let nearZeist = Coordinate(lat: zeist.coordinate.lat, lon: zeist.coordinate.lon + 0.0001)
        let nearDestination = Coordinate(lat: amersfoort.coordinate.lat + 0.0001, lon: amersfoort.coordinate.lon)
        let kept = TripPlan.routableStops(
            [nearStart, zeist.coordinate, nearZeist, soesterberg.coordinate, nearDestination],
            origin: start.coordinate,
            destination: amersfoort.coordinate
        )
        XCTAssertEqual(kept, [zeist.coordinate, soesterberg.coordinate])

        var trip = TripPlan(destination: amersfoort)
        trip.start = .place(start)
        trip.addStop(Destination(title: "again", subtitle: "", coordinate: here))
        let request = try XCTUnwrap(trip.request(currentLocation: nil, avoid: RouteAvoid()))
        XCTAssertEqual(request.options.stops, [])
        XCTAssertEqual(request.options.alternatives, 2)
        XCTAssertEqual(trip.routableStops(currentLocation: nil), [])

        var fromHere = TripPlan(destination: amersfoort)
        let twice = Destination(title: "Slotlaan 10 again", subtitle: "", coordinate: nearZeist)
        for stop in [zeist, twice, soesterberg] { fromHere.addStop(stop) }
        XCTAssertEqual(fromHere.routableStops(currentLocation: here), [zeist, soesterberg])
        XCTAssertEqual(fromHere.request(currentLocation: here, avoid: RouteAvoid())?.options.stops, [zeist.coordinate, soesterberg.coordinate])
        XCTAssertEqual(fromHere.routableStops(currentLocation: nil), [])
    }

    func testAnotherStartPointIsTheOriginAndNeedsNoLocation() throws {
        var trip = TripPlan(destination: amersfoort)
        trip.start = .place(zeist)
        XCTAssertFalse(trip.startsFromCurrentLocation)
        let request = try XCTUnwrap(trip.request(currentLocation: nil, avoid: RouteAvoid()))
        XCTAssertEqual(request.origin, zeist.coordinate)
        XCTAssertEqual(trip.request(currentLocation: here, avoid: RouteAvoid())?.origin, zeist.coordinate)
    }

    func testTimeAndAvoidGoIntoTheRequest() throws {
        var trip = TripPlan(destination: amersfoort)
        let departure = Date(timeIntervalSince1970: 1_794_812_400)
        trip.time = .departAt(departure)
        let avoid = RouteAvoid(ferries: true, unpaved: true, mainRoads: false)
        let request = try XCTUnwrap(trip.request(currentLocation: here, avoid: avoid))
        XCTAssertEqual(request.options.time, .departAt(departure))
        XCTAssertEqual(request.options.avoid, avoid)
    }

    func testDepartAtShowsTheArrivalAndArriveByShowsWhenToLeave() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Amsterdam"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 14, minute: 12)))
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: now))
        let eight = try XCTUnwrap(calendar.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrow))
        let nine = try XCTUnwrap(calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow))
        let duration = 2191.0

        let depart = TripPlan.schedule(for: .departAt(eight), durationS: duration, now: now)
        XCTAssertEqual(depart.departure, eight)
        XCTAssertEqual(depart.arrival, eight.addingTimeInterval(duration))
        XCTAssertEqual(Format.clockTime(depart.arrival, timeZone: calendar.timeZone, language: .english), "08:36")

        let arrive = TripPlan.schedule(for: .arriveBy(nine), durationS: duration, now: now)
        XCTAssertEqual(arrive.arrival, nine)
        XCTAssertEqual(Format.clockTime(arrive.departure, timeZone: calendar.timeZone, language: .dutch), "08:23")
        XCTAssertEqual(Strings.format("preview.leaveAt", "08:23", language: .english), "leave at 08:23")

        let leaveNow = TripPlan.schedule(for: nil, durationS: duration, now: now)
        XCTAssertEqual(leaveNow.departure, now)
        XCTAssertEqual(leaveNow.arrival, now.addingTimeInterval(duration))

        XCTAssertEqual(TripTimeSheet.nextWholeHour(after: now, calendar: calendar), calendar.date(bySettingHour: 15, minute: 0, second: 0, of: now))
    }

    func testUnverifiedStatusSaysWhenEveryRemainingStretchIsUnavoidable() {
        func meta(_ stretches: [Stretch]) -> NaviscootMeta {
            let unverified = stretches.filter { $0.stretchClass == .unverified }.map(\.lengthM).reduce(0, +)
            return NaviscootMeta(
                routeId: "r",
                lengthM: 1000,
                totalsM: RouteTotals(carriageway: 1000 - unverified, mopedPath: 0, unverified: unverified, forbidden: 0),
                stretches: stretches,
                speedLimits: nil,
                warnings: [],
                verifiedOnly: nil,
                avoidUnpaved: nil,
                legs: nil,
                alternates: nil
            )
        }
        func stretch(_ stretchClass: StretchClass, _ length: Int, unavoidable: String? = nil) -> Stretch {
            Stretch(stretchClass: stretchClass, startShapeIndex: 0, endShapeIndex: 1, lengthM: length, wayIds: [], unavoidable: unavoidable)
        }

        XCTAssertEqual(UnverifiedStatus(meta: meta([stretch(.carriageway, 1000)])), .none)
        XCTAssertEqual(UnverifiedStatus(meta: meta([
            stretch(.carriageway, 800),
            stretch(.unverified, 120, unavoidable: "no_alternative"),
            stretch(.unverified, 80, unavoidable: "endpoint"),
        ])), .unavoidable(200))
        XCTAssertEqual(UnverifiedStatus(meta: meta([
            stretch(.carriageway, 800),
            stretch(.unverified, 120, unavoidable: "no_alternative"),
            stretch(.unverified, 80),
        ])), .remaining(200))
    }

    func testThePlannerErrorsHaveRealCopyInBothLanguages() {
        for language in Language.allCases {
            for key in ["error.tooManyStops", "error.conflictingTimes", "error.alternativesNeedTwoPoints"] {
                let text = Strings.tr(key, language: language)
                XCTAssertNotEqual(text, key, "\(key) missing in \(language)")
                XCTAssertFalse(text.contains("400"), text)
            }
        }
        XCTAssertEqual(Strings.format("error.tooManyStops", 8, language: .english), "A trip can have at most 8 stops.")
        XCTAssertFalse(Strings.message(for: RouteRequestError.conflictingTimes).contains("400"))
        XCTAssertFalse(Strings.message(for: RouteRequestError.alternativesNeedTwoPoints).contains("400"))
        XCTAssertFalse(Strings.message(for: RouteRequestError.tooManyStops).contains("400"))
    }

    func testAvoidSettingsDefaultOffAndPersist() {
        let name = "trip-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }

        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.routeAvoid, RouteAvoid())
        settings.avoidFerries = true
        settings.avoidMainRoads = true

        let reopened = AppSettings(defaults: defaults)
        XCTAssertEqual(reopened.routeAvoid, RouteAvoid(ferries: true, unpaved: false, mainRoads: true))
        reopened.avoidUnpaved = true
        reopened.avoidFerries = false
        XCTAssertEqual(AppSettings(defaults: defaults).routeAvoid, RouteAvoid(ferries: false, unpaved: true, mainRoads: true))
    }
}

final class StubRouteProtocol: URLProtocol {
    nonisolated(unsafe) static var response: Data = Data()
    nonisolated(unsafe) static var bodies: [[String: Any]] = []

    override class func canInit(with _: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(buffer, count: count)
            }
            stream.close()
        }
        if let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            Self.bodies.append(body)
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["content-type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.response)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
final class PreviewModelTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json")))
    }

    private func makeModel(avoid: RouteAvoid = RouteAvoid()) throws -> PreviewModel {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "route-alternatives", withExtension: "json"))
        StubRouteProtocol.response = try Data(contentsOf: url)
        StubRouteProtocol.bodies = []
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubRouteProtocol.self]
        let client = NaviscootClient(
            config: APIConfig(baseURL: URL(string: "http://127.0.0.1:8080")!, apiKey: "k"),
            session: URLSession(configuration: configuration)
        )
        let name = "preview-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults)
        settings.languageChoice = .english
        settings.avoidFerries = avoid.ferries
        settings.avoidUnpaved = avoid.unpaved
        settings.avoidMainRoads = avoid.mainRoads
        let destination = Destination(title: "Amersfoort", subtitle: "", coordinate: Coordinate(lat: 52.1561, lon: 5.3878))
        return PreviewModel(destination: destination, client: client, settings: settings)
    }

    private func waitUntilSettled(_ model: PreviewModel) async throws {
        for _ in 0 ..< 200 {
            switch model.state {
            case .loaded, .failed: return
            default: try await Task.sleep(nanoseconds: 20_000_000)
            }
        }
        XCTFail("the preview never settled")
    }

    private func waitUntilLoaded(_ model: PreviewModel) async throws {
        for _ in 0 ..< 200 {
            if case .loaded = model.state { return }
            if case let .failed(message) = model.state { XCTFail(message); return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("the preview never loaded")
    }

    func testThePreviewListsEveryRouteAndStartUsesTheSelectedOne() async throws {
        let model = try makeModel(avoid: RouteAvoid(ferries: true, unpaved: false, mainRoads: false))
        model.originChanged(Coordinate(lat: 52.0907, lon: 5.1214))
        try await waitUntilLoaded(model)

        XCTAssertEqual(model.plans.count, 3)
        XCTAssertEqual(model.selectedPlan?.meta.routeId, model.plans[0].meta.routeId)
        XCTAssertTrue(model.canStart)
        let body = try XCTUnwrap(StubRouteProtocol.bodies.last)
        XCTAssertEqual(body["alternatives"] as? Int, 2)
        XCTAssertEqual(body["avoid"] as? [String: Bool], ["ferries": true, "unpaved": false, "main_roads": false])

        model.select(2)
        XCTAssertEqual(model.selectedPlan?.meta.routeId, model.plans[2].meta.routeId)
        XCTAssertNotEqual(model.plans[2].meta.routeId, model.plans[0].meta.routeId)
        model.select(5)
        XCTAssertEqual(model.selectedIndex, 2)
    }

    func testStopsKeepStartAndAnotherStartHidesIt() async throws {
        let model = try makeModel()
        model.originChanged(Coordinate(lat: 52.0907, lon: 5.1214))
        try await waitUntilLoaded(model)

        let stop = Destination(title: "Zeist", subtitle: "", coordinate: Coordinate(lat: 52.08235683, lon: 5.24011346))
        let second = Destination(title: "Soesterberg", subtitle: "", coordinate: Coordinate(lat: 52.12033201, lon: 5.28612696))
        StubRouteProtocol.response = try fixture("route-multi-stop")
        model.addStop(stop)
        try await waitUntilSettled(model)
        XCTAssertNil(model.selectedPlan, "a route without the stop's waypoint was accepted")
        XCTAssertNil(model.rideToStart())
        guard case let .failed(message) = model.state else { return XCTFail("expected the unsupported-stops error") }
        XCTAssertEqual(message, "This route service can't plan stops yet. Remove the stops or update the service.")

        model.addStop(second)
        try await waitUntilLoaded(model)
        let withStops = try XCTUnwrap(StubRouteProtocol.bodies.last)
        XCTAssertNil(withStops["alternatives"])
        XCTAssertEqual((withStops["waypoints"] as? [[String: Double]])?.count, 2)
        XCTAssertTrue(model.canStart)
        XCTAssertEqual(model.rideToStart()?.stops, [stop, second])
        XCTAssertEqual(model.rideToStart()?.destination, model.destination)

        model.removeStop(at: 1)
        try await waitUntilSettled(model)
        model.removeStop(at: 0)
        try await waitUntilLoaded(model)
        XCTAssertTrue(model.canStart)

        let start = Destination(title: "Soesterberg", subtitle: "", coordinate: Coordinate(lat: 52.12033201, lon: 5.28612696))
        model.setStart(.place(start))
        try await waitUntilLoaded(model)
        let fromStart = try XCTUnwrap(StubRouteProtocol.bodies.last)
        XCTAssertEqual(fromStart["origin"] as? [String: Double], ["lat": 52.12033201, "lon": 5.28612696])
        XCTAssertFalse(model.canStart)

        model.setStart(.currentLocation)
        try await waitUntilLoaded(model)
        XCTAssertTrue(model.canStart)

        let nine = Date(timeIntervalSince1970: 1_794_816_000)
        model.setTime(.arriveBy(nine))
        try await waitUntilLoaded(model)
        XCTAssertEqual(StubRouteProtocol.bodies.last?["arrive_by"] as? String, "2026-11-16T08:00:00Z")
        let schedule = try XCTUnwrap(model.schedule())
        XCTAssertEqual(schedule.arrival, nine)
        XCTAssertEqual(schedule.departure, nine.addingTimeInterval(-(model.selectedPlan?.durationS ?? 0)))
        XCTAssertEqual(StubRouteProtocol.bodies.count, 8)
    }
}
