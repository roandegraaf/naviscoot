import XCTest

final class RideEditUITests: XCTestCase {
    private typealias Point = (lat: Double, lon: Double)

    private struct Place {
        let query: String
        let label: String
        let point: Point
    }

    private let domplein: Point = (52.0907, 5.1214)
    private let caseOrigin: Point = (52.2977646, 5.445363)
    private let amersfoort = Place(query: "Lieve Vrouwestraat 33 Amersfoort", label: "Lieve Vrouwestraat 33,", point: (52.15612897, 5.38786971))
    private let biltstraat = Place(query: "Biltstraat 100 Utrecht", label: "Biltstraat 100,", point: (52.09545846, 5.13137094))
    private let deBilt = Place(query: "Utrechtseweg 368-TR De Bilt", label: "Utrechtseweg 368-TR,", point: (52.09987599, 5.16170801))
    private let maarsbergen = Place(query: "Woudenbergseweg 42 Maarsbergen", label: "Woudenbergseweg 42,", point: (52.04779119, 5.40516261))
    private let unverifiedWay = 1_497_802_338
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        _ = try apiKey()
    }

    func testAStopAndANewDestinationAreAddedMidRideWithoutEndingItAndAFailedPlanKeepsTheOldRoute() throws {
        launch(origin: domplein, speedKmh: 45, verifiedOnly: true, editFailures: 1)
        planAndStart(to: amersfoort)
        let routeId = app.staticTexts["sim.routeId"]
        XCTAssertTrue(routeId.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["ride.banner.distance"].waitForExistence(timeout: 20))
        let options = app.staticTexts["sim.options"]
        let ridden = "verified_only=true ferries=false unpaved=false main_roads=false language=en"
        XCTAssertEqual(options.label, ridden)
        let nextStop = app.descendants(matching: .any)["ride.nextStop"]
        XCTAssertFalse(nextStop.exists)
        let original = routeId.label

        edit("Add a stop", place: biltstraat)
        let failed = app.descendants(matching: .any)["ride.editFailed"]
        XCTAssertTrue(failed.waitForExistence(timeout: 10), "a failed plan was not shown")
        XCTAssertEqual(failed.label, "Couldn't change the route. Cannot reach the route service. Guidance continues on the current route.")
        screenshot("edit-01-failed")
        XCTAssertEqual(routeId.label, original, "a failed plan replaced the route")
        XCTAssertFalse(nextStop.exists)
        assertGuidanceContinues()

        edit("Add a stop", place: biltstraat)
        wait(for: routeId, labelDiffersFrom: original, timeout: 30)
        wait(for: nextStop, labelEquals: "Next stop: Biltstraat 100", timeout: 10)
        XCTAssertTrue(app.buttons["ride.end"].exists, "the edit ended the ride")
        XCTAssertEqual(options.label, ridden, "the new route lost the ride's options")
        XCTAssertTrue(failed.waitForNonExistence(timeout: 5), "the old failure stayed after a working edit")
        assertGuidanceContinues()
        screenshot("edit-02-stop-added")
        let withStop = routeId.label

        edit("Change destination", place: deBilt)
        wait(for: routeId, labelDiffersFrom: withStop, timeout: 30)
        wait(for: nextStop, labelEquals: "Next stop: Biltstraat 100", timeout: 10)
        XCTAssertEqual(options.label, ridden)
        assertGuidanceContinues()
        screenshot("edit-03-destination-changed")

        let spoken = app.staticTexts["sim.spoken"]
        let stopLine = "en-GB|Arriving at your stop, Biltstraat 100. After that, on to your destination, Utrechtseweg 368-TR."
        wait(for: spoken, valueContains: stopLine, timeout: 180)
        XCTAssertTrue(nextStop.waitForNonExistence(timeout: 5), "the reached stop is still shown as next")
        XCTAssertEqual(spokenLines().filter { $0.contains("Arriving at your stop") }, [stopLine], spokenLines().joined(separator: "\n"))
        assertGuidanceContinues()
        screenshot("edit-04-added-stop-announced")

        app.terminate()
        launch(origin: biltstraat.point, speedKmh: 45, discardRide: false)
        let offer = app.alerts["Resume your ride?"]
        XCTAssertTrue(offer.waitForExistence(timeout: 10), "the edited ride was not saved")
        let message = offer.staticTexts.matching(NSPredicate(format: "label == %@", "On to Utrechtseweg 368-TR, from where you are now.")).firstMatch
        XCTAssertTrue(message.exists, offer.debugDescription)
        offer.buttons["End ride"].tap()
        XCTAssertTrue(offer.waitForNonExistence(timeout: 5))
    }

    func testANewDestinationMidRideWarnsForTheUnverifiedStretchOnItsRoute() throws {
        let start = try pointBeforeUnverifiedStretch(meters: 2500)
        let toAmersfoort = try fetchUnverifiedWays(from: start, to: amersfoort.point)
        XCTAssertFalse(toAmersfoort.contains(unverifiedWay), "the first route already crosses the stretch")
        let toMaarsbergen = try fetchUnverifiedWays(from: start, to: maarsbergen.point)
        XCTAssertTrue(toMaarsbergen.contains(unverifiedWay), "the new route no longer crosses the stretch")

        launch(origin: start, speedKmh: 90)
        planAndStart(to: amersfoort)
        let routeId = app.staticTexts["sim.routeId"]
        XCTAssertTrue(routeId.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["ride.banner.distance"].waitForExistence(timeout: 20))
        let original = routeId.label
        XCTAssertFalse(spokenLines().contains { $0.contains("unverified") })

        edit("Change destination", place: maarsbergen)
        wait(for: routeId, labelDiffersFrom: original, timeout: 30)
        XCTAssertTrue(app.buttons["ride.end"].exists)

        let warning = app.descendants(matching: .any)["ride.warning"]
        XCTAssertTrue(warning.waitForExistence(timeout: 150), "no warning for the new route's unverified stretch")
        XCTAssertTrue(warning.label.hasPrefix("Unverified path in "), warning.label)
        let spoken = app.staticTexts["sim.spoken"]
        wait(for: spoken, valueContains: "an unverified cycle path of", timeout: 10)
        XCTAssertEqual(spokenLines().filter { $0.contains("unverified cycle path") }.count, 1, spokenLines().joined(separator: "\n"))
        screenshot("edit-05-new-route-warning")

        app.terminate()
        launch(origin: start, speedKmh: 90, discardRide: false)
        let offer = app.alerts["Resume your ride?"]
        XCTAssertTrue(offer.waitForExistence(timeout: 10))
        XCTAssertTrue(offer.staticTexts.matching(NSPredicate(format: "label == %@", "On to Woudenbergseweg 42, from where you are now.")).firstMatch.exists, offer.debugDescription)
        offer.buttons["End ride"].tap()
    }

    func testDraggingTheMapStopsFollowingUntilRecenterAndOverviewFitsTheRemainingRoute() throws {
        launch(origin: domplein, speedKmh: 30)
        planAndStart(to: amersfoort)
        let distance = app.staticTexts["ride.banner.distance"]
        XCTAssertTrue(distance.waitForExistence(timeout: 20))
        let camera = app.staticTexts["sim.camera"]
        wait(for: camera, labelBeginsWith: "camera=following center=", timeout: 15)
        let following = camera.label
        wait(for: camera, labelDiffersFrom: following, timeout: 15)
        let recenter = app.buttons["ride.recenter"]
        XCTAssertFalse(recenter.exists)

        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.56))
        from.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.46)))
        wait(for: camera, labelBeginsWith: "camera=free", timeout: 10)
        XCTAssertTrue(recenter.waitForExistence(timeout: 5), "no recenter after dragging")
        sleep(2)
        let parked = camera.label
        for _ in 0 ..< 2 {
            let shown = distance.label
            wait(for: distance, labelDiffersFrom: shown, timeout: 30)
        }
        XCTAssertEqual(camera.label, parked, "the map moved on its own after the drag")
        screenshot("camera-01-dragged")

        recenter.tap()
        wait(for: camera, labelBeginsWith: "camera=following", timeout: 10)
        XCTAssertTrue(recenter.waitForNonExistence(timeout: 5))
        let parkedCenter = Self.center(in: parked)
        let moved = expectation(for: NSPredicate { _, _ in Self.center(in: camera.label) != parkedCenter }, evaluatedWith: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 10), .completed, "recenter did not move the map back to the rider")
        let recentered = camera.label
        wait(for: camera, labelDiffersFrom: recentered, timeout: 15)
        screenshot("camera-02-recentered")

        app.buttons["ride.overview"].tap()
        wait(for: camera, labelBeginsWith: "camera=overview", timeout: 10)
        sleep(3)
        screenshot("camera-03-overview")
        wait(for: camera, labelEndsWith: "fits=true", timeout: 10)
        XCTAssertTrue(recenter.exists)

        recenter.tap()
        wait(for: camera, labelBeginsWith: "camera=following", timeout: 10)
        XCTAssertTrue(recenter.waitForNonExistence(timeout: 5))
        let back = camera.label
        wait(for: camera, labelDiffersFrom: back, timeout: 15)
        screenshot("camera-04-following-again")

        app.buttons["ride.end"].tap()
        app.alerts.buttons["End ride"].tap()
        XCTAssertTrue(app.textFields["search.field"].waitForExistence(timeout: 10))
    }

    private func launch(origin: Point, speedKmh: Int, verifiedOnly: Bool = false, editFailures: Int = 0, discardRide: Bool = true) {
        app = XCUIApplication()
        var arguments = [
            "-NaviscootSimulateRide", "YES",
            "-NaviscootSimSpeedKmh", "\(speedKmh)",
            "-NaviscootSimOrigin", "\(origin.lat),\(origin.lon)",
            "-NaviscootSimEditFailures", "\(editFailures)",
            "-settings.language", "en",
            "-settings.verifiedOnlyByDefault", verifiedOnly ? "YES" : "NO",
            "-settings.avoidFerries", "NO",
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

    private func planAndStart(to destination: Place) {
        let field = app.textFields["search.field"]
        field.tap()
        field.typeText(destination.query)
        let result = self.result(containing: destination.label)
        XCTAssertTrue(result.waitForExistence(timeout: 15), "no result for \(destination.query)")
        result.tap()
        let start = app.buttons["preview.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 60), "Start is not offered")
        start.tap()
        XCTAssertTrue(app.buttons["ride.end"].waitForExistence(timeout: 10))
    }

    private func edit(_ action: String, place: Place) {
        let menu = app.buttons["ride.edit"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        XCTAssertTrue(menu.isEnabled, "the edit menu is disabled")
        menu.tap()
        let id = action == "Add a stop" ? "ride.edit.addStop" : "ride.edit.changeDestination"
        let item = app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@", id, action)).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "no '\(action)' in the edit menu")
        item.tap()
        let search = app.textFields["placeSearch.field"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars[action].exists, "the search sheet is not titled '\(action)'")
        search.tap()
        search.typeText(place.query)
        let match = result(containing: place.label)
        XCTAssertTrue(match.waitForExistence(timeout: 15), "no result for \(place.query)")
        match.tap()
        XCTAssertTrue(search.waitForNonExistence(timeout: 10))
    }

    private func assertGuidanceContinues() {
        let distance = app.staticTexts["ride.banner.distance"]
        XCTAssertTrue(distance.waitForExistence(timeout: 20), "guidance stopped")
        wait(for: distance, labelDiffersFrom: distance.label, timeout: 30)
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

    private func wait(for element: XCUIElement, labelDiffersFrom text: String, timeout: TimeInterval) {
        let match = expectation(for: NSPredicate(format: "label != %@", text), evaluatedWith: element)
        XCTAssertEqual(XCTWaiter.wait(for: [match], timeout: timeout), .completed, "'\(text)' did not change")
    }

    private func wait(for element: XCUIElement, labelBeginsWith text: String, timeout: TimeInterval) {
        let match = expectation(for: NSPredicate(format: "label BEGINSWITH %@", text), evaluatedWith: element)
        XCTAssertEqual(XCTWaiter.wait(for: [match], timeout: timeout), .completed, "expected '\(text)…', shown '\(element.label)'")
    }

    private func wait(for element: XCUIElement, labelEndsWith text: String, timeout: TimeInterval) {
        let match = expectation(for: NSPredicate(format: "label ENDSWITH %@", text), evaluatedWith: element)
        XCTAssertEqual(XCTWaiter.wait(for: [match], timeout: timeout), .completed, "expected '…\(text)', shown '\(element.label)'")
    }

    private static func center(in label: String) -> String? {
        label.range(of: #"center=[0-9.,-]+"#, options: .regularExpression).map { String(label[$0]) }
    }

    private func apiKey() throws -> String {
        guard let key = ProcessInfo.processInfo.environment["NAVISCOOT_API_KEY"] else {
            throw XCTSkip("set TEST_RUNNER_NAVISCOOT_API_KEY to run the mid-ride edit proof against the local API")
        }
        return key
    }

    private func pointBeforeUnverifiedStretch(meters: Double) throws -> Point {
        let route = try fetchRoute(from: caseOrigin, to: maarsbergen.point)
        let stretches = try XCTUnwrap(route["stretches"] as? [[String: Any]])
        let geometry = try XCTUnwrap(route["geometry"] as? [Point])
        let stretch = try XCTUnwrap(stretches.first { $0["class"] as? String == "unverified" })
        var index = try XCTUnwrap(stretch["start_shape_index"] as? Int)
        var travelled = 0.0
        while index > 0, travelled < meters {
            travelled += Self.distance(geometry[index - 1], geometry[index])
            index -= 1
        }
        return geometry[index]
    }

    private func fetchUnverifiedWays(from origin: Point, to destination: Point) throws -> [Int] {
        let stretches = try XCTUnwrap(fetchRoute(from: origin, to: destination)["stretches"] as? [[String: Any]])
        return stretches.filter { $0["class"] as? String == "unverified" }.flatMap { $0["way_ids"] as? [Int] ?? [] }
    }

    private func fetchRoute(from origin: Point, to destination: Point) throws -> [String: Any] {
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
        ])
        var data: Data?
        let done = expectation(description: "route")
        URLSession.shared.dataTask(with: request) { body, _, _ in
            data = body
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 90)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(data)) as? [String: Any])
        let meta = try XCTUnwrap(json["naviscoot"] as? [String: Any], "\(json)")
        let routes = try XCTUnwrap(json["routes"] as? [[String: Any]])
        let polyline = try XCTUnwrap(routes.first?["geometry"] as? String)
        return ["stretches": meta["stretches"] as Any, "geometry": Self.decodePolyline6(polyline)]
    }

    private static func decodePolyline6(_ encoded: String) -> [Point] {
        var points: [Point] = []
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

    private static func distance(_ a: Point, _ b: Point) -> Double {
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
