import XCTest

final class LandscapeUITests: XCTestCase {
    private typealias Point = (lat: Double, lon: Double)

    private let domplein: Point = (52.0907, 5.1214)
    private let amersfoort = (query: "Lieve Vrouwestraat 33 Amersfoort", label: "Lieve Vrouwestraat 33,")
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard ProcessInfo.processInfo.environment["NAVISCOOT_API_KEY"] != nil else {
            throw XCTSkip("set TEST_RUNNER_NAVISCOOT_API_KEY to run the landscape proof against the local API")
        }
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    func testSearchPreviewTimeAndSettingsFitInLandscape() throws {
        launch(speedKmh: 30)
        rotate(to: .landscapeLeft)

        assertReachable(["search.field", "search.settings", "home.home", "home.work", "home.locate", "home.layers"])
        XCTAssertFalse(app.buttons["search.trips"].exists, "the old trip-history icon is still on the map")
        app.textFields["search.field"].tap()
        assertReachable(["search.close", "home.home", "home.work"])
        screenshot("landscape-01-search")

        app.buttons["search.close"].tap()
        XCTAssertTrue(app.buttons["search.close"].waitForNonExistence(timeout: 5))
        assertReachable(["home.home", "home.work"])
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)).press(forDuration: 1.2)
        let pin = app.staticTexts["search.pin"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5), "no pin after a long-press in landscape")
        let route = app.buttons["search.pin.route"]
        XCTAssertTrue(route.waitFor(\.isEnabled, timeout: 15), "the pin's address never resolved")
        assertReachable(["search.field", "search.pin.route", "search.pin.remove"])
        screenshot("landscape-02-pin")
        app.buttons["search.pin.remove"].tap()
        XCTAssertTrue(pin.waitForNonExistence(timeout: 5))

        let field = app.textFields["search.field"]
        field.tap()
        field.typeText(amersfoort.query)
        let result = app.buttons.matching(NSPredicate(format: "identifier == 'search.result' AND label CONTAINS %@", amersfoort.label)).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 15), "no result for \(amersfoort.query)")
        assertReachable(["search.field", "search.clear"])
        XCTAssertTrue(result.isHittable, "the first result is hidden in landscape")
        screenshot("landscape-03-results")
        result.tap()

        let start = app.buttons["preview.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 60), "Start is not offered")
        assertReachable(["preview.back", "preview.from", "preview.save", "preview.addStop", "preview.time", "preview.verifiedOnly", "preview.start"])
        XCTAssertTrue(app.staticTexts["preview.duration"].exists)
        screenshot("landscape-04-preview")

        let routes = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'preview.route.'"))
        for index in 0 ..< routes.count {
            let card = routes.element(boundBy: index)
            reveal(card, scrollingWith: start)
            assertReachable(card, "route card \(index)")
        }
        let total = app.descendants(matching: .any)["preview.total.carriageway"].firstMatch
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        reveal(total, scrollingWith: start)
        assertReachable(total, "the carriageway total")
        assertReachable(["preview.start", "preview.verifiedOnly"])
        screenshot("landscape-05-preview-scrolled")

        app.buttons["preview.time"].tap()
        let done = app.buttons["time.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        app.segmentedControls["time.mode"].buttons.element(boundBy: 1).tap()
        let wheel = app.datePickers["time.date"]
        XCTAssertTrue(wheel.waitForExistence(timeout: 5))
        XCTAssertTrue(isInsideWindow(wheel), "the time wheel is clipped: \(wheel.frame) in \(window.frame)")
        assertReachable(["time.done"])
        screenshot("landscape-06-time")
        app.buttons.matching(NSPredicate(format: "label == %@", "Cancel")).firstMatch.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5))

        app.buttons["preview.back"].tap()
        let settings = app.buttons["search.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        XCTAssertTrue(app.buttons["settings.done"].waitForExistence(timeout: 5))
        assertReachable(["settings.done"])
        XCTAssertTrue(isInsideWindow(app.descendants(matching: .any)["settings.language"].firstMatch))
        screenshot("landscape-07-settings")
        for _ in 0 ..< 6 { app.swipeUp() }
        assertReachable(["settings.done"])
        screenshot("landscape-08-settings-bottom")
        app.buttons["settings.done"].tap()
        XCTAssertTrue(settings.waitForExistence(timeout: 5))

        rotate(to: .portrait)
        assertReachable(["search.field", "search.settings", "search.clear", "home.locate", "home.layers"])
    }

    func testARideRotatedMidRideKeepsItsRouteAndStateAndFitsTheLandscapeFreeArea() throws {
        launch(speedKmh: 60)
        planAndStart()
        let distance = app.staticTexts["ride.banner.distance"]
        XCTAssertTrue(distance.waitForExistence(timeout: 20))
        let routeId = app.staticTexts["sim.routeId"].label
        XCTAssertFalse(routeId.isEmpty)
        let camera = app.staticTexts["sim.camera"]
        let activity = app.staticTexts["sim.activity"]
        wait(for: camera, labelContains: "camera=following", timeout: 15)
        wait(for: app.staticTexts["sim.spoken"], valueContains: "en-GB|", timeout: 30)
        let spokenBefore = spokenLines().count
        let remainingBefore = try remaining(activity)

        rotate(to: .landscapeLeft)
        assertRideReachable()
        wait(for: camera, labelContains: "inClear=yes", timeout: 15)
        XCTAssertTrue(camera.label.hasPrefix("camera=following"), camera.label)
        assertRemainingDrops(below: remainingBefore, activity)
        XCTAssertEqual(app.staticTexts["sim.routeId"].label, routeId, "rotating changed the route")
        screenshot("landscape-10-ride")

        app.buttons["ride.overview"].tap()
        wait(for: camera, labelBeginsWith: "camera=overview", timeout: 10)
        wait(for: camera, labelEndsWith: "fits=true", timeout: 15)
        let recenter = app.buttons["ride.recenter"]
        XCTAssertTrue(recenter.waitForExistence(timeout: 5))
        assertReachable(recenter, "recenter")
        sleep(2)
        screenshot("landscape-11-overview")

        rotate(to: .portrait)
        wait(for: camera, labelBeginsWith: "camera=overview", timeout: 10)
        wait(for: camera, labelEndsWith: "fits=true", timeout: 15)
        sleep(2)
        screenshot("landscape-12-overview-portrait")

        rotate(to: .landscapeRight)
        wait(for: camera, labelEndsWith: "fits=true", timeout: 15)
        recenter.tap()
        wait(for: camera, labelBeginsWith: "camera=following", timeout: 10)
        wait(for: camera, labelContains: "inClear=yes", timeout: 15)
        assertRideReachable()
        sleep(2)
        screenshot("landscape-13-ride-right")

        let remainingLandscape = try remaining(activity)
        rotate(to: .portrait)
        assertReachable(["ride.end", "ride.report", "ride.mute", "ride.edit", "ride.overview", "ride.speed"])
        assertRemainingDrops(below: remainingLandscape, activity)
        XCTAssertEqual(app.staticTexts["sim.routeId"].label, routeId, "rotating back changed the route")
        XCTAssertGreaterThanOrEqual(spokenLines().count, spokenBefore, "spoken lines were lost")
        XCTAssertTrue(activity.label.contains("activity=active system=active live=1"), activity.label)
        XCTAssertTrue(camera.label.hasPrefix("camera=following"), camera.label)
        screenshot("landscape-14-portrait-again")

        app.buttons["ride.end"].tap()
        let confirm = app.alerts.buttons.matching(identifier: "End ride").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "End did not ask first")
        confirm.tap()
        XCTAssertTrue(app.textFields["search.field"].waitForExistence(timeout: 10))

        rotate(to: .landscapeLeft)
        let seeAll = app.buttons["home.trips.all"]
        XCTAssertTrue(app.scrollViews["home.drawer"].waitForExistence(timeout: 5))
        for _ in 0 ..< 6 where !(seeAll.exists && seeAll.isHittable) {
            app.scrollViews["home.drawer"].swipeUp()
        }
        XCTAssertTrue(seeAll.exists, "the recorded ride is not in the side panel")
        seeAll.tap()
        XCTAssertTrue(app.buttons["trips.done"].waitForExistence(timeout: 5))
        let trip = app.buttons["trips.trip.0"]
        XCTAssertTrue(trip.waitForExistence(timeout: 5), "the ride was not recorded")
        assertReachable(["trips.done"])
        let middle = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        for _ in 0 ..< 6 where !(trip.exists && trip.isHittable && isInsideWindow(trip)) {
            middle.press(forDuration: 0.1, thenDragTo: middle.withOffset(CGVector(dx: 0, dy: -50)), withVelocity: .slow, thenHoldForDuration: 0.5)
        }
        assertReachable(trip, "first trip")
        screenshot("landscape-15-trips")
        trip.tap()
        let map = app.descendants(matching: .any)["trip.map"].firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 5))
        XCTAssertTrue(isInsideWindow(map), "trip map clipped: \(map.frame)")
        for id in ["trip.destination", "trip.distance", "trip.duration", "trip.speed"] {
            let element = app.descendants(matching: .any)[id].firstMatch
            XCTAssertTrue(element.exists, "\(id) missing")
            XCTAssertTrue(isInsideWindow(element), "\(id) clipped: \(element.frame)")
        }
        XCTAssertLessThan(map.frame.maxX, app.descendants(matching: .any)["trip.distance"].firstMatch.frame.minX, "the trip map is not beside the stats")
        screenshot("landscape-16-trip-detail")
    }

    private var window: XCUIElement { app.windows.firstMatch }

    private func launch(speedKmh: Int) {
        app = XCUIApplication()
        app.launchArguments = [
            "-NaviscootSimulateRide", "YES",
            "-NaviscootSimSpeedKmh", "\(speedKmh)",
            "-NaviscootSimOrigin", "\(domplein.lat),\(domplein.lon)",
            "-NaviscootDiscardActiveRide", "YES",
            "-settings.language", "en",
            "-settings.verifiedOnlyByDefault", "NO",
            "-settings.avoidFerries", "NO",
            "-settings.avoidUnpaved", "NO",
            "-settings.avoidMainRoads", "NO",
            "-settings.mapStyle", "liberty",
            "-settings.northUp", "NO",
            "-settings.threeD", "YES",
            "-settings.autoZoom", "NO",
        ]
        app.launch()
        XCTAssertTrue(app.textFields["search.field"].waitForExistence(timeout: 10))
    }

    private func planAndStart() {
        let field = app.textFields["search.field"]
        field.tap()
        field.typeText(amersfoort.query)
        let result = app.buttons.matching(NSPredicate(format: "identifier == 'search.result' AND label CONTAINS %@", amersfoort.label)).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 15), "no result for \(amersfoort.query)")
        result.tap()
        let start = app.buttons["preview.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 60), "Start is not offered")
        start.tap()
        XCTAssertTrue(app.buttons["ride.end"].waitForExistence(timeout: 10))
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

    private func assertRideReachable() {
        assertReachable(["ride.end", "ride.report", "ride.mute", "ride.edit", "ride.overview"])
        for id in ["ride.banner", "ride.speed", "ride.remaining", "ride.banner.distance", "ride.banner.street"] {
            let element = app.descendants(matching: .any)[id].firstMatch
            XCTAssertTrue(element.exists, "\(id) missing")
            XCTAssertTrue(isInsideWindow(element), "\(id) clipped: \(element.frame) in \(window.frame)")
        }
        let banner = app.descendants(matching: .any)["ride.banner"].firstMatch.frame
        let side = app.buttons["ride.overview"].frame
        let end = app.buttons["ride.end"].frame
        XCTAssertLessThan(banner.maxX, side.minX, "banner and buttons overlap")
        XCTAssertLessThan(banner.maxY, end.minY, "banner and ride bar overlap")
        XCTAssertLessThan(end.maxX, side.minX, "the ride bar runs under the buttons")
    }

    private func reveal(_ element: XCUIElement, scrollingWith anchor: XCUIElement) {
        let scroll = app.scrollViews.containing(.any, identifier: "preview.from").firstMatch
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let x = anchor.frame.midX
        for _ in 0 ..< 8 where !scroll.frame.contains(element.frame) {
            let mid = scroll.frame.midY
            let step: CGFloat = element.frame.minY < scroll.frame.minY ? -40 : 40
            origin.withOffset(CGVector(dx: x, dy: mid + step))
                .press(forDuration: 0.1, thenDragTo: origin.withOffset(CGVector(dx: x, dy: mid - step)), withVelocity: .slow, thenHoldForDuration: 0.5)
            sleep(1)
        }
        XCTAssertTrue(scroll.frame.contains(element.frame), "\(element.identifier) never scrolled into view: \(element.frame) in \(scroll.frame)")
    }

    private func assertReachable(_ ids: [String]) {
        for id in ids {
            let element = app.descendants(matching: .any)[id].firstMatch
            XCTAssertTrue(element.waitForExistence(timeout: 5), "\(id) missing")
            assertReachable(element, id)
        }
    }

    private func assertReachable(_ element: XCUIElement, _ name: String) {
        XCTAssertTrue(element.isHittable, "\(name) is not hittable: \(element.frame) in \(window.frame)")
        XCTAssertTrue(isInsideWindow(element), "\(name) is clipped: \(element.frame) in \(window.frame)")
    }

    private func isInsideWindow(_ element: XCUIElement) -> Bool {
        window.frame.insetBy(dx: -0.5, dy: -0.5).contains(element.frame)
    }

    private func remaining(_ activity: XCUIElement) throws -> Int {
        let label = activity.label
        let range = try XCTUnwrap(label.range(of: #"remainingM=-?[0-9]+"#, options: .regularExpression), label)
        return try XCTUnwrap(Int(label[range].dropFirst("remainingM=".count)), label)
    }

    private func assertRemainingDrops(below value: Int, _ activity: XCUIElement) {
        let dropped = expectation(for: NSPredicate { [weak self] _, _ in
            guard let self, let now = try? self.remaining(activity) else { return false }
            return now >= 0 && now < value
        }, evaluatedWith: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [dropped], timeout: 20), .completed, "the ride stopped after rotating: \(activity.label)")
    }

    private func spokenLines() -> [String] {
        let value = app.staticTexts["sim.spoken"].value as? String ?? ""
        return value.split(separator: "\n").map(String.init)
    }

    private func wait(for element: XCUIElement, labelContains text: String, timeout: TimeInterval) {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let result = XCTWaiter.wait(for: [expectation(for: predicate, evaluatedWith: element)], timeout: timeout)
        XCTAssertEqual(result, .completed, "\(element.identifier) never contained \(text): \(element.exists ? element.label : "missing")")
    }

    private func wait(for element: XCUIElement, labelBeginsWith text: String, timeout: TimeInterval) {
        let predicate = NSPredicate(format: "label BEGINSWITH %@", text)
        let result = XCTWaiter.wait(for: [expectation(for: predicate, evaluatedWith: element)], timeout: timeout)
        XCTAssertEqual(result, .completed, "\(element.identifier) never began with \(text): \(element.exists ? element.label : "missing")")
    }

    private func wait(for element: XCUIElement, labelEndsWith text: String, timeout: TimeInterval) {
        let predicate = NSPredicate(format: "label ENDSWITH %@", text)
        let result = XCTWaiter.wait(for: [expectation(for: predicate, evaluatedWith: element)], timeout: timeout)
        XCTAssertEqual(result, .completed, "\(element.identifier) never ended with \(text): \(element.exists ? element.label : "missing")")
    }

    private func wait(for element: XCUIElement, valueContains text: String, timeout: TimeInterval) {
        let predicate = NSPredicate(format: "value CONTAINS %@", text)
        let result = XCTWaiter.wait(for: [expectation(for: predicate, evaluatedWith: element)], timeout: timeout)
        XCTAssertEqual(result, .completed, "\(element.identifier) never contained \(text)")
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
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if exists, self[keyPath: keyPath] { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return false
    }
}
