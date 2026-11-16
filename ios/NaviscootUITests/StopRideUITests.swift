import XCTest

final class StopRideUITests: XCTestCase {
    private let domplein = (lat: 52.0907, lon: 5.1214)
    private let amersfoort = (query: "Lieve Vrouwestraat 33 Amersfoort", label: "Lieve Vrouwestraat 33,")
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
        launch(extra: ["-NaviscootSeedHome", "YES", "-NaviscootSimEditFailures", "1", "-settings.guidanceMode", "all"])
        planAndStart()
        XCTAssertTrue(app.staticTexts["ride.banner.distance"].waitForExistence(timeout: 20))

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
