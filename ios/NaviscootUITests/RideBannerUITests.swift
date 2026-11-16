import XCTest

final class RideBannerUITests: XCTestCase {
    private typealias Point = (lat: Double, lon: Double)

    private let beforeCloseTurns: Point = (52.229047, 5.47976)
    private let beforeLaneTurn: Point = (52.128964, 5.41559)
    private let address = "Woudenbergseweg 42 Maarsbergen"
    private var app: XCUIApplication!

    private struct Puck {
        let course: Double
        let bearing: Double
        let screen: Double
        let ridden: Int

        init?(_ label: String) {
            func value(_ key: String) -> Double? {
                guard let range = label.range(of: "\(key)=(-?[0-9]+)", options: .regularExpression) else { return nil }
                return Double(label[range].dropFirst(key.count + 1))
            }
            guard let course = value("course"), let bearing = value("bearing"), let screen = value("screen"), let ridden = value("ridden") else {
                return nil
            }
            self.course = course
            self.bearing = bearing
            self.screen = screen
            self.ridden = Int(ridden)
        }
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard ProcessInfo.processInfo.environment["NAVISCOOT_API_KEY"] != nil else {
            throw XCTSkip("set TEST_RUNNER_NAVISCOOT_API_KEY to run the banner proof against the local API")
        }
    }

    func testCloseTurnsAndARoundaboutShowNextNextAndExitWhileThePuckAndLineFollowTheRide() throws {
        launch(origin: beforeCloseTurns)
        startRide()

        let then = app.descendants(matching: .any)["ride.banner.then"]
        XCTAssertTrue(then.waitForExistence(timeout: 30), "no next-next row before two close turns")
        XCTAssertEqual(then.label, "Then: Vleenenck")
        XCTAssertEqual(app.staticTexts["ride.banner.street"].label, "Havenstraat")
        XCTAssertFalse(app.staticTexts["ride.banner.exit"].exists, "an exit number without a roundabout")
        XCTAssertFalse(app.descendants(matching: .any)["ride.banner.lanes"].exists, "lanes without lane data")

        let puckText = app.staticTexts["sim.puck"]
        let start = try waitForPuck(puckText) { $0.ridden > 0 }
        XCTAssertLessThanOrEqual(abs(start.screen), 20, "the arrow is not pointing up in course-up following: \(puckText.label)")
        screenshot("banner-01-next-next")

        app.buttons["ride.overview"].tap()
        wait(for: app.staticTexts["sim.camera"], labelBeginsWith: "camera=overview", timeout: 10)
        let overview = try waitForPuck(puckText) { $0.bearing == 0 || $0.bearing == 360 }
        XCTAssertEqual(abs(Self.angle(overview.screen - overview.course)), 0, accuracy: 1, "north-up overview must draw the arrow at the course: \(puckText.label)")
        screenshot("puck-01-overview")
        app.buttons["ride.recenter"].tap()
        wait(for: app.staticTexts["sim.camera"], labelBeginsWith: "camera=following", timeout: 10)

        let turned = try waitForPuck(puckText, timeout: 60) { abs(Self.angle($0.course - start.course)) > 45 }
        XCTAssertGreaterThan(turned.ridden, start.ridden, "the ridden part did not grow")
        screenshot("banner-02-after-turn")

        wait(for: then, labelEquals: "Then: Torenstraat", timeout: 20)

        let exit = app.staticTexts["ride.banner.exit"]
        XCTAssertTrue(exit.waitForExistence(timeout: 120), "no exit number before the roundabout")
        XCTAssertEqual(exit.label, "Take exit 2")
        XCTAssertEqual(app.staticTexts["ride.banner.street"].label, "Frieswijkstraat")
        XCTAssertFalse(then.exists, "a next-next row while approaching the roundabout")
        let atRoundabout = try XCTUnwrap(Puck(puckText.label))
        XCTAssertGreaterThan(atRoundabout.ridden, turned.ridden)
        screenshot("banner-03-roundabout-exit")
    }

    func testAStepWithLaneDataShowsTheLanesRowOnlyNearTheTurn() throws {
        launch(origin: beforeLaneTurn)
        startRide()

        let distance = app.staticTexts["ride.banner.distance"]
        XCTAssertTrue(distance.waitForExistence(timeout: 30))
        XCTAssertEqual(app.staticTexts["ride.banner.street"].label, "Ben Pon Baan")
        let lanes = app.descendants(matching: .any)["ride.banner.lanes"]
        XCTAssertFalse(lanes.exists, "lanes shown \(distance.label) before the turn, outside the instruction that carries them")
        screenshot("lanes-01-far")

        XCTAssertTrue(lanes.waitForExistence(timeout: 90), "no lanes row near the turn")
        XCTAssertEqual(lanes.label, "Lanes: 1 of 2 go your way")
        XCTAssertEqual(app.descendants(matching: .any)["ride.banner.then"].label, "Then: Hekkerdreef")
        screenshot("lanes-02-near")

        let camera = app.staticTexts["sim.camera"]
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.71))
        from.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.64)))
        wait(for: camera, labelBeginsWith: "camera=free", timeout: 10)
        let puckText = app.staticTexts["sim.puck"]
        let parked = try waitForPuck(puckText) { _ in true }
        screenshot("puck-02-free")
        let moved = try waitForPuck(puckText, timeout: 60) { abs(Self.angle($0.course - parked.course)) > 45 }
        XCTAssertEqual(moved.bearing, parked.bearing, accuracy: 1, "the free map rotated on its own")
        XCTAssertGreaterThan(moved.ridden, parked.ridden)
        screenshot("puck-03-free-after-turn")
        app.buttons["ride.recenter"].tap()
        wait(for: camera, labelBeginsWith: "camera=following", timeout: 10)
    }

    private static func angle(_ degrees: Double) -> Double {
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value > 180 { value -= 360 }
        if value <= -180 { value += 360 }
        return value
    }

    private func waitForPuck(_ element: XCUIElement, timeout: TimeInterval = 20, until condition: @escaping (Puck) -> Bool) throws -> Puck {
        let match = expectation(for: NSPredicate { _, _ in Puck(element.label).map(condition) ?? false }, evaluatedWith: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [match], timeout: timeout), .completed, "puck never matched; last: \(element.label)")
        return try XCTUnwrap(Puck(element.label))
    }

    private func launch(origin: Point) {
        app = XCUIApplication()
        app.launchArguments = [
            "-NaviscootSimulateRide", "YES",
            "-NaviscootSimSpeedKmh", "36",
            "-NaviscootSimOrigin", "\(origin.lat),\(origin.lon)",
            "-NaviscootDiscardActiveRide", "YES",
            "-settings.language", "en",
            "-settings.verifiedOnlyByDefault", "NO",
            "-settings.avoidFerries", "NO",
            "-settings.avoidUnpaved", "NO",
            "-settings.avoidMainRoads", "NO",
        ]
        app.launch()
    }

    private func startRide() {
        let field = app.textFields["search.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(address)
        let result = app.buttons.matching(NSPredicate(format: "identifier == 'search.result' AND label CONTAINS %@", "Woudenbergseweg 42,")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 15))
        result.tap()
        let start = app.buttons["preview.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 40))
        start.tap()
        XCTAssertTrue(app.buttons["ride.end"].waitForExistence(timeout: 10))
    }

    private func wait(for element: XCUIElement, labelEquals text: String, timeout: TimeInterval) {
        let match = expectation(for: NSPredicate(format: "label == %@", text), evaluatedWith: element)
        XCTAssertEqual(XCTWaiter.wait(for: [match], timeout: timeout), .completed, "expected '\(text)', shown '\(element.label)'")
    }

    private func wait(for element: XCUIElement, labelBeginsWith text: String, timeout: TimeInterval) {
        let match = expectation(for: NSPredicate(format: "label BEGINSWITH %@", text), evaluatedWith: element)
        XCTAssertEqual(XCTWaiter.wait(for: [match], timeout: timeout), .completed, "expected '\(text)…', shown '\(element.label)'")
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
