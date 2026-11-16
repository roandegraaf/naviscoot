import XCTest

final class StopRideUITests: XCTestCase {
    private typealias Point = (lat: Double, lon: Double)

    private struct Place {
        let query: String
        let label: String
        let point: Point
    }

    private let domplein: Point = (52.0907, 5.1214)
    private let amersfoort = Place(query: "Lieve Vrouwestraat 33 Amersfoort", label: "Lieve Vrouwestraat 33,", point: (52.15612897, 5.38786971))
    private let biltstraat = Place(query: "Biltstraat 100 Utrecht", label: "Biltstraat 100,", point: (52.09545846, 5.13137094))
    private let deBilt = Place(query: "Utrechtseweg 368-TR De Bilt", label: "Utrechtseweg 368-TR,", point: (52.09987599, 5.16170801))
    private let soesterberg = Place(query: "Kampweg 1 Soesterberg", label: "Kampweg 1,", point: (52.12033201, 5.28612696))
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        _ = try apiKey()
    }

    func testARideThroughTwoStopsAnnouncesEachAndContinuesAndEndAsksFirst() throws {
        launch(origin: domplein)
        planAndStart(stops: [biltstraat, deBilt])

        let nextStop = app.descendants(matching: .any)["ride.nextStop"]
        XCTAssertTrue(nextStop.waitForExistence(timeout: 10))
        XCTAssertEqual(nextStop.label, "Next stop: Biltstraat 100")
        screenshot("stops-01-ride-next-stop")

        let routeId = app.staticTexts["sim.routeId"]
        XCTAssertTrue(routeId.waitForExistence(timeout: 10))
        let firstRoute = routeId.label
        app.buttons["sim.detour"].tap()
        let rerouted = expectation(for: NSPredicate(format: "label != %@", firstRoute), evaluatedWith: routeId)
        XCTAssertEqual(XCTWaiter.wait(for: [rerouted], timeout: 40), .completed, "no reroute after the detour")
        XCTAssertTrue(app.staticTexts["sim.status"].label.hasSuffix("reroutes 1"), app.staticTexts["sim.status"].label)
        XCTAssertEqual(nextStop.label, "Next stop: Biltstraat 100", "the reroute dropped the stop")
        XCTAssertFalse(spokenLines().contains { $0.contains("Arriving at your stop") }, "the reroute skipped the stop")

        let spoken = app.staticTexts["sim.spoken"]
        let first = "en-GB|Arriving at your stop, Biltstraat 100. After that, on to Utrechtseweg 368-TR."
        wait(for: spoken, valueContains: first, timeout: 120)
        wait(for: nextStop, labelEquals: "Next stop: Utrechtseweg 368-TR", timeout: 5)
        assertGuidanceContinues()
        screenshot("stops-02a-first-stop-passed")

        let second = "en-GB|Arriving at your stop, Utrechtseweg 368-TR. After that, on to your destination, Lieve Vrouwestraat 33."
        wait(for: spoken, valueContains: second, timeout: 150)
        XCTAssertTrue(nextStop.waitForNonExistence(timeout: 5), "the reached stop is still shown as next")
        assertGuidanceContinues()
        let stopLines = spokenLines().filter { $0.contains("Arriving at your stop") }
        XCTAssertEqual(stopLines, [first, second], spokenLines().joined(separator: "\n"))
        XCTAssertFalse(spokenLines().contains { !$0.hasPrefix("en-GB|") }, spokenLines().joined(separator: "\n"))
        screenshot("stops-02-stop-passed")

        app.buttons["ride.end"].tap()
        let confirmation = app.alerts["End this ride?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5), "End did not ask first")
        screenshot("stops-03-end-confirmation")
        confirmation.buttons["Keep riding"].tap()
        XCTAssertTrue(confirmation.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["ride.end"].exists, "Keep riding ended the ride")
        assertGuidanceContinues()

        app.buttons["ride.end"].tap()
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.buttons["End ride"].tap()
        XCTAssertTrue(app.textFields["search.field"].waitForExistence(timeout: 10))

        app.terminate()
        launch(origin: domplein, discardRide: false)
        XCTAssertFalse(app.alerts["Resume your ride?"].waitForExistence(timeout: 4), "an ended ride was offered for resuming")
    }

    func testInDutchTheStopIsAnnouncedInDutch() throws {
        launch(origin: domplein, language: "nl")
        planAndStart(stops: [biltstraat])

        let nextStop = app.descendants(matching: .any)["ride.nextStop"]
        XCTAssertTrue(nextStop.waitForExistence(timeout: 10))
        XCTAssertEqual(nextStop.label, "Volgende stop: Biltstraat 100")
        let spoken = app.staticTexts["sim.spoken"]
        wait(for: spoken, valueContains: "nl-NL|Je komt aan bij je tussenstop, Biltstraat 100. Daarna door naar je bestemming, Lieve Vrouwestraat 33.", timeout: 120)
        XCTAssertTrue(nextStop.waitForNonExistence(timeout: 5))
        assertGuidanceContinues()
        XCTAssertFalse(spokenLines().contains { !$0.hasPrefix("nl-NL|") }, spokenLines().joined(separator: "\n"))
        screenshot("nl-stops-02-stop-passed")

        app.buttons["ride.end"].tap()
        let confirmation = app.alerts["Deze rit stoppen?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        screenshot("nl-stops-03-end-confirmation")
        confirmation.buttons["Rit stoppen"].tap()
        XCTAssertTrue(app.textFields["search.field"].waitForExistence(timeout: 10))
    }

    func testAKilledRideWithAStopLeftResumesFromHereWithTheSameOptions() throws {
        launch(origin: domplein, verifiedOnly: true, avoidFerries: true)
        planAndStart(stops: [biltstraat, soesterberg])
        let options = app.staticTexts["sim.options"]
        XCTAssertTrue(options.waitForExistence(timeout: 10))
        let ridden = "verified_only=true ferries=true unpaved=false main_roads=false language=en"
        XCTAssertEqual(options.label, ridden)

        let spoken = app.staticTexts["sim.spoken"]
        wait(for: spoken, valueContains: "en-GB|Arriving at your stop, Biltstraat 100. After that, on to Kampweg 1.", timeout: 120)
        let nextStop = app.descendants(matching: .any)["ride.nextStop"]
        wait(for: nextStop, labelEquals: "Next stop: Kampweg 1", timeout: 5)
        let routeBefore = app.staticTexts["sim.routeId"].label

        app.terminate()
        launch(origin: biltstraat.point, discardRide: false)
        let offer = app.alerts["Resume your ride?"]
        XCTAssertTrue(offer.waitForExistence(timeout: 10), "the killed ride was not offered")
        let message = offer.staticTexts.matching(NSPredicate(format: "label == %@", "On to Lieve Vrouwestraat 33 via Kampweg 1, from where you are now.")).firstMatch
        XCTAssertTrue(message.exists, offer.debugDescription)
        screenshot("stops-04-resume-offer")
        offer.buttons["Resume"].tap()

        XCTAssertTrue(app.buttons["ride.end"].waitForExistence(timeout: 60), "the resumed ride did not start")
        wait(for: nextStop, labelEquals: "Next stop: Kampweg 1", timeout: 10)
        XCTAssertEqual(options.label, ridden, "the resumed ride did not keep its own options")
        XCTAssertNotEqual(app.staticTexts["sim.routeId"].label, routeBefore)

        let expected = try fetchLengthM(from: biltstraat.point, to: amersfoort.point, stops: [soesterberg.point], verifiedOnly: true, avoid: ["ferries": true])
        let remaining = app.descendants(matching: .any)["ride.remaining"]
        let shownKm = try XCTUnwrap(Self.kilometres(in: remaining.label), remaining.label)
        XCTAssertEqual(shownKm * 1000, Double(expected), accuracy: 1500, "the resumed route does not start here: \(remaining.label)")
        assertGuidanceContinues()
        screenshot("stops-05-resumed")

        app.buttons["ride.end"].tap()
        app.alerts.buttons["End ride"].tap()
        XCTAssertTrue(app.textFields["search.field"].waitForExistence(timeout: 10))
    }

    func testDecliningTheResumeOfferForgetsTheRide() throws {
        launch(origin: domplein)
        planAndStart(stops: [])
        XCTAssertTrue(app.staticTexts["ride.banner.distance"].waitForExistence(timeout: 20))

        app.terminate()
        launch(origin: domplein, discardRide: false)
        let offer = app.alerts["Resume your ride?"]
        XCTAssertTrue(offer.waitForExistence(timeout: 10))
        offer.buttons["End ride"].tap()
        XCTAssertTrue(offer.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons["ride.end"].exists)

        app.terminate()
        launch(origin: domplein, discardRide: false)
        XCTAssertFalse(app.alerts["Resume your ride?"].waitForExistence(timeout: 4), "a declined ride was offered again")
    }

    private func launch(origin: Point, language: String = "en", verifiedOnly: Bool = false, avoidFerries: Bool = false, discardRide: Bool = true) {
        app = XCUIApplication()
        var arguments = [
            "-NaviscootSimulateRide", "YES",
            "-NaviscootSimSpeedKmh", "120",
            "-NaviscootSimOrigin", "\(origin.lat),\(origin.lon)",
            "-settings.language", language,
            "-settings.verifiedOnlyByDefault", verifiedOnly ? "YES" : "NO",
            "-settings.avoidFerries", avoidFerries ? "YES" : "NO",
            "-settings.avoidUnpaved", "NO",
            "-settings.avoidMainRoads", "NO",
        ]
        if discardRide {
            arguments += ["-NaviscootDiscardActiveRide", "YES"]
        }
        app.launchArguments = arguments
        app.launch()
        XCTAssertTrue(app.textFields["search.field"].waitForExistence(timeout: 10))
    }

    private func planAndStart(stops: [Place]) {
        let field = app.textFields["search.field"]
        field.tap()
        field.typeText(amersfoort.query)
        let result = self.result(containing: amersfoort.label)
        XCTAssertTrue(result.waitForExistence(timeout: 15), "no result for \(amersfoort.query)")
        result.tap()
        XCTAssertTrue(app.buttons["preview.back"].waitForExistence(timeout: 10))
        for stop in stops {
            let add = app.buttons["preview.addStop"]
            XCTAssertTrue(add.waitForExistence(timeout: 30))
            add.tap()
            let search = app.textFields["placeSearch.field"]
            XCTAssertTrue(search.waitForExistence(timeout: 5))
            search.tap()
            search.typeText(stop.query)
            let match = self.result(containing: stop.label)
            XCTAssertTrue(match.waitForExistence(timeout: 15), "no result for \(stop.query)")
            match.tap()
            XCTAssertTrue(search.waitForNonExistence(timeout: 10))
        }
        let start = app.buttons["preview.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 60), "Start is not offered")
        start.tap()
        XCTAssertTrue(app.buttons["ride.end"].waitForExistence(timeout: 10))
    }

    private func assertGuidanceContinues() {
        let distance = app.staticTexts["ride.banner.distance"]
        XCTAssertTrue(distance.waitForExistence(timeout: 20), "guidance stopped")
        let first = distance.label
        let moved = expectation(for: NSPredicate(format: "label != %@", first), evaluatedWith: distance)
        XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 30), .completed, "guidance did not continue")
        XCTAssertNotEqual(app.staticTexts["ride.banner.street"].label, "You have arrived")
    }

    private func result(containing text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier == 'search.result' AND label CONTAINS %@", text)).firstMatch
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

    private static func kilometres(in label: String) -> Double? {
        guard let range = label.range(of: #"[0-9]+(\.[0-9])? km"#, options: .regularExpression) else { return nil }
        return Double(label[range].dropLast(3))
    }

    private func apiKey() throws -> String {
        guard let key = ProcessInfo.processInfo.environment["NAVISCOOT_API_KEY"] else {
            throw XCTSkip("set TEST_RUNNER_NAVISCOOT_API_KEY to run the stop ride proof against the local API")
        }
        return key
    }

    private func fetchLengthM(from origin: Point, to destination: Point, stops: [Point], verifiedOnly: Bool, avoid: [String: Bool]) throws -> Int {
        let base = ProcessInfo.processInfo.environment["NAVISCOOT_API_BASE_URL"] ?? "http://127.0.0.1:8080"
        var request = URLRequest(url: URL(string: "\(base)/route")!)
        request.httpMethod = "POST"
        request.setValue(try apiKey(), forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "origin": ["lat": origin.lat, "lon": origin.lon],
            "destination": ["lat": destination.lat, "lon": destination.lon],
            "waypoints": stops.map { ["lat": $0.lat, "lon": $0.lon] },
            "verified_only": verifiedOnly,
            "avoid": avoid,
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
