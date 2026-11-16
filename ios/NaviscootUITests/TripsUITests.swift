import XCTest

final class TripsUITests: XCTestCase {
    private let domplein = (lat: 52.0907, lon: 5.1214)
    private let amersfoort = (query: "Lieve Vrouwestraat 33 Amersfoort", label: "Lieve Vrouwestraat 33,", title: "Lieve Vrouwestraat 33")
    private let speedKmh = 60.0
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard ProcessInfo.processInfo.environment["NAVISCOOT_API_KEY"] != nil else {
            throw XCTSkip("set TEST_RUNNER_NAVISCOOT_API_KEY to run the trip history proof against the API")
        }
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
        XCTAssertTrue(app.buttons["ride.panel.toggle"].waitForExistence(timeout: 10))
    }

    private func endThroughTheAlert() {
        XCTAssertTrue(app.staticTexts["ride.banner.distance"].waitForExistence(timeout: 20))
        let end = app.buttons["ride.end"]
        for _ in 0 ..< 3 where !(end.exists && end.isHittable) {
            app.buttons["ride.panel.toggle"].tap()
            let opened = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: end)
            _ = XCTWaiter.wait(for: [opened], timeout: 3)
        }
        XCTAssertTrue(end.isHittable, "the ride panel did not open")
        end.tap()
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
