import XCTest

final class SearchAndPreviewUITests: XCTestCase {
    private let origin = (lat: 52.2977646, lon: 5.445363)
    private let destination = (lat: 52.04779119, lon: 5.40516261)
    private let address = "Woudenbergseweg 42 Maarsbergen"
    private let station = "Amersfoort Centraal"
    private var app: XCUIApplication!

    private enum Language: String {
        case dutch = "nl-NL"
        case english = "en-GB"
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(pinned: Bool = true) {
        app = XCUIApplication()
        app.launchArguments = ["-NaviscootDiscardActiveRide", "YES"]
        if pinned {
            app.launchArguments += [
                "-settings.language", "en", "-settings.verifiedOnlyByDefault", "NO",
                "-settings.avoidFerries", "NO", "-settings.avoidUnpaved", "NO", "-settings.avoidMainRoads", "NO",
            ]
        }
        app.launch()
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow While Using App"]
        if allow.waitForExistence(timeout: 4) {
            allow.tap()
        }
    }

    func testSearchThenPreviewMatchesTheAPIAndVerifiedOnlyDropsUnverified() throws {
        launch()
        let field = app.textFields["search.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))

        field.tap()
        field.typeText(address)
        let addressResult = result(containing: "Woudenbergseweg 42,")
        XCTAssertTrue(addressResult.waitForExistence(timeout: 15))
        XCTAssertTrue(addressResult.label.contains("Address"), addressResult.label)
        screenshot("02-search-address")

        app.buttons["search.clear"].tap()
        field.typeText(station)
        let stationResult = result(containing: "Place")
        XCTAssertTrue(stationResult.waitForExistence(timeout: 15), "no MapKit place for \(station)")
        XCTAssertTrue(stationResult.label.localizedCaseInsensitiveContains("Amersfoort"), stationResult.label)
        screenshot("03-search-station")

        app.buttons["search.clear"].tap()
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

        let handle = app.buttons["preview.sheet.handle"]
        let destination = app.staticTexts["preview.destination"]
        handle.swipeDown()
        XCTAssertTrue(toggle.waitForNonExistence(timeout: 5), "swiping the sheet down did not minimise it")
        XCTAssertFalse(destination.exists)
        XCTAssertTrue(app.staticTexts["preview.duration"].exists, "the minimised sheet lost the route summary")
        XCTAssertTrue(app.buttons["preview.start"].isHittable, "the minimised sheet lost Start")
        sleep(3)
        screenshot("07-preview-minimised")

        handle.swipeUp()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "swiping the sheet up did not expand it")
        XCTAssertTrue(destination.exists)
        handle.tap()
        XCTAssertTrue(toggle.waitForNonExistence(timeout: 5), "tapping the handle did not minimise the sheet")
        handle.tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "tapping the handle did not expand the sheet")
    }

    func testTheResultsRunBehindTheKeyboardAndKeepTheirSizeWhenItCloses() throws {
        launch()
        let field = app.textFields["search.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("Amersfoort")
        let results = app.scrollViews["home.drawer"]
        XCTAssertTrue(result(containing: "Amersfoort").waitForExistence(timeout: 15))
        sleep(2)
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.exists)
        let withKeyboard = results.frame
        XCTAssertGreaterThan(withKeyboard.maxY, keyboard.frame.minY, "the results stop above the keyboard: \(withKeyboard) vs \(keyboard.frame)")
        screenshot("07-results-with-keyboard")

        let rows = app.buttons.matching(identifier: "search.result")
        rows.element(boundBy: 2).press(forDuration: 0.05, thenDragTo: rows.element(boundBy: 0))
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5), "scrolling the results did not close the keyboard")
        screenshot("08-results-without-keyboard")
        XCTAssertEqual(results.frame.height, withKeyboard.height, accuracy: 1, "the results changed size when the keyboard closed")
    }

    func testSettingsSurviveARelaunchAndTheLanguageSwitchesWithoutARestart() throws {
        launch(pinned: false)
        let field = app.textFields["search.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))

        openSettings()
        app.buttons["Nederlands"].tap()
        XCTAssertTrue(app.navigationBars["Instellingen"].waitForExistence(timeout: 5), "settings title did not switch to Dutch")
        let defaultToggle = app.switches["settings.verifiedOnlyDefault"]
        if defaultToggle.value as? String != "1" {
            defaultToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        }
        XCTAssertEqual(defaultToggle.value as? String, "1")
        XCTAssertTrue(app.staticTexts["Standaard alleen bevestigde wegen"].exists)
        screenshot("nl-01-settings")
        app.buttons["settings.done"].tap()
        XCTAssertEqual(field.placeholderValue, "Adres of plaats")
        XCTAssertEqual(app.buttons["search.settings"].label, "Instellingen")
        screenshot("nl-02-search")

        app.terminate()
        launch(pinned: false)
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        XCTAssertEqual(field.placeholderValue, "Adres of plaats", "the language did not survive the relaunch")
        openSettings()
        XCTAssertTrue(app.buttons["Nederlands"].isSelected, "Nederlands is not the selected language after the relaunch")
        XCTAssertEqual(app.switches["settings.verifiedOnlyDefault"].value as? String, "1", "verified-only default did not survive the relaunch")
        app.buttons["settings.done"].tap()

        field.tap()
        field.typeText(address)
        let addressResult = result(containing: "Woudenbergseweg 42,")
        XCTAssertTrue(addressResult.waitForExistence(timeout: 15))
        XCTAssertTrue(addressResult.label.contains("Adres"), addressResult.label)
        screenshot("nl-03-search-results")
        addressResult.tap()

        let previewToggle = app.switches["preview.verifiedOnly"]
        XCTAssertTrue(previewToggle.waitForExistence(timeout: 10))
        XCTAssertEqual(previewToggle.value as? String, "1", "the preview did not start from the verified-only default")
        let verifiedRoute = try fetchRoute(verifiedOnly: true)
        XCTAssertEqual(verifiedRoute.totals["unverified"], 0)
        try assertPreviewShows(verifiedRoute, in: .dutch)
        XCTAssertFalse(app.buttons["preview.total.unverified"].exists)
        XCTAssertEqual(app.buttons["preview.start"].label, "Start")
        XCTAssertEqual(app.buttons["preview.back"].label, "Terug")
        sleep(3)
        screenshot("nl-04-preview")
        app.buttons["preview.back"].tap()

        openSettings()
        app.buttons["English"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5), "settings title did not switch to English")
        XCTAssertTrue(app.staticTexts["Verified roads only by default"].exists)
        screenshot("en-01-settings")
        app.buttons["System"].tap()
        let resetToggle = app.switches["settings.verifiedOnlyDefault"]
        if resetToggle.value as? String == "1" {
            resetToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        }
        XCTAssertEqual(resetToggle.value as? String, "0")
        app.buttons["settings.done"].tap()
        XCTAssertEqual(field.placeholderValue, "Address or place")
        screenshot("en-02-search")
    }

    private func openSettings() {
        let button = app.buttons["search.settings"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap()
        XCTAssertTrue(app.buttons["settings.done"].waitForExistence(timeout: 5))
    }

    private func result(containing text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier == 'search.result' AND label CONTAINS %@", text)).firstMatch
    }

    private func assertPreviewShows(_ route: APIRoute, in language: Language = .english) throws {
        let rows = language == .dutch
            ? [("carriageway", "Rijbaan"), ("moped_path", "Bromfietspad (G12a)"), ("unverified", "Onbevestigd fietspad")]
            : [("carriageway", "Carriageway"), ("moped_path", "Moped path (G12a)"), ("unverified", "Unverified cycle path")]
        for (key, label) in rows {
            let expected = "\(label), \(Self.distance(route.totals[key] ?? -1, in: language))"
            let element = app.descendants(matching: .any)["preview.total.\(key)"]
            let shown = NSPredicate(format: "label == %@", expected)
            let match = expectation(for: shown, evaluatedWith: element)
            XCTAssertEqual(XCTWaiter.wait(for: [match], timeout: 30), .completed, "expected '\(expected)', shown '\(element.label)'")
        }
        let distance = app.staticTexts["preview.distance"]
        let arrive = language == .dutch ? "aankomst" : "arrive"
        XCTAssertTrue(distance.label.hasPrefix("\(Self.distance(route.lengthM, in: language)), \(arrive) "), distance.label)
        XCTAssertEqual(app.staticTexts["preview.duration"].label, Self.duration(route.durationS, in: language))
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

    private static func distance(_ meters: Int, in language: Language) -> String {
        guard meters >= 1000 else { return "\(meters) m" }
        let text = String(format: "%.1f km", locale: Locale(identifier: "en_US_POSIX"), Double(meters) / 1000)
        return language == .dutch ? text.replacingOccurrences(of: ".", with: ",") : text
    }

    private static func duration(_ seconds: Double, in language: Language) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        let hour = language == .dutch ? "u" : "h"
        return minutes < 60 ? "\(minutes) min" : "\(minutes / 60) \(hour) \(minutes % 60) min"
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
