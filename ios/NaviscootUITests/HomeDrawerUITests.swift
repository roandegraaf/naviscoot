import XCTest

final class HomeDrawerUITests: XCTestCase {
    private let origin = (lat: 52.1533, lon: 5.3728)
    private let fiveKilometresNorthOfHome = (lat: 52.1940, lon: 5.3738)
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testSavedPlacesAndTripsShowOnLaunchWithoutFocusingSearch() throws {
        launch()
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

    func testSearchingExpandsTheDrawerAndAResultOpensThePreviewThenTheDrawerComesBack() throws {
        launch()
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

    func testHomeFiveKilometresAwayShowsItsETAOrOnlyTheDistanceWhenTheAPIFails() throws {
        launch(origin: fiveKilometresNorthOfHome, eta: "720")
        let home = app.buttons["home.home"]
        XCTAssertTrue(home.waitForExistence(timeout: 5))
        wait(for: home, labelContains: "12 min · Utrechtseweg 1")
        screenshot("drawer-08-eta")
        home.tap()
        XCTAssertTrue(app.staticTexts["preview.destination"].waitForExistence(timeout: 10), "the Home row did not open the preview")

        app.terminate()
        launch(origin: fiveKilometresNorthOfHome, eta: "fail")
        XCTAssertTrue(home.waitForExistence(timeout: 5))
        wait(for: home, labelContains: "5.0 km · Utrechtseweg 1")
        Thread.sleep(forTimeInterval: 2)
        XCTAssertFalse(home.label.contains("min"), home.label)
        screenshot("drawer-09-eta-failed")
    }

    private var window: XCUIElement { app.windows.firstMatch }

    private func launch(origin: (lat: Double, lon: Double)? = nil, eta: String? = nil) {
        let origin = origin ?? self.origin
        app = XCUIApplication()
        app.launchArguments = [
            "-NaviscootDiscardActiveRide", "YES",
            "-NaviscootSimOrigin", "\(origin.lat),\(origin.lon)",
            "-settings.language", "en",
            "-settings.mapStyle", "liberty",
            "-NaviscootSeedHome", "YES",
        ]
        if let eta {
            app.launchArguments += ["-NaviscootSimETA", eta]
        }
        app.launch()
        XCTAssertTrue(app.textFields["search.field"].waitForExistence(timeout: 10))
    }

    private func wait(for element: XCUIElement, labelContains text: String) {
        let match = expectation(for: NSPredicate(format: "label CONTAINS %@", text), evaluatedWith: element)
        XCTAssertEqual(XCTWaiter.wait(for: [match], timeout: 10), .completed, "'\(text)' not in '\(element.label)'")
    }

    private func dragDrawer(by dy: CGFloat) {
        let field = app.textFields["search.field"]
        let grabber = window.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: window.frame.midX, dy: field.frame.minY - 22))
        grabber.press(forDuration: 0.2, thenDragTo: grabber.withOffset(CGVector(dx: 0, dy: dy)), withVelocity: .default, thenHoldForDuration: 0.3)
        Thread.sleep(forTimeInterval: 0.8)
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
