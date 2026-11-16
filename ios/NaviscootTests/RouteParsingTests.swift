@testable import Naviscoot
import XCTest

final class RouteParsingTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    func testDefaultRouteParsesWithFerrostarAndKeepsTheNaviscootKey() throws {
        let plan = try RouteParser.parse(fixture("route-default"))

        XCTAssertEqual(plan.route.geometry.count, 1457)
        XCTAssertEqual(plan.route.distance, 36254.836, accuracy: 0.001)
        XCTAssertEqual(plan.durationS, 4241.428, accuracy: 0.001)
        XCTAssertFalse(plan.route.steps.isEmpty)
        XCTAssertEqual(plan.meta.lengthM, 36255)
        XCTAssertEqual(plan.meta.totalsM, RouteTotals(carriageway: 20961, mopedPath: 14811, unverified: 483, forbidden: 0))
        XCTAssertNil(plan.meta.verifiedOnly)
    }

    func testTotalsAndStretchesAddUpToTheRouteLength() throws {
        let plan = try RouteParser.parse(fixture("route-default"))

        XCTAssertEqual(plan.meta.totalsM.sum, plan.meta.lengthM)
        XCTAssertEqual(plan.meta.stretches.map(\.lengthM).reduce(0, +), plan.meta.lengthM)
        for stretchClass in StretchClass.allCases {
            let fromStretches = plan.meta.stretches.filter { $0.stretchClass == stretchClass }.map(\.lengthM).reduce(0, +)
            XCTAssertEqual(fromStretches, plan.meta.totalsM[stretchClass], "\(stretchClass)")
        }
    }

    func testStretchesSplitTheGeometryIntoContiguousSegments() throws {
        let plan = try RouteParser.parse(fixture("route-default"))
        let geometry = plan.route.geometry.map(Coordinate.init)

        XCTAssertEqual(plan.segments.count, plan.meta.stretches.count)
        XCTAssertEqual(plan.segments.first?.coordinates.first, geometry.first)
        XCTAssertEqual(plan.segments.last?.coordinates.last, geometry.last)
        for (segment, stretch) in zip(plan.segments, plan.meta.stretches) {
            XCTAssertEqual(segment.stretchClass, stretch.stretchClass)
            XCTAssertGreaterThanOrEqual(segment.coordinates.count, 2)
            XCTAssertEqual(segment.coordinates.first, geometry[stretch.startShapeIndex])
            XCTAssertEqual(segment.coordinates.last, geometry[stretch.endShapeIndex])
        }
        for (current, next) in zip(plan.segments, plan.segments.dropFirst()) {
            XCTAssertEqual(current.coordinates.last, next.coordinates.first)
        }

        let unverified = plan.segments.filter { $0.stretchClass == .unverified }
        XCTAssertEqual(unverified.count, 1)
        XCTAssertEqual(unverified.first?.coordinates.count, 1377 - 1341 + 1)
        XCTAssertEqual(plan.unverifiedStretches.first?.wayIds, [1_497_802_338])
    }

    func testVerifiedOnlyRouteHasNoUnverifiedSegment() throws {
        let plan = try RouteParser.parse(fixture("route-verified-only"))

        XCTAssertEqual(plan.meta.totalsM.unverified, 0)
        XCTAssertEqual(plan.meta.totalsM.sum, plan.meta.lengthM)
        XCTAssertTrue(plan.segments.allSatisfy { $0.stretchClass != .unverified })
        XCTAssertEqual(plan.meta.verifiedOnly, VerifiedOnlyInfo(requests: 2, excludedPoints: 2, converged: true, stoppedBecause: nil))
    }

    func testMultiStopRouteKeepsEveryLegInOneIndexSpace() throws {
        let plans = try RouteParser.parseAll(fixture("route-multi-stop"))
        let plan = try XCTUnwrap(plans.first)

        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(plan.route.geometry.count, 956)
        XCTAssertEqual(plan.route.waypoints.count, 4)
        XCTAssertEqual(plan.route.distance, 29084.141, accuracy: 0.001)
        XCTAssertEqual(plan.route.steps.count, 55)
        let legs = try XCTUnwrap(plan.meta.legs)
        XCTAssertEqual(legs.map(\.startShapeIndex), [0, 338, 707])
        XCTAssertEqual(legs.map(\.endShapeIndex), [338, 707, 955])
        XCTAssertEqual(legs.first?.firstEdge, 0)
        for (current, next) in zip(legs, legs.dropFirst()) {
            XCTAssertEqual(next.firstEdge, current.lastEdge + 1)
        }

        let geometry = plan.route.geometry.map(Coordinate.init)
        for (index, leg) in legs.enumerated() {
            let waypoint = Coordinate(plan.route.waypoints[index + 1].coordinate)
            XCTAssertEqual(geometry[leg.endShapeIndex].lat, waypoint.lat, accuracy: 0.000001)
            XCTAssertEqual(geometry[leg.endShapeIndex].lon, waypoint.lon, accuracy: 0.000001)
        }
        XCTAssertEqual(plan.meta.totalsM.sum, plan.meta.lengthM)
        XCTAssertEqual(plan.segments.first?.coordinates.first, geometry.first)
        XCTAssertEqual(plan.segments.last?.coordinates.last, geometry.last)
        for (current, next) in zip(plan.segments, plan.segments.dropFirst()) {
            XCTAssertEqual(current.coordinates.last, next.coordinates.first)
        }
        let limits = try XCTUnwrap(plan.meta.speedLimits)
        XCTAssertEqual(limits.first?.startShapeIndex, 0)
        XCTAssertEqual(limits.last?.endShapeIndex, 955)
    }

    func testAlternativesParseIntoOnePlanPerRouteWithItsOwnMeta() throws {
        let data = try fixture("route-alternatives")
        let plans = try RouteParser.parseAll(data)

        XCTAssertEqual(plans.count, 3)
        XCTAssertEqual(plans.map { $0.route.distance }, [22194.225, 25348.221, 25917.229])
        XCTAssertEqual(plans.map(\.durationS), [2191.285, 2709.984, 2552.562])
        XCTAssertEqual(plans.map(\.meta.lengthM), [22194, 25348, 25917])
        XCTAssertEqual(Set(plans.map(\.meta.routeId)).count, 3)
        for plan in plans {
            XCTAssertEqual(plan.meta.totalsM.sum, plan.meta.lengthM)
            XCTAssertEqual(plan.meta.stretches.last?.endShapeIndex, plan.route.geometry.count - 1)
            XCTAssertEqual(plan.segments.last?.coordinates.last, plan.route.geometry.last.map(Coordinate.init))
            XCTAssertNil(plan.meta.legs)
            XCTAssertFalse(plan.route.steps.isEmpty)
        }
        XCTAssertEqual(plans.first?.meta.alternates?.map(\.routeId), plans.dropFirst().map(\.meta.routeId))
        XCTAssertEqual(try RouteParser.parse(data).meta.routeId, plans.first?.meta.routeId)
    }

    func testRoutesWithoutMatchingMetadataAreRejected() throws {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture("route-alternatives")) as? [String: Any])
        var naviscoot = try XCTUnwrap(json["naviscoot"] as? [String: Any])
        naviscoot["alternates"] = Array((naviscoot["alternates"] as? [Any] ?? []).prefix(1))
        json["naviscoot"] = naviscoot
        let data = try JSONSerialization.data(withJSONObject: json)
        XCTAssertThrowsError(try RouteParser.parseAll(data)) { error in
            XCTAssertEqual(error as? RouteParseError, .routeCountMismatch(routes: 3, metas: 2))
        }
    }

    func testLegsMustCoverTheGeometry() throws {
        let leg = { (start: Int, end: Int) in RouteLeg(startShapeIndex: start, endShapeIndex: end, firstEdge: 0, lastEdge: 0) }
        XCTAssertNoThrow(try RouteParser.checkLegs(nil, geometryPoints: 5))
        XCTAssertNoThrow(try RouteParser.checkLegs([leg(0, 2), leg(2, 4)], geometryPoints: 5))
        XCTAssertThrowsError(try RouteParser.checkLegs([leg(0, 2), leg(3, 4)], geometryPoints: 5))
        XCTAssertThrowsError(try RouteParser.checkLegs([leg(0, 2), leg(2, 3)], geometryPoints: 5))
    }

    func testSplitRejectsStretchesThatDoNotMatchTheGeometry() {
        let geometry = (0 ..< 5).map { Coordinate(lat: 52, lon: 5 + Double($0) / 1000) }
        let tooLong = [stretch(.carriageway, 0, 7)]
        XCTAssertThrowsError(try RouteParser.split(geometry: geometry, stretches: tooLong)) { error in
            XCTAssertEqual(error as? RouteParseError, .geometryMismatch(geometryPoints: 5, lastShapeIndex: 7))
        }
        let reversed = [stretch(.carriageway, 3, 1), stretch(.mopedPath, 1, 4)]
        XCTAssertThrowsError(try RouteParser.split(geometry: geometry, stretches: reversed))
    }

    func testSinglePointStretchAndForbiddenClassAreDrawable() throws {
        let geometry = (0 ..< 4).map { Coordinate(lat: 52, lon: 5 + Double($0) / 1000) }
        let segments = try RouteParser.split(
            geometry: geometry,
            stretches: [stretch(.carriageway, 0, 2), stretch(.forbidden, 2, 2), stretch(.unverified, 2, 3)]
        )
        XCTAssertEqual(segments.map(\.stretchClass), [.carriageway, .forbidden, .unverified])
        XCTAssertEqual(segments[1].coordinates, [geometry[2], geometry[2]])
        XCTAssertEqual(segments[2].coordinates, [geometry[2], geometry[3]])
    }

    func testDecodesEveryStretchClass() throws {
        let json = """
        {"route_id":"r","length_m":10,"totals_m":{"carriageway":1,"moped_path":2,"unverified":3,"forbidden":4},
         "stretches":[{"class":"forbidden","start_shape_index":0,"end_shape_index":1,"length_m":4,"way_ids":[1],
                       "unavoidable":"no_alternative"}],
         "warnings":["drift"]}
        """
        let meta = try JSONDecoder().decode(NaviscootMeta.self, from: Data(json.utf8))
        XCTAssertEqual(meta.stretches.first?.stretchClass, .forbidden)
        XCTAssertEqual(meta.stretches.first?.unavoidable, "no_alternative")
        XCTAssertEqual(meta.totalsM[.forbidden], 4)
        XCTAssertEqual(meta.warnings, ["drift"])
    }

    func testRouteRequestCarriesKeyFormatAndVerifiedOnly() throws {
        let client = NaviscootClient(config: APIConfig(baseURL: URL(string: "http://127.0.0.1:8080")!, apiKey: "secret"))
        let request = try client.makeRouteRequest(
            from: Coordinate(lat: 52.2977646, lon: 5.445363),
            to: Coordinate(lat: 52.0464515, lon: 5.4059619),
            verifiedOnly: true,
            language: .english
        )

        XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:8080/route")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "secret")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["format"] as? String, "osrm")
        XCTAssertEqual(body["verified_only"] as? Bool, true)
        let origin = try XCTUnwrap(body["origin"] as? [String: Double])
        XCTAssertEqual(origin["lat"], 52.2977646)
        XCTAssertEqual(origin["lon"], 5.445363)
        XCTAssertEqual(body["language"] as? String, "en-GB")

        let dutch = try client.makeRouteRequest(from: Coordinate(lat: 52.3, lon: 5.4), to: Coordinate(lat: 52.0, lon: 5.4), verifiedOnly: false, language: .dutch)
        let dutchBody = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(dutch.httpBody)) as? [String: Any])
        XCTAssertEqual(dutchBody["language"] as? String, "nl-NL")
        XCTAssertEqual(dutchBody["verified_only"] as? Bool, false)
    }

    func testRouteRequestWithoutOptionsSendsOnlyTheTwoPointFields() throws {
        let client = NaviscootClient(config: APIConfig(baseURL: URL(string: "http://127.0.0.1:8080")!, apiKey: "k"))
        let request = try client.makeRouteRequest(from: Coordinate(lat: 52.3, lon: 5.4), to: Coordinate(lat: 52.0, lon: 5.4), verifiedOnly: false, language: .dutch)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(Set(body.keys), ["origin", "destination", "verified_only", "format", "language"])
    }

    func testRouteRequestCarriesStopsAlternativesTimeAndAvoid() throws {
        let client = NaviscootClient(config: APIConfig(baseURL: URL(string: "http://127.0.0.1:8080")!, apiKey: "k"))
        let origin = Coordinate(lat: 52.0907, lon: 5.1214)
        let destination = Coordinate(lat: 52.1561, lon: 5.3878)
        let departure = Date(timeIntervalSince1970: 1_794_812_400)
        let options = RouteOptions(
            stops: [Coordinate(lat: 52.11, lon: 5.2), Coordinate(lat: 52.13, lon: 5.3)],
            time: .departAt(departure),
            avoid: RouteAvoid(ferries: true, unpaved: false, mainRoads: true)
        )
        let request = try client.makeRouteRequest(from: origin, to: destination, options: options, verifiedOnly: true, language: .english)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])

        let stops = try XCTUnwrap(body["waypoints"] as? [[String: Double]])
        XCTAssertEqual(stops, [["lat": 52.11, "lon": 5.2], ["lat": 52.13, "lon": 5.3]])
        XCTAssertEqual(body["depart_at"] as? String, "2026-11-16T07:00:00Z")
        XCTAssertNil(body["arrive_by"])
        XCTAssertNil(body["alternatives"])
        XCTAssertEqual(body["avoid"] as? [String: Bool], ["ferries": true, "unpaved": false, "main_roads": true])
        XCTAssertEqual(body["verified_only"] as? Bool, true)

        let arrival = try client.makeRouteRequest(
            from: origin,
            to: destination,
            options: RouteOptions(alternatives: 2, time: .arriveBy(departure)),
            verifiedOnly: false,
            language: .dutch
        )
        let arrivalBody = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(arrival.httpBody)) as? [String: Any])
        XCTAssertEqual(arrivalBody["arrive_by"] as? String, "2026-11-16T07:00:00Z")
        XCTAssertEqual(arrivalBody["alternatives"] as? Int, 2)
        XCTAssertNil(arrivalBody["waypoints"])
        XCTAssertNil(arrivalBody["avoid"])
    }

    func testErrorBodiesMapToRouteErrors() {
        func body(_ code: String) -> Data { Data("{\"error\":\"\(code)\"}".utf8) }
        XCTAssertEqual(NaviscootClient.error(status: 401, body: body("unauthorized")), .unauthorized)
        XCTAssertEqual(NaviscootClient.error(status: 422, body: body("no_route")), .noRoute)
        XCTAssertEqual(NaviscootClient.error(status: 502, body: body("valhalla_unavailable")), .serviceUnavailable)
        XCTAssertEqual(NaviscootClient.error(status: 502, body: body("classification_failed")), .classificationFailed)
        XCTAssertEqual(NaviscootClient.error(status: 500, body: Data("oops".utf8)), .http(status: 500, code: nil))
        XCTAssertEqual(NaviscootClient.error(status: 400, body: body("too_many_waypoints")), .tooManyStops)
        XCTAssertEqual(NaviscootClient.error(status: 400, body: body("conflicting_times")), .conflictingTimes)
        XCTAssertEqual(NaviscootClient.error(status: 400, body: body("alternatives_need_two_points")), .alternativesNeedTwoPoints)
        XCTAssertEqual(NaviscootClient.error(status: 400, body: body("Bad Request")), .http(status: 400, code: "Bad Request"))
    }

    func testFormatting() {
        XCTAssertEqual(Format.distance(meters: 0, language: .english), "0 m")
        XCTAssertEqual(Format.distance(meters: 483, language: .english), "483 m")
        XCTAssertEqual(Format.distance(meters: 999, language: .english), "999 m")
        XCTAssertEqual(Format.distance(meters: 1000, language: .english), "1.0 km")
        XCTAssertEqual(Format.distance(meters: 20961, language: .english), "21.0 km")
        XCTAssertEqual(Format.distance(meters: 36255, language: .english), "36.3 km")
        XCTAssertEqual(Format.duration(seconds: 20, language: .english), "1 min")
        XCTAssertEqual(Format.duration(seconds: 3000, language: .english), "50 min")
        XCTAssertEqual(Format.duration(seconds: 4241.428, language: .english), "1 h 11 min")
        let date = Date(timeIntervalSince1970: 0)
        let amsterdam = TimeZone(identifier: "Europe/Amsterdam")!
        XCTAssertEqual(Format.clockTime(date, timeZone: amsterdam, language: .english), "01:00")
        XCTAssertEqual(Format.clockTime(date.addingTimeInterval(13 * 3600), timeZone: amsterdam, language: .english), "14:00")
    }

    func testFormattingFollowsTheLanguage() {
        XCTAssertEqual(Format.distance(meters: 1500, language: .dutch), "1,5 km")
        XCTAssertEqual(Format.distance(meters: 1500, language: .english), "1.5 km")
        XCTAssertEqual(Format.distance(meters: 36255, language: .dutch), "36,3 km")
        XCTAssertEqual(Format.distance(meters: 483, language: .dutch), "483 m")
        XCTAssertEqual(Format.approximateDistance(meters: 1460, language: .dutch), "1,5 km")
        XCTAssertEqual(Format.duration(seconds: 4241.428, language: .dutch), "1 u 11 min")
        XCTAssertEqual(Format.duration(seconds: 3000, language: .dutch), "50 min")
        let afternoon = Date(timeIntervalSince1970: 13 * 3600)
        XCTAssertEqual(Format.clockTime(afternoon, timeZone: TimeZone(identifier: "Europe/Amsterdam")!, language: .dutch), "14:00")
    }

    private func stretch(_ stretchClass: StretchClass, _ start: Int, _ end: Int) -> Stretch {
        Stretch(stretchClass: stretchClass, startShapeIndex: start, endShapeIndex: end, lengthM: 1, wayIds: [], unavoidable: nil)
    }
}
