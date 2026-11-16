import XCTest

final class StopRideUITests: XCTestCase {
    private let domplein = (lat: 52.0907, lon: 5.1214)
    private let amersfoort = (query: "Lieve Vrouwestraat 33 Amersfoort", label: "Lieve Vrouwestraat 33,")
    private let biltstraat = (query: "Biltstraat 100 Utrecht", label: "Biltstraat 100,")
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard ProcessInfo.processInfo.environment["NAVISCOOT_API_KEY"] != nil else {
            throw XCTSkip("set TEST_RUNNER_NAVISCOOT_API_KEY to run the stop ride proof against the API")
        }
    }

    func testDecliningTheResumeOfferForgetsTheRide() throws {
        launch()
        planAndStart()
        XCTAssertTrue(app.staticTexts["ride.banner.distance"].waitForExistence(timeout: 20))

        app.terminate()
        launch(discardRide: false)
        let offer = app.alerts["Resume your ride?"]
        XCTAssertTrue(offer.waitForExistence(timeout: 10))
        offer.buttons["End ride"].tap()
        XCTAssertTrue(offer.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons["ride.panel.toggle"].exists)

        app.terminate()
        launch(discardRide: false)
        XCTAssertFalse(app.alerts["Resume your ride?"].waitForExistence(timeout: 4), "a declined ride was offered again")
    }

    func testTheRideMapKeepsThreeButtonsAndThePanelHoldsTheRest() throws {
        launch(extra: ["-NaviscootSeedHome", "YES", "-NaviscootSimEditFailures", "1", "-settings.guidanceMode", "all", "-NaviscootSimScooter", "riding"])
        planAndStart()
        XCTAssertTrue(app.staticTexts["ride.banner.distance"].waitForExistence(timeout: 20))

        let battery = app.descendants(matching: .any)["ride.battery"]
        XCTAssertTrue(battery.waitForExistence(timeout: 15), "the panel shows no scooter battery")
        XCTAssertTrue(battery.label.hasPrefix("Battery 64% · "), battery.label)
        XCTAssertTrue(battery.label.hasSuffix(" on arrival"), battery.label)
        XCTAssertTrue(battery.isHittable, "the battery line is clipped by the collapsed panel")

        let report = app.buttons["ride.report"], mute = app.buttons["ride.mute"], recenter = app.buttons["ride.recenter"]
        for button in [report, mute, recenter] {
            XCTAssertTrue(button.isHittable, "\(button.identifier) is not on the map")
            XCTAssertFalse(button.label.isEmpty)
        }
        for id in ["ride.overview", "ride.end", "ride.edit.addStop", "ride.voiceMode"] {
            let element = app.descendants(matching: .any)[id]
            XCTAssertFalse(element.exists && element.isHittable, "\(id) is on the map, not in the panel")
        }
        screenshot("ride-00-map")

        app.buttons["ride.panel.toggle"].tap()
        let end = app.buttons["ride.end"]
        XCTAssertTrue(end.waitForHittable(timeout: 5), "the panel did not open")
        for id in ["ride.edit.addStop", "ride.edit.changeDestination", "ride.overview", "ride.voiceMode", "ride.northUp", "ride.threeD"] {
            XCTAssertTrue(app.descendants(matching: .any)[id].isHittable, "\(id) is missing from the panel")
        }
        screenshot("ride-01-panel")

        app.buttons["ride.overview"].tap()
        let camera = app.staticTexts["sim.camera"]
        let overview = expectation(for: NSPredicate(format: "label CONTAINS 'camera=overview' AND label CONTAINS ' fits='"), evaluatedWith: camera)
        wait(for: [overview], timeout: 10)
        Thread.sleep(forTimeInterval: 2)
        XCTAssertTrue(camera.label.contains("fits=true"), "the overview does not fit the remaining route: \(camera.label)")
        let fill = camera.label.components(separatedBy: " ").first { $0.hasPrefix("fill=") }.flatMap { Double($0.dropFirst(5)) }
        XCTAssertGreaterThan(fill ?? 0, 0.6, "the overview leaves the route small in the clear map area: \(camera.label)")
        screenshot("ride-01b-overview")
        app.buttons["ride.panel.toggle"].tap()
        XCTAssertTrue(end.waitForHittable(timeout: 5), "the panel did not reopen after the overview")

        let voice = app.segmentedControls["ride.voiceMode"]
        voice.buttons["Off"].tap()
        XCTAssertEqual(mute.label, "Unmute voice")
        XCTAssertEqual(mute.value as? String, "Off")
        app.buttons["ride.panel.toggle"].tap()
        XCTAssertTrue(mute.waitForHittable(timeout: 5), "mute is still under the panel")
        mute.tap()
        XCTAssertEqual(mute.label, "Mute voice")
        app.buttons["ride.panel.toggle"].tap()
        XCTAssertTrue(end.waitForHittable(timeout: 5))
        XCTAssertTrue(voice.buttons["All"].isSelected)
        voice.buttons["Alerts"].tap()
        XCTAssertEqual(mute.value as? String, "Alerts")
        voice.buttons["All"].tap()

        app.buttons["ride.edit.addStop"].tap()
        let saved = app.buttons["placeSearch.saved.0"]
        XCTAssertTrue(saved.waitForExistence(timeout: 5), "the stop search shows no saved places")
        saved.tap()
        let failed = app.descendants(matching: .any)["ride.editFailed"]
        XCTAssertTrue(failed.waitForExistence(timeout: 10), "the simulated edit failure did not show")
        for button in [report, mute] {
            XCTAssertTrue(button.isHittable, "\(button.identifier) is not tappable under the error")
            XCTAssertFalse(button.frame.intersects(failed.frame), "the error covers \(button.identifier)")
        }
        XCTAssertTrue(recenter.isHittable)
        screenshot("ride-02-edit-failed")

        app.buttons["ride.panel.toggle"].tap()
        XCTAssertTrue(end.waitForHittable(timeout: 5))
        end.tap()
        let confirm = app.alerts.buttons.matching(identifier: "End ride").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "End did not ask first")
        confirm.tap()
        XCTAssertTrue(app.textFields["search.field"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["home.home"].waitForExistence(timeout: 10), "the home drawer did not come back after the ride")
    }

    func testArrivingShowsTheArrivalCardAndParkedHereRecordsTheSpot() throws {
        launch(extra: ["-NaviscootSimScooter", "riding"])
        XCTAssertTrue(app.buttons["home.home"].waitForExistence(timeout: 10))
        let parkedRow = app.buttons["home.parkedScooter"]
        XCTAssertTrue(parkedRow.waitForNonExistence(timeout: 10), "a parked spot from an earlier run was not cleared by the connected scooter")
        planAndStart(biltstraat)

        let title = app.descendants(matching: .any)["ride.arrival.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 240), "the ride did not arrive")
        XCTAssertTrue(title.label.hasPrefix("Arrived"), title.label)
        let ridden = app.descendants(matching: .any)["ride.arrival.ridden"]
        XCTAssertTrue(ridden.exists)
        XCTAssertTrue(ridden.label.contains("km") || ridden.label.contains(" m"), ridden.label)
        XCTAssertTrue(app.descendants(matching: .any)["ride.arrival.battery"].exists, "the arrival card shows no battery used")
        let parkedHere = app.buttons["ride.arrival.parkedHere"]
        XCTAssertTrue(parkedHere.waitForHittable(timeout: 5), "Parked here is not reachable")
        screenshot("ride-03-arrived")
        parkedHere.tap()
        let saved = app.descendants(matching: .any)["ride.arrival.parkedHere"]
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        XCTAssertEqual(saved.label, "Spot saved")
        XCTAssertFalse(app.buttons["ride.arrival.parkedHere"].exists, "Parked here can be tapped twice")

        app.buttons["ride.arrival.done"].tap()
        XCTAssertFalse(app.alerts.firstMatch.waitForExistence(timeout: 2), "Done asked for confirmation after arriving")
        XCTAssertTrue(app.textFields["search.field"].waitForExistence(timeout: 10))
        XCTAssertTrue(parkedRow.waitForExistence(timeout: 10), "Parked here did not record the spot")
    }

    private func launch(discardRide: Bool = true, extra: [String] = []) {
        app = XCUIApplication()
        var arguments = [
            "-NaviscootSimulateRide", "YES",
            "-NaviscootSimSpeedKmh", "120",
            "-NaviscootSimOrigin", "\(domplein.lat),\(domplein.lon)",
            "-settings.language", "en",
            "-settings.verifiedOnlyByDefault", "NO",
            "-settings.avoidFerries", "NO",
            "-settings.avoidUnpaved", "NO",
            "-settings.avoidMainRoads", "NO",
        ]
        if discardRide {
            arguments += ["-NaviscootDiscardActiveRide", "YES"]
        }
        app.launchArguments = arguments + extra
        app.launch()
        XCTAssertTrue(app.textFields["search.field"].waitForExistence(timeout: 10))
    }

    private func planAndStart(_ place: (query: String, label: String)? = nil) {
        let place = place ?? amersfoort
        let field = app.textFields["search.field"]
        field.tap()
        field.typeText(place.query)
        let result = app.buttons.matching(NSPredicate(format: "identifier == 'search.result' AND label CONTAINS %@", place.label)).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 15), "no result for \(place.query)")
        result.tap()
        let start = app.buttons["preview.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 60), "Start is not offered")
        start.tap()
        XCTAssertTrue(app.buttons["ride.panel.toggle"].waitForExistence(timeout: 10))
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
    func waitForHittable(timeout: TimeInterval) -> Bool {
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: self)
        return XCTWaiter.wait(for: [hittable], timeout: timeout) == .completed
    }
}
