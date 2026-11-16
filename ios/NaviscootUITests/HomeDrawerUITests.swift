import XCTest

final class HomeDrawerUITests: XCTestCase {
    private let origin = (lat: 52.1533, lon: 5.3728)
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testSavedPlacesAndTripsShowOnLaunchWithoutFocusingSearch() throws {
        launch(seeded: true)
        for id in ["home.home", "home.work", "home.favourite.0", "home.recent.0"] {
            XCTAssertTrue(app.buttons[id].waitForExistence(timeout: 5), "\(id) is not in the drawer on launch")
        }
        for id in ["home.home", "home.work", "home.favourite.0"] {
            XCTAssertTrue(app.buttons[id].isHittable, "\(id) is not reachable at the medium drawer")
        }
        XCTAssertTrue(app.buttons["home.home"].label.hasPrefix("Home"), app.buttons["home.home"].label)
        XCTAssertFalse(app.buttons["search.close"].exists, "search opened by itself")
        XCTAssertFalse(app.buttons["search.trips"].exists, "the old trip-history icon is still on the map")
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        screenshot("drawer-01-medium")

        dragDrawer(by: -500)
        let seeAll = app.buttons["home.trips.all"]
        XCTAssertTrue(seeAll.waitForExistence(timeout: 5))
        XCTAssertTrue(seeAll.isHittable, "See all is not reachable at the large drawer")
        XCTAssertTrue(app.buttons["home.trip.0"].label.hasPrefix("Koppelpoort"), app.buttons["home.trip.0"].label)
        XCTAssertTrue(app.buttons["home.trip.1"].label.hasPrefix("Domplein"), app.buttons["home.trip.1"].label)
        XCTAssertFalse(app.buttons["home.trip.2"].exists)
        XCTAssertTrue(app.buttons["home.recent.0"].isHittable, "the recent place is not reachable at the large drawer")
        screenshot("drawer-02-large")

        seeAll.tap()
        XCTAssertTrue(app.buttons["trips.done"].waitForExistence(timeout: 5), "See all did not open the trip history")
        XCTAssertTrue(app.buttons["trips.trip.1"].exists)
        app.buttons["trips.done"].tap()
        XCTAssertTrue(app.buttons["trips.done"].waitForNonExistence(timeout: 5))
        app.buttons["home.trip.1"].tap()
        let destination = app.staticTexts["trip.destination"]
        XCTAssertTrue(destination.waitForExistence(timeout: 5), "a recent trip did not open its detail")
        XCTAssertEqual(destination.label, "Domplein")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["trips.done"].waitForExistence(timeout: 5))
        app.buttons["trips.done"].tap()
        XCTAssertTrue(app.buttons["home.trip.1"].waitForExistence(timeout: 5), "the drawer did not come back after trip history")
    }

    func testTheDrawerFoldsToTheSearchBarAndTheMapStaysUsable() throws {
        launch(seeded: true)
        let field = app.textFields["search.field"]
        let locate = app.buttons["home.locate"]
        XCTAssertTrue(locate.waitForExistence(timeout: 5))
        let start = try waitForCamera(locate)

        drag(on: CGVector(dx: 0.3, dy: 0.25), by: CGVector(dx: 120, dy: 80))
        let panned = try waitForCamera(locate, awayFrom: start)
        XCTAssertGreaterThan(distance(panned, start), 0.0005, "the map did not pan behind the medium drawer")

        dragDrawer(by: 700)
        XCTAssertTrue(field.isHittable, "the search field is gone at the collapsed drawer")
        XCTAssertGreaterThan(field.frame.minY, window.frame.height * 0.75, "the drawer did not fold down: \(field.frame)")
        XCTAssertFalse(app.buttons["home.home"].isHittable, "saved places still show at the collapsed drawer")
        screenshot("drawer-03-collapsed")

        drag(on: CGVector(dx: 0.5, dy: 0.6), by: CGVector(dx: -100, dy: -120))
        let pannedCollapsed = try waitForCamera(locate, awayFrom: panned)
        XCTAssertGreaterThan(distance(pannedCollapsed, panned), 0.0005, "the map did not pan behind the collapsed drawer")
        Thread.sleep(forTimeInterval: 1)
        window.pinch(withScale: 2.5, velocity: 2)
        Thread.sleep(forTimeInterval: 1.5)
        let zoomed = try waitForCamera(locate, awayFrom: pannedCollapsed)
        XCTAssertGreaterThan(zoomed.zoom, pannedCollapsed.zoom + 0.3, "the map did not zoom behind the collapsed drawer")

        locate.tap()
        let back = try waitForCamera(locate, awayFrom: zoomed)
        XCTAssertEqual(back.lat, origin.lat, accuracy: 0.0005, "locate did not recenter on the user")
        XCTAssertEqual(back.lon, origin.lon, accuracy: 0.0005, "locate did not recenter on the user")

        dragDrawer(by: -300)
        XCTAssertTrue(app.buttons["home.home"].waitFor(\.isHittable, timeout: 5), "the drawer did not unfold to medium")
        XCTAssertLessThan(field.frame.minY, window.frame.height * 0.75)
        screenshot("drawer-04-medium-again")
    }

    func testLayersOpenTheMapStyleCardsAndApplyAtOnce() throws {
        launch(seeded: true)
        let layers = app.buttons["home.layers"]
        XCTAssertTrue(layers.waitForExistence(timeout: 5))
        XCTAssertEqual(layers.value as? String, "liberty")
        layers.tap()
        let positron = app.buttons["layers.style.positron"]
        XCTAssertTrue(positron.waitForExistence(timeout: 5), "layers did not open the map styles")
        for style in ["liberty", "bright", "dark", "fiord"] {
            XCTAssertTrue(app.buttons["layers.style.\(style)"].exists, "no card for \(style)")
        }
        positron.tap()
        XCTAssertTrue(layers.waitFor(\.value, equals: "positron", timeout: 5), "picking a card did not change the map style")
        XCTAssertTrue(positron.isSelected)
        screenshot("drawer-05-layers")
        app.buttons["layers.done"].tap()
        XCTAssertTrue(positron.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["home.home"].isHittable, "the drawer did not come back after layers")
        screenshot("drawer-06-positron")
    }

    func testSettingsPlacesAndSetHomeOpenFromTheDrawerAndCloseBackToIt() throws {
        launch(seeded: true)
        app.buttons["search.settings"].tap()
        XCTAssertTrue(app.buttons["settings.done"].waitForExistence(timeout: 5), "Settings did not open from the drawer")
        app.buttons["settings.done"].tap()
        XCTAssertTrue(app.buttons["settings.done"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["home.home"].waitFor(\.isHittable, timeout: 5), "the drawer did not come back after Settings")

        app.buttons["home.edit"].tap()
        XCTAssertTrue(app.buttons["places.done"].waitForExistence(timeout: 5), "the places editor did not open from the drawer")
        app.buttons["places.done"].tap()
        XCTAssertTrue(app.buttons["places.done"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["home.home"].waitFor(\.isHittable, timeout: 5), "the drawer did not come back after the places editor")

        app.terminate()
        launch(seeded: false)
        let home = app.buttons["home.home"]
        XCTAssertTrue(home.waitForExistence(timeout: 5))
        XCTAssertEqual(home.label, "Set Home")
        home.tap()
        XCTAssertTrue(app.textFields["placeSearch.field"].waitForExistence(timeout: 5), "Set Home did not open its search")
        app.buttons["placeSearch.cancel"].tap()
        XCTAssertTrue(app.textFields["placeSearch.field"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["home.work"].waitFor(\.isHittable, timeout: 5), "the drawer did not come back after Set Home")
    }

    func testSearchingExpandsTheDrawerAndAResultOpensThePreviewThenTheDrawerComesBack() throws {
        launch(seeded: true)
        let field = app.textFields["search.field"]
        XCTAssertGreaterThan(field.frame.minY, window.frame.height * 0.3)
        field.tap()
        XCTAssertTrue(app.buttons["search.close"].waitForExistence(timeout: 5))
        XCTAssertTrue(field.waitFor(\.frame.minY, below: window.frame.height * 0.25, timeout: 5), "focusing search did not expand the drawer: \(field.frame)")
        field.typeText("Amersfoort Centraal")
        let result = app.buttons.matching(NSPredicate(format: "identifier == 'search.result' AND label CONTAINS %@", "Amersfoort Centraal")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 20), "no result for Amersfoort Centraal")
        XCTAssertFalse(app.buttons["home.home"].exists, "saved places show over the results")
        screenshot("drawer-07-results")
        result.tap()

        let destination = app.staticTexts["preview.destination"]
        XCTAssertTrue(destination.waitForExistence(timeout: 10), "the preview did not open")
        XCTAssertFalse(field.exists, "the drawer stayed over the preview")
        app.buttons["preview.back"].tap()

        XCTAssertTrue(field.waitForExistence(timeout: 5), "the drawer did not come back after the preview")
        app.buttons["search.clear"].tap()
        XCTAssertTrue(app.buttons["home.recent.0"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["home.recent.0"].label.contains("Amersfoort"), app.buttons["home.recent.0"].label)
        app.buttons["search.close"].tap()
        XCTAssertTrue(app.buttons["search.close"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(field.waitFor(\.frame.minY, above: window.frame.height * 0.3, timeout: 5), "closing search did not return the drawer to medium: \(field.frame)")
    }

    private var window: XCUIElement { app.windows.firstMatch }

    private func launch(seeded: Bool) {
        app = XCUIApplication()
        app.launchArguments = [
            "-NaviscootDiscardActiveRide", "YES",
            "-NaviscootSimOrigin", "\(origin.lat),\(origin.lon)",
            "-settings.language", "en",
            "-settings.mapStyle", "liberty",
        ]
        app.launchArguments += seeded ? ["-NaviscootSeedHome", "YES"] : ["-NaviscootResetPlaces", "YES", "-NaviscootSeedHome", "NO"]
        app.launch()
        XCTAssertTrue(app.textFields["search.field"].waitForExistence(timeout: 10))
    }

    private func dragDrawer(by dy: CGFloat) {
        let field = app.textFields["search.field"]
        let grabber = window.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: window.frame.midX, dy: field.frame.minY - 22))
        grabber.press(forDuration: 0.2, thenDragTo: grabber.withOffset(CGVector(dx: 0, dy: dy)), withVelocity: .default, thenHoldForDuration: 0.3)
        Thread.sleep(forTimeInterval: 0.8)
    }

    private func drag(on point: CGVector, by offset: CGVector) {
        let from = window.coordinate(withNormalizedOffset: point)
        from.press(forDuration: 0.1, thenDragTo: from.withOffset(offset), withVelocity: .slow, thenHoldForDuration: 0.3)
    }

    private struct Camera {
        let lat: Double
        let lon: Double
        let zoom: Double
    }

    private func camera(_ element: XCUIElement) -> Camera? {
        let parts = (element.value as? String ?? "").split(separator: ",").compactMap { Double($0) }
        return parts.count == 3 ? Camera(lat: parts[0], lon: parts[1], zoom: parts[2]) : nil
    }

    private func distance(_ a: Camera, _ b: Camera) -> Double {
        max(abs(a.lat - b.lat), abs(a.lon - b.lon))
    }

    private func waitForCamera(_ element: XCUIElement, awayFrom previous: Camera? = nil, line: UInt = #line) throws -> Camera {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if let current = camera(element) {
                guard let previous else { return current }
                if distance(current, previous) > 0.00005 || abs(current.zoom - previous.zoom) > 0.05 { return current }
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return try XCTUnwrap(nil as Camera?, "line \(line): the camera did not change from \(String(describing: previous)): \(element.value ?? "nil")")
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

private extension XCUIElement {
    func waitFor(_ keyPath: KeyPath<XCUIElement, Bool>, timeout: TimeInterval) -> Bool {
        poll(timeout) { self[keyPath: keyPath] }
    }

    func waitFor(_ keyPath: KeyPath<XCUIElement, Any?>, equals expected: String, timeout: TimeInterval) -> Bool {
        poll(timeout) { self[keyPath: keyPath] as? String == expected }
    }

    func waitFor(_ keyPath: KeyPath<XCUIElement, CGFloat>, below limit: CGFloat, timeout: TimeInterval) -> Bool {
        poll(timeout) { self[keyPath: keyPath] < limit }
    }

    func waitFor(_ keyPath: KeyPath<XCUIElement, CGFloat>, above limit: CGFloat, timeout: TimeInterval) -> Bool {
        poll(timeout) { self[keyPath: keyPath] > limit }
    }

    private func poll(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if exists, condition() { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return exists && condition()
    }
}
