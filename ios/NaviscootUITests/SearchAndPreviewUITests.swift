import XCTest

final class SearchAndPreviewUITests: XCTestCase {
    private let origin = (lat: 52.2977646, lon: 5.445363)
    private let destination = (lat: 52.04779119, lon: 5.40516261)
    private let address = "Woudenbergseweg 42 Maarsbergen"
    private let station = "Amersfoort Centraal"
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow While Using App"]
        if allow.waitForExistence(timeout: 4) {
            allow.tap()
        }
    }

    func testSearchThenPreviewMatchesTheAPIAndVerifiedOnlyDropsUnverified() throws {
        let field = app.textFields["search.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))

        field.tap()
        field.typeText(address)
        let addressResult = result(containing: "Woudenbergseweg 42,")
        XCTAssertTrue(addressResult.waitForExistence(timeout: 15))
        XCTAssertTrue(addressResult.label.contains("Address"), addressResult.label)
        screenshot("02-search-address")

        app.buttons["Clear"].tap()
        field.typeText(station)
        let stationResult = result(containing: "Place")
        XCTAssertTrue(stationResult.waitForExistence(timeout: 15), "no MapKit place for \(station)")
        XCTAssertTrue(stationResult.label.localizedCaseInsensitiveContains("Amersfoort"), stationResult.label)
        screenshot("03-search-station")

        app.buttons["Clear"].tap()
        field.typeText(address)
        XCTAssertTrue(addressResult.waitForExistence(timeout: 15))
        addressResult.tap()

        let defaultRoute = try fetchRoute(verifiedOnly: false)
        XCTAssertGreaterThan(defaultRoute.totals["unverified"] ?? 0, 0, "the proof needs an unverified stretch")
        try assertPreviewShows(defaultRoute)
        sleep(4)
        screenshot("04-preview-default")

        let unverifiedRow = app.buttons["preview.total.unverified"]
        XCTAssertTrue(unverifiedRow.exists)
        unverifiedRow.tap()
        sleep(4)
        screenshot("05-preview-unverified-zoom")
        unverifiedRow.tap()

        let toggle = app.switches["preview.verifiedOnly"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        let verifiedRoute = try fetchRoute(verifiedOnly: true)
        XCTAssertEqual(verifiedRoute.totals["unverified"], 0)
        try assertPreviewShows(verifiedRoute)
        XCTAssertEqual(toggle.value as? String, "1")
        sleep(4)
        XCTAssertFalse(app.buttons["preview.total.unverified"].exists)
        screenshot("06-preview-verified-only")
    }

    private func result(containing text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier == 'search.result' AND label CONTAINS %@", text)).firstMatch
    }

    private func assertPreviewShows(_ route: APIRoute) throws {
        let rows = [
            ("carriageway", "Carriageway"),
            ("moped_path", "Moped path (G12a)"),
            ("unverified", "Unverified cycle path"),
        ]
        for (key, label) in rows {
            let expected = "\(label), \(Self.distance(route.totals[key] ?? -1))"
            let element = app.descendants(matching: .any)["preview.total.\(key)"]
            let shown = NSPredicate(format: "label == %@", expected)
            let match = expectation(for: shown, evaluatedWith: element)
            XCTAssertEqual(XCTWaiter.wait(for: [match], timeout: 30), .completed, "expected '\(expected)', shown '\(element.label)'")
        }
        let distance = app.staticTexts["preview.distance"]
        XCTAssertTrue(distance.label.hasPrefix("\(Self.distance(route.lengthM)), arrive "), distance.label)
        XCTAssertEqual(app.staticTexts["preview.duration"].label, Self.duration(route.durationS))
    }

    private struct APIRoute {
        let lengthM: Int
        let durationS: Double
        let totals: [String: Int]
    }

    private func fetchRoute(verifiedOnly: Bool) throws -> APIRoute {
        let environment = ProcessInfo.processInfo.environment
        guard let key = environment["NAVISCOOT_API_KEY"] else {
            throw XCTSkip("set TEST_RUNNER_NAVISCOOT_API_KEY to run the UI proof against the local API")
        }
        let base = environment["NAVISCOOT_API_BASE_URL"] ?? "http://127.0.0.1:8080"
        var request = URLRequest(url: URL(string: "\(base)/route")!)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "origin": ["lat": origin.lat, "lon": origin.lon],
            "destination": ["lat": destination.lat, "lon": destination.lon],
            "verified_only": verifiedOnly,
            "format": "osrm",
            "language": "nl-NL",
        ])

        var body: Data?
        let done = expectation(description: "route")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            body = data
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 60)

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(body)) as? [String: Any])
        let naviscoot = try XCTUnwrap(json["naviscoot"] as? [String: Any])
        let routes = try XCTUnwrap(json["routes"] as? [[String: Any]])
        return try APIRoute(
            lengthM: XCTUnwrap(naviscoot["length_m"] as? Int),
            durationS: XCTUnwrap(routes.first?["duration"] as? Double),
            totals: XCTUnwrap(naviscoot["totals_m"] as? [String: Int])
        )
    }

    private static func distance(_ meters: Int) -> String {
        meters < 1000 ? "\(meters) m" : String(format: "%.1f km", locale: Locale(identifier: "en_US_POSIX"), Double(meters) / 1000)
    }

    private static func duration(_ seconds: Double) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        return minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(minutes % 60) min"
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
