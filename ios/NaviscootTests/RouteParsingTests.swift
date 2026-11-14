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
            verifiedOnly: true
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
    }

    func testErrorBodiesMapToRouteErrors() {
        func body(_ code: String) -> Data { Data("{\"error\":\"\(code)\"}".utf8) }
        XCTAssertEqual(NaviscootClient.error(status: 401, body: body("unauthorized")), .unauthorized)
        XCTAssertEqual(NaviscootClient.error(status: 422, body: body("no_route")), .noRoute)
        XCTAssertEqual(NaviscootClient.error(status: 502, body: body("valhalla_unavailable")), .serviceUnavailable)
        XCTAssertEqual(NaviscootClient.error(status: 502, body: body("classification_failed")), .classificationFailed)
        XCTAssertEqual(NaviscootClient.error(status: 500, body: Data("oops".utf8)), .http(status: 500, code: nil))
    }

    func testFormatting() {
        XCTAssertEqual(Format.distance(meters: 0), "0 m")
        XCTAssertEqual(Format.distance(meters: 483), "483 m")
        XCTAssertEqual(Format.distance(meters: 999), "999 m")
        XCTAssertEqual(Format.distance(meters: 1000), "1.0 km")
        XCTAssertEqual(Format.distance(meters: 20961), "21.0 km")
        XCTAssertEqual(Format.distance(meters: 36255), "36.3 km")
        XCTAssertEqual(Format.duration(seconds: 20), "1 min")
        XCTAssertEqual(Format.duration(seconds: 3000), "50 min")
        XCTAssertEqual(Format.duration(seconds: 4241.428), "1 h 11 min")
        let date = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(Format.clockTime(date, timeZone: TimeZone(identifier: "Europe/Amsterdam")!), "01:00")
    }

    private func stretch(_ stretchClass: StretchClass, _ start: Int, _ end: Int) -> Stretch {
        Stretch(stretchClass: stretchClass, startShapeIndex: start, endShapeIndex: end, lengthM: 1, wayIds: [], unavoidable: nil)
    }
}
