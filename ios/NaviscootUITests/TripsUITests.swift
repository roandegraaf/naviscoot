import XCTest

final class TripsUITests: XCTestCase {
    private typealias Point = (lat: Double, lon: Double)

    private let domplein: Point = (52.0907, 5.1214)
    private let biltstraat = (query: "Biltstraat 100 Utrecht", label: "Biltstraat 100,", title: "Biltstraat 100", point: (lat: 52.09545846, lon: 5.13137094))
    private let amersfoort = (query: "Lieve Vrouwestraat 33 Amersfoort", label: "Lieve Vrouwestraat 33,", title: "Lieve Vrouwestraat 33")
    private let speedKmh = 60.0
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        _ = try apiKey()
    }

    func testARideToArrivalIsRecordedOpensToItsTrackCountsInTheTotalsSurvivesARelaunchAndCanBeDeleted() throws {
        launch(resetTrips: true)
        assertNoRecentTrips("the reset store still has trips")
        screenshot("trips-01-empty")

        let routeM = try fetchLengthM(from: domplein, to: biltstraat.point)
        planAndStart(query: biltstraat.query, label: biltstraat.label)
        let street = app.staticTexts["ride.banner.street"]
        let arrived = expectation(for: NSPredicate(format: "label == 'You have arrived'"), evaluatedWith: street)
        XCTAssertEqual(XCTWaiter.wait(for: [arrived], timeout: 240), .completed, "the ride did not arrive")
        app.buttons["ride.end"].tap()
        XCTAssertTrue(app.textFields["search.field"].waitForExistence(timeout: 10))

        openHistory()
        let row = app.buttons["trips.trip.0"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the arrived ride was not recorded")
        XCTAssertFalse(app.buttons["trips.trip.1"].exists)
        XCTAssertTrue(row.label.hasPrefix(biltstraat.title), row.label)
        XCTAssertTrue(row.label.contains("km/h"), row.label)
        let values = try Self.values(row)
        let distance = try XCTUnwrap(values["distanceM"]), duration = try XCTUnwrap(values["durationS"]), average = try XCTUnwrap(values["avgKmh"])
        XCTAssertEqual(distance, Double(routeM), accuracy: Double(routeM) * 0.15, "ridden distance vs the route's \(routeM) m")
        XCTAssertEqual(average, speedKmh, accuracy: 12, "average speed of a \(speedKmh) km/h simulated ride")
        XCTAssertEqual(duration, distance / (average / 3.6), accuracy: 1.5)
        XCTAssertGreaterThan(duration, 30)

        XCTAssertEqual(app.descendants(matching: .any)["trips.total.count"].value as? String, "1")
        XCTAssertEqual(Double(app.descendants(matching: .any)["trips.total.distance"].value as? String ?? "") ?? -1, distance.rounded(), accuracy: 1)
        XCTAssertEqual(Double(app.descendants(matching: .any)["trips.total.time"].value as? String ?? "") ?? -1, duration.rounded(), accuracy: 1)
        XCTAssertEqual(Double(app.descendants(matching: .any)["trips.total.speed"].value as? String ?? "") ?? 0, average, accuracy: 0.15)
        screenshot("trips-02-history")

        row.tap()
        XCTAssertEqual(app.staticTexts["trip.destination"].waitForExistence(timeout: 5) ? app.staticTexts["trip.destination"].label : nil, biltstraat.title)
        let map = app.descendants(matching: .any)["trip.map"]
        XCTAssertTrue(map.waitForExistence(timeout: 5))
        let drawn = expectation(for: NSPredicate(format: "value MATCHES %@", #"segments=1 points=\d+ features=[1-9]\d*"#), evaluatedWith: map)
        XCTAssertEqual(XCTWaiter.wait(for: [drawn], timeout: 20), .completed, "the track is not drawn: \(map.value ?? "nil")")
        let points = Int((map.value as? String ?? "").components(separatedBy: "points=").last?.components(separatedBy: " ").first ?? "") ?? 0
        XCTAssertGreaterThan(points, 20, "a 1.4 km ride sampled every ≤ 15 m")
        XCTAssertTrue(app.descendants(matching: .any)["trip.distance"].label.contains(" km"), app.descendants(matching: .any)["trip.distance"].label)
        screenshot("trips-03-track")

        app.terminate()
        launch(resetTrips: false)
        openHistory()
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the trip did not survive a relaunch")
        XCTAssertEqual(try Self.values(row)["distanceM"], distance)

        row.swipeLeft()
        let delete = app.buttons.matching(NSPredicate(format: "identifier == 'trips.delete' OR label == 'Delete'")).firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "no delete action")
        delete.tap()
        XCTAssertTrue(app.staticTexts["trips.empty"].waitForExistence(timeout: 5), "the trip was not deleted")
        screenshot("trips-04-deleted")

        app.terminate()
        launch(resetTrips: false)
        assertNoRecentTrips("a deleted trip came back after a relaunch")
    }

    func testARideEndedThroughTheAlertIsRecordedAndANearEmptyOneIsNot() throws {
        launch(resetTrips: true)
        planAndStart(query: amersfoort.query, label: amersfoort.label)
        endThroughTheAlert()
        assertNoRecentTrips("a ride ended at once was recorded")

        planAndStart(query: amersfoort.query, label: amersfoort.label)
        XCTAssertTrue(app.staticTexts["ride.banner.distance"].waitForExistence(timeout: 20))
        Thread.sleep(forTimeInterval: 45)
        endThroughTheAlert()

        openHistory()
        let row = app.buttons["trips.trip.0"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the ended ride was not recorded")
        XCTAssertFalse(app.buttons["trips.trip.1"].exists, "the near-empty ride was recorded after all")
        XCTAssertTrue(row.label.hasPrefix(amersfoort.title), row.label)
        let values = try Self.values(row)
        let distance = try XCTUnwrap(values["distanceM"]), duration = try XCTUnwrap(values["durationS"]), average = try XCTUnwrap(values["avgKmh"])
        XCTAssertGreaterThan(duration, 35)
        XCTAssertLessThan(duration, 90)
        XCTAssertEqual(average, speedKmh, accuracy: 12)
        XCTAssertGreaterThan(distance, 500)
        XCTAssertEqual(app.descendants(matching: .any)["trips.total.count"].value as? String, "1")
        screenshot("trips-05-ended-ride")
    }

    private func launch(resetTrips: Bool) {
        app = XCUIApplication()
        app.launchArguments = [
            "-NaviscootSimulateRide", "YES",
            "-NaviscootSimSpeedKmh", "\(Int(speedKmh))",
            "-NaviscootSimOrigin", "\(domplein.lat),\(domplein.lon)",
            "-NaviscootDiscardActiveRide", "YES",
            "-settings.language", "en",
            "-settings.verifiedOnlyByDefault", "NO",
            "-settings.avoidFerries", "NO",
            "-settings.avoidUnpaved", "NO",
            "-settings.avoidMainRoads", "NO",
        ]
        if resetTrips {
            app.launchArguments += ["-NaviscootResetTrips", "YES"]
        }
        app.launch()
        XCTAssertTrue(app.textFields["search.field"].waitForExistence(timeout: 10))
    }

    private func openHistory() {
        let button = app.buttons["home.trips.all"]
        XCTAssertTrue(app.scrollViews["home.drawer"].waitForExistence(timeout: 10))
        for _ in 0 ..< 6 where !(button.exists && button.isHittable) {
            app.scrollViews["home.drawer"].swipeUp()
        }
        XCTAssertTrue(button.exists, "the drawer has no recent trips")
        button.tap()
        XCTAssertTrue(app.buttons["trips.done"].waitForExistence(timeout: 5), "trip history did not open")
    }

    private func assertNoRecentTrips(_ message: String) {
        XCTAssertTrue(app.textFields["search.field"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["home.home"].waitForExistence(timeout: 5), "the drawer content did not load")
        XCTAssertFalse(app.buttons["home.trips.all"].exists, message)
    }

    private func planAndStart(query: String, label: String) {
        let field = app.textFields["search.field"]
        field.tap()
        field.typeText(query)
        let result = app.buttons.matching(NSPredicate(format: "identifier == 'search.result' AND label CONTAINS %@", label)).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 15), "no result for \(query)")
        result.tap()
        let start = app.buttons["preview.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 60), "Start is not offered")
        start.tap()
        XCTAssertTrue(app.buttons["ride.end"].waitForExistence(timeout: 10))
    }

    private func endThroughTheAlert() {
        app.buttons["ride.end"].tap()
        let confirm = app.alerts.buttons.matching(identifier: "End ride").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "End did not ask first")
        confirm.tap()
        XCTAssertTrue(app.textFields["search.field"].waitForExistence(timeout: 10))
        if app.buttons["search.clear"].exists {
            app.buttons["search.clear"].tap()
        }
    }

    private static func values(_ element: XCUIElement) throws -> [String: Double] {
        let value = try XCTUnwrap(element.value as? String, "no value on \(element.identifier)")
        var result: [String: Double] = [:]
        for pair in value.split(separator: " ") {
            let parts = pair.split(separator: "=")
            if parts.count == 2, let number = Double(parts[1]) { result[String(parts[0])] = number }
        }
        return result
    }

    private func apiKey() throws -> String {
        guard let key = ProcessInfo.processInfo.environment["NAVISCOOT_API_KEY"] else {
            throw XCTSkip("set TEST_RUNNER_NAVISCOOT_API_KEY to run the trip history proof against the local API")
        }
        return key
    }

    private func fetchLengthM(from origin: Point, to destination: Point) throws -> Int {
        let base = ProcessInfo.processInfo.environment["NAVISCOOT_API_BASE_URL"] ?? "http://127.0.0.1:8080"
        var request = URLRequest(url: URL(string: "\(base)/route")!)
        request.httpMethod = "POST"
        request.setValue(try apiKey(), forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "origin": ["lat": origin.lat, "lon": origin.lon],
            "destination": ["lat": destination.lat, "lon": destination.lon],
            "verified_only": false,
            "format": "osrm",
            "language": "en-GB",
        ] as [String: Any])
        var data: Data?
        let done = expectation(description: "route")
        URLSession.shared.dataTask(with: request) { body, _, _ in
            data = body
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 90)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(data)) as? [String: Any])
        let meta = try XCTUnwrap(json["naviscoot"] as? [String: Any], "\(json)")
        return try XCTUnwrap(meta["length_m"] as? Int)
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
