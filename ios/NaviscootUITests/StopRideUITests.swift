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
        XCTAssertFalse(app.buttons["ride.end"].exists)

        app.terminate()
        launch(discardRide: false)
        XCTAssertFalse(app.alerts["Resume your ride?"].waitForExistence(timeout: 4), "a declined ride was offered again")
    }

    private func launch(discardRide: Bool = true) {
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
        app.launchArguments = arguments
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
}
