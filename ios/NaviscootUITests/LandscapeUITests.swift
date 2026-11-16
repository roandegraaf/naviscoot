import XCTest

final class LandscapeUITests: XCTestCase {
    private let domplein = (lat: 52.0907, lon: 5.1214)
    private let amersfoort = (query: "Lieve Vrouwestraat 33 Amersfoort", label: "Lieve Vrouwestraat 33,")
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard ProcessInfo.processInfo.environment["NAVISCOOT_API_KEY"] != nil else {
            throw XCTSkip("set TEST_RUNNER_NAVISCOOT_API_KEY to run the landscape proof against the API")
        }
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    func testHomeSearchAndPreviewFitInLandscape() throws {
        launch()
        rotate(to: .landscapeLeft)

        assertReachable(["search.field", "search.settings", "home.scooter", "home.home", "home.work", "home.locate", "home.layers"])
        screenshot("landscape-00-home")
        let field = app.textFields["search.field"]
        field.tap()
        assertReachable(["search.close", "home.home", "home.work"])
        screenshot("landscape-01-search")

        field.typeText(amersfoort.query)
        let result = app.buttons.matching(NSPredicate(format: "identifier == 'search.result' AND label CONTAINS %@", amersfoort.label)).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 15), "no result for \(amersfoort.query)")
        assertReachable(["search.field", "search.clear"])
        XCTAssertTrue(result.isHittable, "the first result is hidden in landscape")
        result.tap()

        let start = app.buttons["preview.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 60), "Start is not offered")
        assertReachable(["preview.back", "preview.from", "preview.save", "preview.addStop", "preview.time", "preview.start"])
        XCTAssertTrue(app.staticTexts["preview.duration"].exists)
        screenshot("landscape-02-preview")

        app.buttons["preview.back"].tap()
        XCTAssertTrue(app.buttons["search.clear"].waitForExistence(timeout: 5))
        rotate(to: .portrait)
        assertReachable(["search.field", "search.settings", "search.clear", "home.scooter", "home.locate", "home.layers"])
    }

    private var window: XCUIElement { app.windows.firstMatch }

    private func launch() {
        app = XCUIApplication()
        app.launchArguments = [
            "-NaviscootSimOrigin", "\(domplein.lat),\(domplein.lon)",
            "-NaviscootDiscardActiveRide", "YES",
            "-settings.language", "en",
            "-settings.verifiedOnlyByDefault", "NO",
            "-settings.avoidFerries", "NO",
            "-settings.avoidUnpaved", "NO",
            "-settings.avoidMainRoads", "NO",
            "-settings.mapStyle", "liberty",
            "-NaviscootSimScooter", "charging",
        ]
        app.launch()
        XCTAssertTrue(app.textFields["search.field"].waitForExistence(timeout: 10))
    }

    private func rotate(to orientation: UIDeviceOrientation) {
        XCUIDevice.shared.orientation = orientation
        let landscape = orientation.isLandscape
        let rotated = expectation(for: NSPredicate { [window] _, _ in
            let frame = window.frame
            return landscape ? frame.width > frame.height : frame.height > frame.width
        }, evaluatedWith: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 10), .completed, "the window did not rotate: \(window.frame)")
        sleep(1)
    }

    private func assertReachable(_ ids: [String]) {
        for id in ids {
            let element = app.descendants(matching: .any)[id].firstMatch
            XCTAssertTrue(element.waitForExistence(timeout: 5), "\(id) missing")
            XCTAssertTrue(element.isHittable, "\(id) is not hittable: \(element.frame) in \(window.frame)")
            XCTAssertTrue(window.frame.insetBy(dx: -0.5, dy: -0.5).contains(element.frame), "\(id) is clipped: \(element.frame) in \(window.frame)")
        }
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
