import XCTest

final class TripPlannerUITests: XCTestCase {
    private typealias Point = (lat: Double, lon: Double)

    private struct Place {
        let query: String
        let label: String
        let point: Point
    }

    private struct APIRoute {
        let lengthM: Int
        let durationS: Double
        let unverifiedM: Int
        let carriagewayM: Int
        let allUnavoidable: Bool
    }

    private let caseOrigin: Point = (52.2977646, 5.445363)
    private let domplein: Point = (52.0907, 5.1214)
    private let maarsbergen = Place(query: "Woudenbergseweg 42 Maarsbergen", label: "Woudenbergseweg 42,", point: (52.04779119, 5.40516261))
    private let amersfoort = Place(query: "Lieve Vrouwestraat 33 Amersfoort", label: "Lieve Vrouwestraat 33,", point: (52.15612897, 5.38786971))
    private let zeist = Place(query: "Slotlaan 10 Zeist", label: "Slotlaan 10,", point: (52.08235683, 5.24011346))
    private let soesterberg = Place(query: "Kampweg 1 Soesterberg", label: "Kampweg 1,", point: (52.12033201, 5.28612696))
    private let centraal = Place(query: "Stationsplein 19P-1 Amsterdam", label: "Stationsplein 19P-1,", point: (52.37886601, 4.89969163))
    private let badhuiskade = Place(query: "Badhuiskade 15 Amsterdam", label: "Badhuiskade 15,", point: (52.38455882, 4.90447288))
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        _ = try apiKey()
    }

    func testAlternativesAreListedAndStartRidesTheSelectedOne() throws {
        launch(origin: caseOrigin)
        searchDestination(maarsbergen)

        let routes = try fetchRoutes(from: caseOrigin, to: maarsbergen.point, alternatives: 2)
        XCTAssertGreaterThan(routes.count, 1, "the proof needs alternatives")
        XCTAssertTrue(routes.contains { $0.unverifiedM > 0 }, "the proof needs an unverified route")
        assertCards(routes, verifiedOnly: false)
        try assertPreviewShows(routes[0])
        sleep(3)
        screenshot("planner-01-alternatives")

        card(1).tap()
        try assertPreviewShows(routes[1])
        XCTAssertTrue(card(1).isSelected)
        XCTAssertFalse(card(0).isSelected)
        sleep(2)
        screenshot("planner-02-alternative-selected")

        let toggle = app.switches["preview.verifiedOnly"]
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        let verified = try fetchRoutes(from: caseOrigin, to: maarsbergen.point, alternatives: 2, verifiedOnly: true)
        XCTAssertGreaterThan(verified.count, 1)
        assertCards(verified, verifiedOnly: true)
        try assertPreviewShows(verified[0])
        sleep(2)
        screenshot("planner-03-alternatives-verified-only")

        let chosen = card(1)
        chosen.tap()
        try assertPreviewShows(verified[1])
        let routeId = String(chosen.identifier.split(separator: ".").last ?? "")
        XCTAssertEqual(routeId.count, 36, chosen.identifier)
        app.buttons["preview.start"].tap()
        let shownId = app.staticTexts["sim.routeId"]
        XCTAssertTrue(shownId.waitForExistence(timeout: 10))
        XCTAssertEqual(shownId.label, routeId, "Start did not hand the selected route to guidance")
        screenshot("planner-04-ride-on-selected-route")
        app.buttons["ride.end"].tap()
        let confirm = app.alerts.buttons["End ride"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.textFields["search.field"].waitForExistence(timeout: 10))
    }

    func testTwoStopsAreRoutedInOrderAndTheTimeCanBeSet() throws {
        launch(origin: domplein)
        searchDestination(amersfoort)
        let direct = try fetchRoutes(from: domplein, to: amersfoort.point, alternatives: 2)
        try assertPreviewShows(direct[0])

        addStop(zeist)
        addStop(soesterberg)
        XCTAssertTrue(app.staticTexts["preview.stop.0"].label.contains("Slotlaan 10"), app.staticTexts["preview.stop.0"].label)
        XCTAssertTrue(app.staticTexts["preview.stop.1"].label.contains("Kampweg 1"), app.staticTexts["preview.stop.1"].label)
        let inOrder = try fetchRoutes(from: domplein, to: amersfoort.point, stops: [zeist.point, soesterberg.point])
        XCTAssertEqual(inOrder.count, 1)
        try assertPreviewShows(inOrder[0])
        XCTAssertFalse(card(0).exists, "a trip with stops has no alternatives")
        XCTAssertTrue(app.buttons["preview.start"].exists, "a trip with stops can be ridden")
        XCTAssertFalse(app.staticTexts["preview.startHint"].exists)
        sleep(3)
        screenshot("planner-05-two-stops")

        app.buttons["preview.stop.1.up"].tap()
        XCTAssertTrue(app.staticTexts["preview.stop.0"].label.contains("Kampweg 1"))
        let reordered = try fetchRoutes(from: domplein, to: amersfoort.point, stops: [soesterberg.point, zeist.point])
        XCTAssertNotEqual(reordered[0].lengthM, inOrder[0].lengthM)
        try assertPreviewShows(reordered[0])
        sleep(3)
        screenshot("planner-06-stops-reordered")

        setTime("Arrive by")
        XCTAssertTrue(app.buttons["preview.time"].label.hasPrefix("Arrive by · "), app.buttons["preview.time"].label)
        wait(for: app.staticTexts["preview.distance"], labelMatches: #"^[0-9.]+ km, leave at \d\d:\d\d$"#)
        screenshot("planner-07-arrive-by")

        setTime("Depart at")
        XCTAssertTrue(app.buttons["preview.time"].label.hasPrefix("Depart at · "), app.buttons["preview.time"].label)
        wait(for: app.staticTexts["preview.distance"], labelMatches: #"^[0-9.]+ km, arrive \d\d:\d\d$"#)

        app.buttons["preview.stop.1.remove"].tap()
        app.buttons["preview.stop.0.remove"].tap()
        XCTAssertFalse(app.staticTexts["preview.stop.0"].exists)
        setTime("Now")
        try assertPreviewShows(direct[0])
        XCTAssertTrue(app.buttons["preview.start"].waitForExistence(timeout: 10))
    }

    func testVerifiedOnlyHoldsThroughAStopAndMarksWhatIsUnavoidable() throws {
        let valkenhoeve = Place(query: "Valkenhoeve 2a Leusden", label: "Valkenhoeve 2a,", point: (52.12974638, 5.43049044))
        let vieweg = Place(query: "Vieweg 4 Leusden", label: "Vieweg 4,", point: (52.10461401, 5.40228104))
        launch(origin: caseOrigin)
        searchDestination(maarsbergen)
        addStop(valkenhoeve)
        let plain = try fetchRoutes(from: caseOrigin, to: maarsbergen.point, stops: [valkenhoeve.point])
        XCTAssertGreaterThan(plain[0].unverifiedM, 0, "the proof needs an unverified stretch through the stop")
        try assertPreviewShows(plain[0])
        XCTAssertTrue(app.buttons["preview.total.unverified"].exists)

        let toggle = app.switches["preview.verifiedOnly"]
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        let avoided = try fetchRoutes(from: caseOrigin, to: maarsbergen.point, stops: [valkenhoeve.point], verifiedOnly: true)
        XCTAssertEqual(avoided[0].unverifiedM, 0)
        try assertPreviewShows(avoided[0])
        XCTAssertFalse(app.buttons["preview.total.unverified"].exists)
        wait(for: toggle, labelContains: "Avoiding unverified cycle paths")
        sleep(2)
        screenshot("planner-11-stop-verified-only")

        app.buttons["preview.stop.0.remove"].tap()
        addStop(vieweg)
        let forced = try fetchRoutes(from: caseOrigin, to: maarsbergen.point, stops: [vieweg.point], verifiedOnly: true)
        XCTAssertGreaterThan(forced[0].unverifiedM, 0)
        XCTAssertTrue(forced[0].allUnavoidable, "the forced stop should leave only unavoidable stretches")
        try assertPreviewShows(forced[0])
        wait(for: toggle, labelContains: "No alternative for \(Self.distance(forced[0].unverifiedM)) unverified")
        sleep(2)
        screenshot("planner-12-stop-unavoidable")
    }

    func testAvoidFerriesChangesTheRouteFromAnotherStartAndSurvivesARelaunch() throws {
        launch(origin: domplein, pinAvoid: false)
        changeSettings { setSwitch("settings.avoidFerries", on: false) }
        let viaFerry = try fetchRoutes(from: centraal.point, to: badhuiskade.point, alternatives: 2)
        let noFerry = try fetchRoutes(from: centraal.point, to: badhuiskade.point, alternatives: 2, avoid: ["ferries": true])
        XCTAssertGreaterThan(noFerry[0].lengthM, viaFerry[0].lengthM * 3, "the ferry case no longer differs")

        searchDestination(badhuiskade)
        setStart(centraal)
        try assertPreviewShows(viaFerry[0])
        XCTAssertFalse(app.buttons["preview.start"].exists)
        XCTAssertEqual(app.staticTexts["preview.startHint"].label, "Start from your location to ride this route.")
        sleep(3)
        screenshot("planner-08-start-point-ferry")
        app.buttons["preview.back"].tap()

        changeSettings { setSwitch("settings.avoidFerries", on: true) }
        app.terminate()
        launch(origin: domplein, pinAvoid: false)
        changeSettings {
            XCTAssertEqual(app.switches["settings.avoidFerries"].value as? String, "1", "avoid ferries did not survive the relaunch")
            XCTAssertEqual(app.switches["settings.avoidUnpaved"].value as? String, "0")
            XCTAssertEqual(app.switches["settings.avoidMainRoads"].value as? String, "0")
            screenshot("planner-09-settings-avoid")
        }

        searchDestination(badhuiskade)
        setStart(centraal)
        try assertPreviewShows(noFerry[0])
        sleep(3)
        screenshot("planner-10-avoid-ferries")
        app.buttons["preview.back"].tap()

        changeSettings { setSwitch("settings.avoidFerries", on: false) }
        searchDestination(badhuiskade)
        setStart(centraal)
        try assertPreviewShows(viaFerry[0])

        app.buttons["preview.from.reset"].tap()
        XCTAssertTrue(app.buttons["preview.from"].label.contains("Your location"), app.buttons["preview.from"].label)
        XCTAssertTrue(app.buttons["preview.start"].waitForExistence(timeout: 60))
    }

    func testAvoidMainRoadsAndUnpavedChangeTheRouteAndOffRestoresIt() throws {
        let cases: [(switchId: String, key: String, origin: Point, place: Place)] = [
            ("settings.avoidMainRoads", "main_roads", (51.97709, 5.89902),
             Place(query: "Groningensingel 135 Arnhem", label: "Groningensingel 135,", point: (51.95622464, 5.90775811))),
            ("settings.avoidUnpaved", "unpaved", (52.10483, 5.60555),
             Place(query: "Heidehoek 5 Ede", label: "Heidehoek 5,", point: (52.0792764, 5.6637442))),
        ]
        for item in cases {
            let plain = try fetchRoutes(from: item.origin, to: item.place.point, alternatives: 2)
            let avoiding = try fetchRoutes(from: item.origin, to: item.place.point, alternatives: 2, avoid: [item.key: true])
            XCTAssertNotEqual(plain[0].lengthM, avoiding[0].lengthM, "\(item.key) no longer changes its case")

            launch(origin: item.origin, pinAvoid: false)
            changeSettings {
                setSwitch("settings.avoidFerries", on: false)
                setSwitch("settings.avoidMainRoads", on: false)
                setSwitch("settings.avoidUnpaved", on: false)
                setSwitch(item.switchId, on: true)
            }
            searchDestination(item.place)
            try assertPreviewShows(avoiding[0])
            sleep(2)
            screenshot("planner-avoid-\(item.key)")
            app.buttons["preview.back"].tap()

            changeSettings { setSwitch(item.switchId, on: false) }
            searchDestination(item.place)
            try assertPreviewShows(plain[0])
            app.terminate()
        }
    }

    private func launch(origin: Point, pinAvoid: Bool = true) {
        app = XCUIApplication()
        var arguments = [
            "-NaviscootSimulateRide", "YES",
            "-NaviscootSimSpeedKmh", "45",
            "-NaviscootSimOrigin", "\(origin.lat),\(origin.lon)",
            "-settings.language", "en",
            "-settings.verifiedOnlyByDefault", "NO",
            "-NaviscootDiscardActiveRide", "YES",
        ]
        if pinAvoid {
            arguments += ["-settings.avoidFerries", "NO", "-settings.avoidUnpaved", "NO", "-settings.avoidMainRoads", "NO"]
        }
        app.launchArguments = arguments
        app.launch()
        XCTAssertTrue(app.textFields["search.field"].waitForExistence(timeout: 10))
    }

    private func searchDestination(_ place: Place) {
        let field = app.textFields["search.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        let clear = app.buttons["search.clear"]
        if clear.exists {
            clear.tap()
            XCTAssertTrue(clear.waitForNonExistence(timeout: 5))
        }
        field.tap()
        field.typeText(place.query)
        let result = self.result(containing: place.label)
        XCTAssertTrue(result.waitForExistence(timeout: 15), "no result for \(place.query)")
        result.tap()
        XCTAssertTrue(app.buttons["preview.back"].waitForExistence(timeout: 10))
    }

    private func pick(_ place: Place, from button: XCUIElement) {
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap()
        let field = app.textFields["placeSearch.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(place.query)
        let result = self.result(containing: place.label)
        XCTAssertTrue(result.waitForExistence(timeout: 15), "no result for \(place.query)")
        result.tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 10))
    }

    private func addStop(_ place: Place) {
        pick(place, from: app.buttons["preview.addStop"])
    }

    private func setStart(_ place: Place) {
        pick(place, from: app.buttons["preview.from"])
        XCTAssertTrue(app.buttons["preview.from"].label.contains(place.label.dropLast()), app.buttons["preview.from"].label)
    }

    private func setTime(_ mode: String) {
        let chip = app.buttons["preview.time"]
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        chip.tap()
        let segment = app.segmentedControls["time.mode"].buttons[mode]
        XCTAssertTrue(segment.waitForExistence(timeout: 5))
        segment.tap()
        app.buttons["time.done"].tap()
        XCTAssertTrue(app.buttons["time.done"].waitForNonExistence(timeout: 5))
    }

    private func changeSettings(_ change: () -> Void) {
        let button = app.buttons["search.settings"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap()
        XCTAssertTrue(app.buttons["settings.done"].waitForExistence(timeout: 5))
        change()
        app.buttons["settings.done"].tap()
        XCTAssertTrue(app.buttons["settings.done"].waitForNonExistence(timeout: 5))
    }

    private func setSwitch(_ id: String, on: Bool) {
        let toggle = app.switches[id]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        var swipes = 0
        while !toggle.isHittable, swipes < 4 {
            app.swipeUp()
            swipes += 1
        }
        if (toggle.value as? String == "1") != on {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        }
        XCTAssertEqual(toggle.value as? String, on ? "1" : "0", id)
    }

    private func result(containing text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier == 'search.result' AND label CONTAINS %@", text)).firstMatch
    }

    private func card(_ index: Int) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "preview.route.\(index).")).firstMatch
    }

    private func assertCards(_ routes: [APIRoute], verifiedOnly: Bool) {
        for (index, route) in routes.enumerated() {
            let unverified: String
            if route.unverifiedM == 0 {
                unverified = "No unverified"
            } else if verifiedOnly, route.allUnavoidable {
                unverified = "\(Self.distance(route.unverifiedM)) unavoidable"
            } else {
                unverified = "\(Self.distance(route.unverifiedM)) unverified"
            }
            let expected = "Route \(index + 1), \(Self.duration(route.durationS)), \(Self.distance(route.lengthM)), \(unverified)"
            let match = expectation(for: NSPredicate(format: "label == %@", expected), evaluatedWith: card(index))
            XCTAssertEqual(XCTWaiter.wait(for: [match], timeout: 60), .completed, "expected '\(expected)', shown '\(card(index).label)'")
        }
        XCTAssertFalse(card(routes.count).exists)
    }

    private func assertPreviewShows(_ route: APIRoute) throws {
        let duration = app.staticTexts["preview.duration"]
        let shown = NSPredicate(format: "label == %@", Self.duration(route.durationS))
        let match = expectation(for: shown, evaluatedWith: duration)
        XCTAssertEqual(XCTWaiter.wait(for: [match], timeout: 60), .completed, "expected \(Self.duration(route.durationS)), shown '\(duration.label)'")
        let distance = app.staticTexts["preview.distance"]
        XCTAssertTrue(distance.label.hasPrefix("\(Self.distance(route.lengthM)), "), distance.label)
        let carriageway = app.descendants(matching: .any)["preview.total.carriageway"]
        XCTAssertEqual(carriageway.label, "Carriageway, \(Self.distance(route.carriagewayM))")
    }

    private func wait(for element: XCUIElement, labelMatches pattern: String) {
        let match = expectation(for: NSPredicate(format: "label MATCHES %@", pattern), evaluatedWith: element)
        XCTAssertEqual(XCTWaiter.wait(for: [match], timeout: 60), .completed, "'\(element.label)' does not match \(pattern)")
    }

    private func wait(for element: XCUIElement, labelContains text: String) {
        let match = expectation(for: NSPredicate(format: "label CONTAINS %@", text), evaluatedWith: element)
        XCTAssertEqual(XCTWaiter.wait(for: [match], timeout: 30), .completed, "'\(element.label)' does not contain '\(text)'")
    }

    private func apiKey() throws -> String {
        guard let key = ProcessInfo.processInfo.environment["NAVISCOOT_API_KEY"] else {
            throw XCTSkip("set TEST_RUNNER_NAVISCOOT_API_KEY to run the planner proof against the local API")
        }
        return key
    }

    private func fetchRoutes(
        from origin: Point,
        to destination: Point,
        stops: [Point] = [],
        alternatives: Int = 0,
        verifiedOnly: Bool = false,
        avoid: [String: Bool]? = nil
    ) throws -> [APIRoute] {
        let base = ProcessInfo.processInfo.environment["NAVISCOOT_API_BASE_URL"] ?? "http://127.0.0.1:8080"
        var request = URLRequest(url: URL(string: "\(base)/route")!)
        request.httpMethod = "POST"
        request.setValue(try apiKey(), forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        var body: [String: Any] = [
            "origin": ["lat": origin.lat, "lon": origin.lon],
            "destination": ["lat": destination.lat, "lon": destination.lon],
            "verified_only": verifiedOnly,
            "format": "osrm",
            "language": "en-GB",
        ]
        if !stops.isEmpty { body["waypoints"] = stops.map { ["lat": $0.lat, "lon": $0.lon] } }
        if alternatives > 0 { body["alternatives"] = alternatives }
        if let avoid { body["avoid"] = avoid }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        var data: Data?
        let done = expectation(description: "route")
        URLSession.shared.dataTask(with: request) { body, _, _ in
            data = body
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 90)

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(data)) as? [String: Any])
        let primary = try XCTUnwrap(json["naviscoot"] as? [String: Any], "\(json)")
        let metas = [primary] + (primary["alternates"] as? [[String: Any]] ?? [])
        let routes = try XCTUnwrap(json["routes"] as? [[String: Any]])
        XCTAssertEqual(routes.count, metas.count)
        return try zip(routes, metas).map { route, meta in
            let totals = try XCTUnwrap(meta["totals_m"] as? [String: Int])
            let stretches = meta["stretches"] as? [[String: Any]] ?? []
            let unverified = stretches.filter { $0["class"] as? String == "unverified" }
            return try APIRoute(
                lengthM: XCTUnwrap(meta["length_m"] as? Int),
                durationS: XCTUnwrap(route["duration"] as? Double),
                unverifiedM: totals["unverified"] ?? 0,
                carriagewayM: totals["carriageway"] ?? 0,
                allUnavoidable: !unverified.isEmpty && unverified.allSatisfy { $0["unavoidable"] is String }
            )
        }
    }

    private static func distance(_ meters: Int) -> String {
        guard meters >= 1000 else { return "\(meters) m" }
        return String(format: "%.1f km", locale: Locale(identifier: "en_US_POSIX"), Double(meters) / 1000)
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
