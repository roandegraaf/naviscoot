import XCTest

final class RideUITests: XCTestCase {
    private let caseOrigin = (lat: 52.2977646, lon: 5.445363)
    private let destination = (lat: 52.04779119, lon: 5.40516261)
    private let address = "Woudenbergseweg 42 Maarsbergen"
    private let unverifiedWay = 1_497_802_338
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        _ = try apiKey()
    }

    func testGuidanceSpeaksDutchStoresAReportAndReroutesAfterADetour() throws {
        launch(origin: caseOrigin, speedKmh: 120)
        startRide()

        let distance = app.staticTexts["ride.banner.distance"]
        let street = app.staticTexts["ride.banner.street"]
        XCTAssertTrue(distance.waitForExistence(timeout: 20))
        XCTAssertTrue(distance.label.range(of: #"^\d+(\.\d)? (m|km)$"#, options: .regularExpression) != nil, distance.label)
        XCTAssertFalse(street.label.isEmpty)

        let spoken = app.staticTexts["sim.spoken"]
        wait(for: spoken, valueContains: "nl-NL|Over ", timeout: 40)
        wait(for: spoken, valueContains: "Rechts afslaan.", timeout: 10)
        XCTAssertFalse(spokenLines().contains { !$0.hasPrefix("nl-NL|") }, spokenLines().joined(separator: "\n"))
        wait(for: street, labelEquals: "Holkerpad", timeout: 40)
        XCTAssertTrue(distance.label.range(of: #"^\d+(\.\d)? (m|km)$"#, options: .regularExpression) != nil, distance.label)
        screenshot("07-ride-banner-voice")

        let routeId = app.staticTexts["sim.routeId"].label
        XCTAssertEqual(routeId.count, 36, routeId)
        let tappedAt = Date()
        app.buttons["ride.report"].tap()
        wait(for: app.staticTexts["ride.reportStatus"], labelEquals: "Report saved with your position", timeout: 15)
        screenshot("08-ride-report")
        let reports = try fetchReports().filter { $0["route_id"] as? String == routeId }
        XCTAssertEqual(reports.count, 1)
        let report = try XCTUnwrap(reports.first)
        let lat = try XCTUnwrap(report["lat"] as? Double)
        let lon = try XCTUnwrap(report["lon"] as? Double)
        XCTAssertTrue((52.25 ... 52.30).contains(lat) && (5.40 ... 5.46).contains(lon), "\(lat), \(lon)")
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let time = try XCTUnwrap((report["time"] as? String).flatMap(iso.date(from:)), "\(report)")
        XCTAssertLessThan(abs(time.timeIntervalSince(tappedAt)), 30)

        let spokenBefore = spokenLines().count
        app.buttons["sim.detour"].tap()
        let routeIdLabel = app.staticTexts["sim.routeId"]
        let changed = expectation(for: NSPredicate(format: "label != %@", routeId), evaluatedWith: routeIdLabel)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 40), .completed, "no new route after the detour")
        XCTAssertEqual(routeIdLabel.label.count, 36)
        XCTAssertTrue(app.staticTexts["sim.status"].label.hasSuffix("reroutes 1"), app.staticTexts["sim.status"].label)
        screenshot("09-ride-rerouted")

        XCTAssertTrue(distance.waitForExistence(timeout: 10))
        let firstDistance = distance.label
        let moved = expectation(for: NSPredicate(format: "label != %@", firstDistance), evaluatedWith: distance)
        XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 20), .completed, "guidance did not continue after the reroute")
        let spokeAgain = expectation(for: NSPredicate { _, _ in self.spokenLines().count > spokenBefore }, evaluatedWith: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [spokeAgain], timeout: 30), .completed, "no instruction spoken after the reroute")
        XCTAssertFalse(app.staticTexts["ride.rerouting"].exists)

        app.buttons["ride.end"].tap()
        XCTAssertTrue(app.textFields["search.field"].waitForExistence(timeout: 10))
    }

    func testWarnsBeforeTheUnverifiedStretchOnScreenAndInDutch() throws {
        let start = try pointBeforeUnverifiedStretch(meters: 1400)
        let fromStart = try fetchRoute(from: start)
        let unverified = fromStart.stretches.filter { $0["class"] as? String == "unverified" }
        XCTAssertEqual(unverified.count, 1, "the route from \(start) no longer crosses one unverified stretch")
        XCTAssertEqual((unverified.first?["way_ids"] as? [Int])?.first, unverifiedWay)
        let length = try XCTUnwrap(unverified.first?["length_m"] as? Int)

        launch(origin: start, speedKmh: 90)
        startRide()

        let warning = app.descendants(matching: .any)["ride.warning"]
        XCTAssertTrue(warning.waitForExistence(timeout: 60), "no warning before the unverified stretch")
        XCTAssertTrue(warning.label.hasPrefix("Unverified path in "), warning.label)
        XCTAssertTrue(warning.label.hasSuffix(", for \(length) m"), warning.label)
        let spoken = app.staticTexts["sim.spoken"]
        wait(for: spoken, valueContains: "nl-NL|Let op: over ", timeout: 10)
        wait(for: spoken, valueContains: "een onbevestigd fietspad van 500 meter.", timeout: 5)
        screenshot("10-ride-warning-ahead")

        wait(for: warning, labelBeginsWith: "On unverified path, ", timeout: 90)
        let chip = app.descendants(matching: .any)["ride.stretch"]
        wait(for: chip, labelEquals: "Unverified path, limit 30", timeout: 10)
        XCTAssertEqual(app.descendants(matching: .any)["ride.limit"].label, "Speed limit 30")
        XCTAssertEqual(spokenLines().filter { $0.contains("onbevestigd fietspad") }.count, 1, spokenLines().joined(separator: "\n"))
        screenshot("11-ride-warning-inside")

        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: warning)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 60), .completed, "the warning stayed after the stretch")
        XCTAssertEqual(spokenLines().filter { $0.contains("onbevestigd fietspad") }.count, 1)
    }

    private func launch(origin: (lat: Double, lon: Double), speedKmh: Int) {
        app = XCUIApplication()
        app.launchArguments = [
            "-NaviscootSimulateRide", "YES",
            "-NaviscootSimSpeedKmh", "\(speedKmh)",
            "-NaviscootSimOrigin", "\(origin.lat),\(origin.lon)",
        ]
        app.launch()
    }

    private func startRide() {
        let field = app.textFields["search.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(address)
        let result = app.buttons.matching(NSPredicate(format: "identifier == 'search.result' AND label CONTAINS %@", "Woudenbergseweg 42,")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 15))
        result.tap()
        let start = app.buttons["preview.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 40))
        start.tap()
        XCTAssertTrue(app.buttons["ride.end"].waitForExistence(timeout: 10))
    }

    private func spokenLines() -> [String] {
        let value = app.staticTexts["sim.spoken"].value as? String ?? ""
        return value.split(separator: "\n").map(String.init)
    }

    private func wait(for element: XCUIElement, valueContains text: String, timeout: TimeInterval) {
        let match = expectation(for: NSPredicate(format: "value CONTAINS %@", text), evaluatedWith: element)
        XCTAssertEqual(XCTWaiter.wait(for: [match], timeout: timeout), .completed, "'\(text)' not in \(element.value ?? "nil")")
    }

    private func wait(for element: XCUIElement, labelEquals text: String, timeout: TimeInterval) {
        let match = expectation(for: NSPredicate(format: "label == %@", text), evaluatedWith: element)
        XCTAssertEqual(XCTWaiter.wait(for: [match], timeout: timeout), .completed, "expected '\(text)', shown '\(element.label)'")
    }

    private func wait(for element: XCUIElement, labelBeginsWith text: String, timeout: TimeInterval) {
        let match = expectation(for: NSPredicate(format: "label BEGINSWITH %@", text), evaluatedWith: element)
        XCTAssertEqual(XCTWaiter.wait(for: [match], timeout: timeout), .completed, "expected '\(text)…', shown '\(element.label)'")
    }

    private struct APIRoute {
        let geometry: [(lat: Double, lon: Double)]
        let stretches: [[String: Any]]
    }

    private func pointBeforeUnverifiedStretch(meters: Double) throws -> (lat: Double, lon: Double) {
        let route = try fetchRoute(from: caseOrigin)
        let stretch = try XCTUnwrap(route.stretches.first { $0["class"] as? String == "unverified" })
        var index = try XCTUnwrap(stretch["start_shape_index"] as? Int)
        var travelled = 0.0
        while index > 0, travelled < meters {
            travelled += Self.distance(route.geometry[index - 1], route.geometry[index])
            index -= 1
        }
        return route.geometry[index]
    }

    private func apiKey() throws -> String {
        guard let key = ProcessInfo.processInfo.environment["NAVISCOOT_API_KEY"] else {
            throw XCTSkip("set TEST_RUNNER_NAVISCOOT_API_KEY to run the ride proof against the local API")
        }
        return key
    }

    private var baseURL: String {
        ProcessInfo.processInfo.environment["NAVISCOOT_API_BASE_URL"] ?? "http://127.0.0.1:8080"
    }

    private func fetchRoute(from origin: (lat: Double, lon: Double)) throws -> APIRoute {
        var request = URLRequest(url: URL(string: "\(baseURL)/route")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "origin": ["lat": origin.lat, "lon": origin.lon],
            "destination": ["lat": destination.lat, "lon": destination.lon],
            "verified_only": false,
            "format": "osrm",
            "language": "nl-NL",
        ])
        let json = try load(request)
        let naviscoot = try XCTUnwrap(json["naviscoot"] as? [String: Any])
        let routes = try XCTUnwrap(json["routes"] as? [[String: Any]])
        let geometry = try XCTUnwrap(routes.first?["geometry"] as? String)
        return try APIRoute(
            geometry: Self.decodePolyline6(geometry),
            stretches: XCTUnwrap(naviscoot["stretches"] as? [[String: Any]])
        )
    }

    private func fetchReports() throws -> [[String: Any]] {
        try XCTUnwrap(load(URLRequest(url: URL(string: "\(baseURL)/reports")!))["reports"] as? [[String: Any]])
    }

    private func load(_ request: URLRequest) throws -> [String: Any] {
        var request = request
        request.setValue(try apiKey(), forHTTPHeaderField: "x-api-key")
        var body: Data?
        let done = expectation(description: "api")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            body = data
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 60)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(body)) as? [String: Any])
    }

    private static func decodePolyline6(_ encoded: String) -> [(lat: Double, lon: Double)] {
        var points: [(lat: Double, lon: Double)] = []
        let bytes = Array(encoded.utf8)
        var index = 0
        var lat = 0
        var lon = 0
        func next() -> Int {
            var result = 0
            var shift = 0
            var byte: Int
            repeat {
                byte = Int(bytes[index]) - 63
                index += 1
                result |= (byte & 0x1F) << shift
                shift += 5
            } while byte >= 0x20
            return (result & 1) != 0 ? ~(result >> 1) : result >> 1
        }
        while index < bytes.count {
            lat += next()
            lon += next()
            points.append((Double(lat) / 1e6, Double(lon) / 1e6))
        }
        return points
    }

    private static func distance(_ a: (lat: Double, lon: Double), _ b: (lat: Double, lon: Double)) -> Double {
        let dLat = (b.lat - a.lat) * .pi / 180
        let dLon = (b.lon - a.lon) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(a.lat * .pi / 180) * cos(b.lat * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * 6_371_008.8 * asin(min(1, sqrt(h)))
    }

    private func screenshot(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] {
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }
}
