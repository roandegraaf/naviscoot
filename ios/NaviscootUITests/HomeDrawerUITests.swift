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

        app.buttons["search.settings"].tap()
        XCTAssertTrue(app.buttons["settings.scooter"].waitForExistence(timeout: 5), "Settings did not open")
        let voiceMode = element("settings.voiceMode")
        XCTAssertTrue(voiceMode.isHittable, "the voice mode is not at the top of Settings")
        XCTAssertLessThan(element("settings.section.navigation").frame.maxY, voiceMode.frame.minY + 1)
        XCTAssertLessThan(voiceMode.frame.maxY, app.buttons["settings.voiceDetails"].frame.minY + 1, "the voice mode is not first in Navigation")
        XCTAssertEqual(voiceMode.buttons.allElementsBoundByIndex.map(\.label), ["All", "Alerts", "Off"])
        voiceMode.buttons["Alerts"].tap()
        XCTAssertTrue(voiceMode.buttons["Alerts"].isSelected)
        screenshot("drawer-15-settings-top")

        app.buttons["settings.voiceDetails"].tap()
        XCTAssertTrue(element("settings.voice.default").waitForExistence(timeout: 5), "the Voice page has no voice list")
        let rate = element("settings.speechRate")
        XCTAssertTrue(rate.exists, "the Voice page has no speaking rate")
        XCTAssertTrue(element("settings.speechVolume").exists, "the Voice page has no volume")
        screenshot("drawer-16-settings-voice")
        let rateBefore = rate.label
        rate.buttons.element(boundBy: 1).tap()
        wait(for: rate, labelChangesFrom: rateBefore)
        let rateRaised = rate.label
        rate.buttons.element(boundBy: 0).tap()
        wait(for: rate, labelChangesFrom: rateRaised)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(voiceMode.waitForExistence(timeout: 5))

        var order = ["scooter"]
        var pickedStyle = false
        for _ in 0 ..< 8 where order.count < 6 {
            let visible = ["navigation", "routeDefaults", "map", "general", "about"]
                .filter { !order.contains($0) && element("settings.section.\($0)").exists }
                .sorted { element("settings.section.\($0)").frame.minY < element("settings.section.\($1)").frame.minY }
            order += visible
            if !pickedStyle, element("settings.mapStyle.positron").isHittable {
                pickedStyle = true
                app.buttons["settings.mapStyle.positron"].tap()
                XCTAssertTrue(app.buttons["settings.mapStyle.positron"].isSelected, "tapping a map style card did not select it")
                screenshot("drawer-17-settings-map")
                app.buttons["settings.mapStyle.liberty"].tap()
                XCTAssertTrue(app.buttons["settings.mapStyle.liberty"].isSelected)
            }
            if order.count < 6 { app.swipeUp() }
        }
        XCTAssertEqual(order, ["scooter", "navigation", "routeDefaults", "map", "general", "about"])
        XCTAssertTrue(pickedStyle, "the map style cards never came into view")
        XCTAssertTrue(element("settings.language").exists)
        XCTAssertTrue(element("settings.appearance").exists)

        app.buttons["settings.done"].tap()
        XCTAssertTrue(app.buttons["settings.done"].waitForNonExistence(timeout: 5))
        app.buttons["search.settings"].tap()
        XCTAssertTrue(voiceMode.waitForExistence(timeout: 5))
        XCTAssertTrue(voiceMode.buttons["Alerts"].isSelected, "the voice mode did not stick")
        voiceMode.buttons["All"].tap()
        app.buttons["settings.done"].tap()
        XCTAssertTrue(app.buttons["settings.done"].waitForNonExistence(timeout: 5))
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

    func testThePreviewTidiesTheBreakdownReordersStopsAndPicksAnAlternativeFromTheMap() throws {
        launch(extra: ["-settings.verifiedOnlyByDefault", "NO"])
        app.buttons["home.home"].tap()
        let duration = app.staticTexts["preview.duration"]
        XCTAssertTrue(duration.waitForExistence(timeout: 30), "the route to Home did not load")
        let any = app.descendants(matching: .any)
        XCTAssertTrue(any["preview.total.carriageway"].exists)
        XCTAssertFalse(any["preview.total.moped_path"].exists, "a 0 m moped path row shows")
        XCTAssertFalse(any["preview.total.unverified"].exists, "a 0 m unverified row shows")
        XCTAssertFalse(app.switches["preview.verifiedOnly"].exists, "the verified-only toggle shows on a route without unverified stretches")
        screenshot("preview-01-breakdown")

        addStop("Koppelpoort")
        addStop("Lieve Vrouwestraat")
        let first = app.staticTexts["preview.stop.0"]
        let second = app.staticTexts["preview.stop.1"]
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        XCTAssertTrue(first.label.contains("Koppelpoort"), first.label)
        XCTAssertTrue(app.buttons["preview.stop.1.remove"].waitForExistence(timeout: 5))
        screenshot("preview-02-stops")

        second.press(forDuration: 1.0, thenDragTo: first, withVelocity: .slow, thenHoldForDuration: 0.5)
        wait(for: first, labelContains: "Lieve Vrouwestraat")
        XCTAssertTrue(second.label.contains("Koppelpoort"), second.label)
        screenshot("preview-03-reordered")

        app.terminate()
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("NaviscootTests/Fixtures/route-alternatives.json").path
        launch(extra: ["-NaviscootSimRoutesFile", fixture])
        app.buttons["home.home"].tap()
        let bubble = app.buttons["preview.bubble.2"]
        XCTAssertTrue(bubble.waitForExistence(timeout: 15), "no time bubble on the alternative")
        XCTAssertTrue(app.buttons["preview.bubble.1"].exists)
        XCTAssertTrue(app.buttons["preview.bubble.0"].isSelected)
        XCTAssertFalse(bubble.isSelected)
        XCTAssertTrue(bubble.label.hasSuffix("43 min"), bubble.label)
        screenshot("preview-04-alternatives")

        bubble.tap()
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'preview.route.2.'")).firstMatch
        let selected = expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: card)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed, "tapping the bubble did not select its route")
        XCTAssertTrue(bubble.isSelected)
        XCTAssertFalse(app.buttons["preview.bubble.0"].isSelected)
        screenshot("preview-05-alternative-selected")
    }

    private func addStop(_ name: String) {
        app.buttons["preview.addStop"].tap()
        let place = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'placeSearch.saved.' AND label CONTAINS %@", name)).firstMatch
        XCTAssertTrue(place.waitForExistence(timeout: 5), "\(name) is not among the saved places")
        place.tap()
        XCTAssertTrue(place.waitForNonExistence(timeout: 5))
    }

    func testParkedPinOffersWalkThereAndTheScooterStripOpensTheScooterScreen() throws {
        launch(extra: ["-NaviscootSeedParked", "\(origin.lat),\(origin.lon)"])
        XCTAssertFalse(app.buttons["home.scooter"].exists, "the strip shows without a scooter set up")
        dragDrawer(by: 400)
        let pin = app.buttons["home.parkedPin"]
        XCTAssertTrue(pin.waitForExistence(timeout: 10), "no parked scooter pin on the map")
        XCTAssertTrue(pin.isHittable)
        screenshot("drawer-10-parked-pin")
        XCTAssertEqual(pin.frame.midX, window.frame.midX, accuracy: 4, "the pin is not on the parked spot: \(pin.frame)")
        // The map centres the camera in its safe area, a few points below the window centre.
        XCTAssertEqual(pin.frame.midY, window.frame.midY, accuracy: 20, "the pin is not on the parked spot: \(pin.frame)")
        pin.tap()
        let walk = app.buttons["home.parkedPin.walk"]
        XCTAssertTrue(walk.waitForExistence(timeout: 5), "the pin does not offer Walk there")
        XCTAssertTrue(walk.isHittable)
        XCTAssertEqual(walk.label, "Walk there")
        screenshot("drawer-11-parked-callout")

        app.terminate()
        launch(extra: ["-NaviscootSimScooter", "charging"])
        let strip = app.buttons["home.scooter"]
        XCTAssertTrue(strip.waitForExistence(timeout: 10), "no scooter strip on home")
        wait(for: strip, valueContains: "64%, 31 km, Connected")
        XCTAssertTrue(strip.isHittable)
        XCTAssertFalse(app.buttons["home.parkedPin"].exists, "a connected scooter still shows as parked")
        screenshot("drawer-12-scooter-strip")
        dragDrawer(by: 400)
        XCTAssertTrue(strip.isHittable, "the strip is hidden with the drawer folded")
        strip.tap()
        let charging = element("settings.scooter.charging")
        XCTAssertTrue(charging.waitForExistence(timeout: 10), "the strip did not open the scooter screen")
        wait(for: charging, labelContains: "Charging")
        wait(for: element("scooter.battery"), valueContains: "64%")
        wait(for: element("scooter.range"), valueContains: "31 km")
        for id in ["settings.scooter.openSeat", "settings.scooter.powerOn", "settings.scooter.powerOff"] {
            XCTAssertTrue(app.buttons[id].isHittable, "\(id) is not reachable without scrolling")
            XCTAssertGreaterThanOrEqual(app.buttons[id].frame.height, 60, "\(id) is not a large button")
        }
        let fullIn = element("scooter.fullIn")
        XCTAssertTrue(fullIn.waitForExistence(timeout: 15), "no time to full while charging")
        XCTAssertTrue(fullIn.label.hasPrefix("Full in about"), fullIn.label)
        wait(for: element("scooter.cycles"), textContains: "87")
        XCTAssertTrue(element("scooter.health").exists)
        XCTAssertTrue(element("scooter.temperature").exists)
        XCTAssertFalse(element("settings.scooter.speedCurrent").exists, "the speed limit is still on the main scooter screen")
        screenshot("drawer-13-scooter-screen")

        app.buttons["settings.scooter.openSeat"].tap()
        let result = element("settings.scooter.actionResult")
        XCTAssertTrue(result.waitForExistence(timeout: 10), "Open seat gave no result")

        app.buttons["scooter.battery.details"].tap()
        let cells = element("scooter.details.cells")
        XCTAssertTrue(cells.waitForExistence(timeout: 10), "Details did not open")
        for id in ["scooter.details.capacity", "scooter.details.chargeCount", "scooter.details.serial"] {
            XCTAssertTrue(element(id).exists, "Details lacks \(id)")
        }
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let advanced = app.buttons["scooter.advanced"]
        scroll(to: advanced)
        advanced.tap()
        XCTAssertTrue(element("settings.scooter.speedCurrent").waitForExistence(timeout: 10), "Advanced has no speed limit")
        XCTAssertTrue(element("settings.scooter.topSpeedCurrent").exists, "Advanced has no top speed")
        screenshot("drawer-14-scooter-advanced")
        scroll(to: element("settings.scooter.recovery"))
        scroll(to: element("settings.scooter.feature.seatDetection"))
        let clock = element("settings.scooter.clock")
        scroll(to: clock)
        XCTAssertTrue(clock.exists, "Advanced has no clock")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["scooter.done"].waitForExistence(timeout: 5))
        app.buttons["scooter.done"].tap()
        XCTAssertTrue(strip.waitForExistence(timeout: 5))
        XCTAssertTrue(charging.waitForNonExistence(timeout: 5), "Done did not close the scooter screen")
    }

    private var window: XCUIElement { app.windows.firstMatch }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func scroll(to target: XCUIElement) {
        for _ in 0 ..< 6 where !(target.exists && target.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(target.isHittable, "could not scroll to \(target)")
    }

    private func launch(origin: (lat: Double, lon: Double)? = nil, eta: String? = nil, extra: [String] = []) {
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
        app.launchArguments += extra
        app.launch()
        XCTAssertTrue(app.textFields["search.field"].waitForExistence(timeout: 10))
    }

    private func wait(for element: XCUIElement, labelContains text: String) {
        let match = expectation(for: NSPredicate(format: "label CONTAINS %@", text), evaluatedWith: element)
        XCTAssertEqual(XCTWaiter.wait(for: [match], timeout: 10), .completed, "'\(text)' not in '\(element.label)'")
    }

    private func wait(for element: XCUIElement, labelChangesFrom text: String) {
        let match = expectation(for: NSPredicate(format: "label != %@", text), evaluatedWith: element)
        XCTAssertEqual(XCTWaiter.wait(for: [match], timeout: 5), .completed, "'\(element.label)' did not change")
    }

    private func wait(for element: XCUIElement, valueContains text: String) {
        let match = expectation(for: NSPredicate(format: "value CONTAINS %@", text), evaluatedWith: element)
        XCTAssertEqual(XCTWaiter.wait(for: [match], timeout: 10), .completed, "'\(text)' not in '\(element.value ?? "")'")
    }

    private func wait(for element: XCUIElement, textContains text: String) {
        let match = expectation(for: NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", text, text), evaluatedWith: element)
        XCTAssertEqual(XCTWaiter.wait(for: [match], timeout: 10), .completed, "'\(text)' not in '\(element.label)' / '\(element.value ?? "")'")
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
