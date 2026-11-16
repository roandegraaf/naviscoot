import XCTest

final class PlacesUITests: XCTestCase {
    private let origin = "52.1533,5.3728"
    private let farAddress = (query: "Woudenbergseweg 42 Maarsbergen", title: "Woudenbergseweg 42")
    private let nearAddress = (query: "Kapelweg 170A Amersfoort", title: "Kapelweg 170A")
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard ProcessInfo.processInfo.environment["NAVISCOOT_API_KEY"] != nil else {
            throw XCTSkip("set TEST_RUNNER_NAVISCOOT_API_KEY to run the places proof against the local API")
        }
    }

    private func launch(reset: Bool) {
        app = XCUIApplication()
        app.launchArguments = [
            "-NaviscootDiscardActiveRide", "YES",
            "-NaviscootSimOrigin", origin,
            "-settings.language", "en", "-settings.verifiedOnlyByDefault", "NO",
            "-settings.avoidFerries", "NO", "-settings.avoidUnpaved", "NO", "-settings.avoidMainRoads", "NO",
        ]
        if reset {
            app.launchArguments += ["-NaviscootResetPlaces", "YES"]
        }
        app.launch()
        XCTAssertTrue(app.textFields["search.field"].waitForExistence(timeout: 10))
    }

    func testAPreviewedAddressBecomesARecentThatOpensInOneTapAndCanBeCleared() throws {
        launch(reset: true)
        openSearch()
        XCTAssertTrue(app.buttons["home.home"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["home.home"].label, "Set Home")
        XCTAssertFalse(app.buttons["home.recent.0"].exists, "the reset store still has recents")
        screenshot("places-01-empty-home")

        openPreview(searching: farAddress.query, result: "\(farAddress.title),")
        assertPreviewLoads(showing: farAddress.title)
        app.buttons["preview.back"].tap()
        app.buttons["search.clear"].tap()

        let recent = app.buttons["home.recent.0"]
        XCTAssertTrue(recent.waitForExistence(timeout: 5), "no recent after previewing \(farAddress.title)")
        XCTAssertTrue(recent.label.contains(farAddress.title), recent.label)
        screenshot("places-02-recent")

        recent.tap()
        assertPreviewLoads(showing: farAddress.title)
        app.buttons["preview.back"].tap()
        openSearch()
        XCTAssertTrue(recent.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["home.recent.1"].exists, "opening a recent again added a duplicate")

        app.buttons["home.clearRecents"].tap()
        assertGone(recent, "recents were not cleared")
        XCTAssertFalse(app.buttons["home.clearRecents"].exists)
        screenshot("places-03-recents-cleared")
    }

    func testAFavouriteAndHomeSurviveARelaunchOpenInOneTapAndCanBeRenamedAndRemoved() throws {
        launch(reset: true)
        openPreview(searching: farAddress.query, result: "\(farAddress.title),")
        assertPreviewLoads(showing: farAddress.title)
        save(as: "preview.save.favourite")
        app.buttons["preview.back"].tap()
        app.buttons["search.clear"].tap()

        openPreview(searching: nearAddress.query, result: "\(nearAddress.title),")
        assertPreviewLoads(showing: nearAddress.title)
        save(as: "preview.save.home")
        screenshot("places-04-preview-saved")
        app.buttons["preview.back"].tap()

        app.terminate()
        launch(reset: false)
        openSearch()
        let home = app.buttons["home.home"]
        let favourite = app.buttons["home.favourite.0"]
        XCTAssertTrue(home.waitForExistence(timeout: 5))
        XCTAssertTrue(home.label.hasPrefix("Home"), home.label)
        XCTAssertTrue(home.label.contains(nearAddress.title), home.label)
        XCTAssertTrue(favourite.waitForExistence(timeout: 5), "the favourite did not survive the relaunch")
        XCTAssertTrue(favourite.label.contains(farAddress.title), favourite.label)
        XCTAssertEqual(app.buttons["home.work"].label, "Set Work")
        screenshot("places-05-after-relaunch")

        home.tap()
        assertPreviewLoads(showing: nearAddress.title)
        app.buttons["preview.back"].tap()
        openSearch()
        favourite.tap()
        assertPreviewLoads(showing: farAddress.title)
        app.buttons["preview.back"].tap()
        openSearch()

        app.buttons["home.edit"].tap()
        let editedRow = app.descendants(matching: .any)["places.favourite.0"]
        XCTAssertTrue(editedRow.waitForExistence(timeout: 5))
        app.buttons["places.favourite.0.rename"].tap()
        let alert = app.alerts["Rename favourite"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let nameField = alert.textFields.firstMatch
        nameField.tap()
        nameField.typeText("Grandma")
        alert.buttons.matching(identifier: "Save").firstMatch.tap()
        XCTAssertTrue(wait(for: editedRow, labelContains: "Grandma, \(farAddress.title),"), editedRow.label)
        screenshot("places-06-edit")
        app.buttons["places.done"].tap()

        XCTAssertTrue(wait(for: favourite, labelContains: "Grandma, \(farAddress.title),"), favourite.label)
        XCTAssertTrue(favourite.label.hasPrefix("Grandma,"), favourite.label)
        XCTAssertTrue(favourite.label.contains(farAddress.title), "the renamed favourite lost its address: \(favourite.label)")
        favourite.tap()
        assertPreviewLoads(showing: "Grandma")
        app.buttons["preview.back"].tap()
        openSearch()

        app.buttons["home.edit"].tap()
        XCTAssertTrue(app.buttons["places.favourite.0.remove"].waitForExistence(timeout: 5))
        app.buttons["places.favourite.0.remove"].tap()
        app.buttons["places.home.remove"].tap()
        XCTAssertTrue(app.staticTexts["Nothing saved yet. Save a destination from its route preview."].waitForExistence(timeout: 5))
        app.buttons["places.done"].tap()
        assertGone(favourite, "the favourite was not removed")
        XCTAssertEqual(home.label, "Set Home")

        app.terminate()
        launch(reset: false)
        openSearch()
        XCTAssertTrue(app.buttons["home.home"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["home.home"].label, "Set Home", "the removed Home came back after a relaunch")
        XCTAssertFalse(app.buttons["home.favourite.0"].exists, "the removed favourite came back after a relaunch")
    }

    func testALongPressDropsAPinWithTheNearestAddressAndOpensItsPreview() throws {
        launch(reset: true)
        sleep(3)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.3)).press(forDuration: 1.2)

        let pin = app.staticTexts["search.pin"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5), "no pin after a long-press")
        let point = try XCTUnwrap((pin.value as? String).flatMap(Self.coordinate), "pin value: \(String(describing: pin.value))")
        let expected = try XCTUnwrap(reverseGeocode(point), "PDOK has no address within 200 m of \(point); press elsewhere")
        XCTAssertTrue(wait(for: pin, labelIs: expected.title), "pin shows '\(pin.label)', PDOK says '\(expected.title)'")
        XCTAssertEqual(app.staticTexts["search.pin.subtitle"].label, expected.subtitle)
        screenshot("places-07-pin")

        app.buttons["search.pin.route"].tap()
        assertPreviewLoads(showing: expected.title)
        screenshot("places-08-pin-preview")
        app.buttons["preview.back"].tap()

        assertGone(pin, "the pin stayed after opening its preview")
        openSearch()
        let recent = app.buttons["home.recent.0"]
        XCTAssertTrue(recent.waitForExistence(timeout: 5))
        XCTAssertTrue(recent.label.contains(expected.title), recent.label)
    }

    private func openSearch() {
        app.textFields["search.field"].tap()
        XCTAssertTrue(app.buttons["search.close"].waitForExistence(timeout: 5), "tapping the field did not open the search panel")
    }

    private func openPreview(searching query: String, result text: String) {
        let field = app.textFields["search.field"]
        field.tap()
        field.typeText(query)
        let result = app.buttons.matching(NSPredicate(format: "identifier == 'search.result' AND label CONTAINS %@", text)).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 15), "no search result for \(query)")
        result.tap()
    }

    private func assertPreviewLoads(showing title: String) {
        let destination = app.staticTexts["preview.destination"]
        XCTAssertTrue(destination.waitForExistence(timeout: 10), "the preview did not open")
        XCTAssertTrue(destination.label.contains(title), destination.label)
        XCTAssertTrue(app.staticTexts["preview.duration"].waitForExistence(timeout: 30), "the preview to \(title) did not load a route")
    }

    private func save(as option: String) {
        app.buttons["preview.save"].tap()
        let button = app.buttons.matching(identifier: option).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
        let saved = expectation(for: NSPredicate(format: "value == 'Saved'"), evaluatedWith: app.buttons["preview.save"])
        XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 5), .completed, "the preview does not show the place as saved")
    }

    private func wait(for element: XCUIElement, labelContains text: String) -> Bool {
        let match = expectation(for: NSPredicate(format: "label CONTAINS %@", text), evaluatedWith: element)
        return XCTWaiter.wait(for: [match], timeout: 10) == .completed
    }

    private func wait(for element: XCUIElement, labelIs text: String) -> Bool {
        let match = expectation(for: NSPredicate(format: "label == %@", text), evaluatedWith: element)
        return XCTWaiter.wait(for: [match], timeout: 15) == .completed
    }

    private func assertGone(_ element: XCUIElement, _ message: String) {
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed, message)
    }

    private static func coordinate(_ text: String) -> (lat: Double, lon: Double)? {
        let parts = text.split(separator: ",").compactMap { Double($0) }
        return parts.count == 2 ? (parts[0], parts[1]) : nil
    }

    private func reverseGeocode(_ point: (lat: Double, lon: Double)) throws -> (title: String, subtitle: String)? {
        var components = URLComponents(string: "https://api.pdok.nl/bzk/locatieserver/search/v3_1/reverse")!
        components.queryItems = [
            URLQueryItem(name: "lat", value: String(point.lat)),
            URLQueryItem(name: "lon", value: String(point.lon)),
            URLQueryItem(name: "type", value: "adres"),
            URLQueryItem(name: "rows", value: "1"),
            URLQueryItem(name: "distance", value: "200"),
        ]
        var body: Data?
        let done = expectation(description: "reverse")
        URLSession.shared.dataTask(with: components.url!) { data, _, _ in
            body = data
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 30)

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(body)) as? [String: Any])
        let docs = try XCTUnwrap((json["response"] as? [String: Any])?["docs"] as? [[String: Any]])
        guard let name = docs.first?["weergavenaam"] as? String else { return nil }
        guard let comma = name.firstIndex(of: ",") else { return (name, "") }
        return (String(name[..<comma]), name[name.index(after: comma)...].trimmingCharacters(in: .whitespaces))
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
