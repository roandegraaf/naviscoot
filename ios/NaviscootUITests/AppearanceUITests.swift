import XCTest

final class AppearanceUITests: XCTestCase {
    private typealias Point = (lat: Double, lon: Double)

    private let caseOrigin: Point = (52.2977646, 5.445363)
    private let beforeCloseTurns: Point = (52.229047, 5.47976)
    private let beforeLaneTurn: Point = (52.128964, 5.41559)
    private let beforeUnverifiedStretch: Point = (52.0637, 5.407623)
    private let address = "Woudenbergseweg 42 Maarsbergen"
    private var app: XCUIApplication!

    private struct Camera {
        let mode: String
        let zoom: Double
        let pitch: Double
        let direction: Double

        init?(_ label: String) {
            func value(_ key: String) -> Double? {
                guard let range = label.range(of: "\(key)=-?[0-9.]+", options: .regularExpression) else { return nil }
                return Double(label[range].dropFirst(key.count + 1))
            }
            guard let modeRange = label.range(of: "camera=[a-z]+", options: .regularExpression),
                  let zoom = value("zoom"), let pitch = value("pitch"), let direction = value("direction")
            else { return nil }
            mode = String(label[modeRange].dropFirst("camera=".count))
            self.zoom = zoom
            self.pitch = pitch
            self.direction = direction
        }

        var isNorthUp: Bool { direction.truncatingRemainder(dividingBy: 360) == 0 }
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard ProcessInfo.processInfo.environment["NAVISCOOT_API_KEY"] != nil else {
            throw XCTSkip("set TEST_RUNNER_NAVISCOOT_API_KEY to run the appearance proof against the local API")
        }
    }

    func testDarkAppearanceGivesDarkPanelsAndADarkMapOnEveryScreen() {
        launch(origin: caseOrigin, extra: ["-settings.appearance", "dark"])

        let field = app.textFields["search.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        assertDark(CGPoint(x: field.frame.maxX - 6, y: field.frame.midY), "search field")
        screenshot("dark-01-search")

        app.buttons["search.settings"].tap()
        let done = app.buttons["settings.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Appearance' OR label == 'APPEARANCE'")).firstMatch.exists, "no Appearance section")
        assertDark(CGPoint(x: 12, y: done.frame.midY), "settings navigation bar")
        screenshot("dark-02-settings")
        let autoZoom = app.switches["settings.autoZoom"]
        for _ in 0..<6 where !autoZoom.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(autoZoom.isHittable, "the map settings are not reachable")
        screenshot("dark-03-settings-map")
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5))

        openPreview()
        assertDark(CGPoint(x: 16, y: screenSize.height - 14), "preview sheet")
        screenshot("dark-04-preview")

        app.buttons["preview.addStop"].tap()
        let cancelSearch = app.buttons["placeSearch.cancel"]
        XCTAssertTrue(cancelSearch.waitForExistence(timeout: 5))
        assertDark(CGPoint(x: 12, y: cancelSearch.frame.midY), "place search sheet")
        screenshot("dark-04b-place-search")
        cancelSearch.tap()
        XCTAssertTrue(cancelSearch.waitForNonExistence(timeout: 5))

        app.buttons["preview.time"].tap()
        let timeDone = app.buttons["time.done"]
        XCTAssertTrue(timeDone.waitForExistence(timeout: 5))
        assertDark(CGPoint(x: screenSize.width / 2, y: screenSize.height - 14), "time sheet")
        screenshot("dark-04c-time")
        app.buttons.matching(NSPredicate(format: "label == 'Cancel'")).firstMatch.tap()
        XCTAssertTrue(timeDone.waitForNonExistence(timeout: 5))

        app.buttons["preview.start"].tap()
        XCTAssertTrue(app.buttons["ride.end"].waitForExistence(timeout: 10))
        let style = app.staticTexts["sim.style"]
        wait(for: style, labelBeginsWith: "style=dark layers=5/5", timeout: 20)
        assertDark(CGPoint(x: 16, y: screenSize.height - 14), "ride bar")
        screenshot("dark-05-ride")

        app.buttons["ride.end"].tap()
        let keepRiding = app.buttons["Keep riding"]
        XCTAssertTrue(keepRiding.waitForExistence(timeout: 5))
        screenshot("dark-06-end-alert")
        keepRiding.tap()
        XCTAssertTrue(keepRiding.waitForNonExistence(timeout: 5))
    }

    func testPickingDarkInTheOpenSettingsSheetTurnsTheAppDarkRightAway() {
        launch(origin: caseOrigin, extra: ["-settings.appearance", "light"])
        let field = app.textFields["search.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        app.buttons["search.settings"].tap()
        let done = app.buttons["settings.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        let navigationBar = CGPoint(x: 12, y: done.frame.midY)
        assertLight(navigationBar, "settings sheet before picking Dark")

        let light = app.buttons["Light"]
        for _ in 0..<6 where !light.isHittable {
            app.swipeUp()
        }
        appearanceRow(below: light).tap()
        let turnedDark = expectation(for: NSPredicate { [weak self] _, _ in (self?.luminance(at: navigationBar) ?? 1) < 0.25 }, evaluatedWith: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [turnedDark], timeout: 5), .completed, "the open settings sheet did not turn dark")
        screenshot("dark-00-picked-in-settings")
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5))
        assertDark(CGPoint(x: field.frame.maxX - 6, y: field.frame.midY), "search field after picking Dark")

        app.buttons["search.settings"].tap()
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        for _ in 0..<6 where !light.isHittable {
            app.swipeUp()
        }
        appearanceRow(above: light).tap()
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5))
        assertLight(CGPoint(x: field.frame.maxX - 6, y: field.frame.midY), "search field back on System")
    }

    // "System" and "Dark" also name a language and a map style row; the Appearance ones sit right around "Light".
    private func appearanceRow(above light: XCUIElement) -> XCUIElement {
        nearest(label: "System", to: light) { $0.frame.midY < light.frame.midY }
    }

    private func appearanceRow(below light: XCUIElement) -> XCUIElement {
        nearest(label: "Dark", to: light) { $0.frame.midY > light.frame.midY }
    }

    private func nearest(label: String, to anchor: XCUIElement, where side: (XCUIElement) -> Bool) -> XCUIElement {
        let candidates = app.buttons.matching(NSPredicate(format: "label == %@", label)).allElementsBoundByIndex.filter(side)
        let row = candidates.min { abs($0.frame.midY - anchor.frame.midY) < abs($1.frame.midY - anchor.frame.midY) }
        XCTAssertNotNil(row, "no \(label) row next to Light")
        return row ?? anchor
    }

    // The runner shares the simulator's appearance, so its own trait is the OS setting. With NAVISCOOT_OS_APPEARANCE_FLIP
    // set, the person running the test flips it with `xcrun simctl ui <device> appearance` after system-01 is written.
    func testSystemAppearanceFollowsTheOSWhileTheAppRuns() {
        launch(origin: caseOrigin, extra: ["-settings.appearance", "system"])
        let field = app.textFields["search.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        let sample = CGPoint(x: field.frame.maxX - 6, y: field.frame.midY)
        let osIsDark = UIScreen.main.traitCollection.userInterfaceStyle == .dark
        if osIsDark {
            assertDark(sample, "search field with the OS in dark mode")
        } else {
            assertLight(sample, "search field with the OS in light mode")
        }
        screenshot("system-01-os-\(osIsDark ? "dark" : "light")")

        guard ProcessInfo.processInfo.environment["NAVISCOOT_OS_APPEARANCE_FLIP"]?.isEmpty == false else { return }
        let flipped = expectation(for: NSPredicate { [weak self] _, _ in
            guard let value = self?.luminance(at: sample) else { return false }
            return osIsDark ? value > 0.85 : value < 0.25
        }, evaluatedWith: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [flipped], timeout: 90), .completed, "the app did not follow the OS switch")
        screenshot("system-02-os-\(osIsDark ? "light" : "dark")")
    }

    func testAForcedNightClockGivesTheDarkMapOnTheRideWithTheRouteLinesIntact() {
        launch(origin: beforeUnverifiedStretch, speedKmh: 45, extra: ["-settings.appearance", "light", "-NaviscootSimClock", "2026-11-15T21:00:00Z"])
        openPreview()
        Thread.sleep(forTimeInterval: 4)
        assertLight(CGPoint(x: 16, y: screenSize.height - 14), "preview sheet in light appearance")
        screenshot("night-01-preview")

        app.buttons["preview.start"].tap()
        XCTAssertTrue(app.buttons["ride.end"].waitForExistence(timeout: 10))
        let style = app.staticTexts["sim.style"]
        wait(for: style, labelBeginsWith: "style=dark layers=5/5", timeout: 20)
        waitForRouteFeatures(style)
        assertLight(CGPoint(x: 16, y: screenSize.height - 14), "ride bar in light appearance")
        screenshot("night-02-ride")

        let warning = app.descendants(matching: .any)["ride.warning"]
        XCTAssertTrue(warning.waitForExistence(timeout: 60), "no warning before the unverified stretch")
        screenshot("night-03-unverified-ahead")
        wait(for: warning, labelBeginsWith: "On unverified path, ", timeout: 120)
        Thread.sleep(forTimeInterval: 3)
        screenshot("night-04-on-unverified")

        app.buttons["ride.overview"].tap()
        wait(for: app.staticTexts["sim.camera"], labelBeginsWith: "camera=overview", timeout: 10)
        waitForRouteFeatures(style)
        screenshot("night-05-overview")
    }

    func testTheMapTurnsDarkAtSunsetMidRideAndKeepsItsRouteLayers() {
        launch(origin: caseOrigin, extra: ["-settings.appearance", "light", "-NaviscootSimClock", "2026-11-15T15:44:45Z"])
        startRide()
        let style = app.staticTexts["sim.style"]
        wait(for: style, labelBeginsWith: "style=liberty layers=5/5", timeout: 10)
        waitForRouteFeatures(style)
        screenshot("sunset-01-before")

        wait(for: style, labelBeginsWith: "style=dark", timeout: 120)
        wait(for: style, labelBeginsWith: "style=dark layers=5/5", timeout: 20)
        waitForRouteFeatures(style)
        screenshot("sunset-02-after")
    }

    func testNorthUpTwoDAndAnotherStyleKeepTheMapFlatNorthAndStyledThroughATurnAndAfterRecenter() throws {
        launch(origin: beforeCloseTurns, mapStyle: "positron", extra: ["-settings.northUp", "YES", "-settings.threeD", "NO"])
        startRide()
        wait(for: app.staticTexts["sim.style"], labelBeginsWith: "style=positron layers=5/5", timeout: 20)

        let camera = app.staticTexts["sim.camera"]
        let puck = app.staticTexts["sim.puck"]
        let first = try waitForCamera(camera) { $0.mode == "following" && $0.isNorthUp && $0.pitch == 0 }
        XCTAssertEqual(first.zoom, 16.5, accuracy: 0.01)
        let startCourse = try XCTUnwrap(course(puck.label))
        screenshot("northup-01-start")

        var turned = false
        let deadline = Date().addingTimeInterval(80)
        while Date() < deadline {
            if let sample = Camera(camera.label), sample.mode == "following" {
                XCTAssertTrue(sample.isNorthUp, "the map turned away from north: \(camera.label)")
                XCTAssertEqual(sample.pitch, 0, "the map tilted: \(camera.label)")
            }
            if let now = course(puck.label), abs(Self.angle(now - startCourse)) > 45 {
                turned = true
                break
            }
            Thread.sleep(forTimeInterval: 1)
        }
        XCTAssertTrue(turned, "no turn within 80 s; puck: \(puck.label)")
        screenshot("northup-02-after-turn")

        app.buttons["ride.overview"].tap()
        wait(for: camera, labelBeginsWith: "camera=overview", timeout: 10)
        app.buttons["ride.recenter"].tap()
        _ = try waitForCamera(camera) { $0.mode == "following" && $0.isNorthUp && $0.pitch == 0 && abs($0.zoom - 16.5) < 0.01 }
        screenshot("northup-03-recentered")
    }

    func testAutoZoomOpensUpOnTheStraightAndClosesInBeforeTheTurn() throws {
        launch(origin: beforeLaneTurn, extra: ["-settings.autoZoom", "YES"])
        startRide()

        let camera = app.staticTexts["sim.camera"]
        let distance = app.staticTexts["ride.banner.distance"]
        let straight = try waitForCamera(camera) { $0.mode == "following" && abs($0.zoom - 15.75) < 0.01 }
        XCTAssertEqual(straight.pitch, 40, accuracy: 0.5)
        XCTAssertGreaterThan(meters(distance.label) ?? 0, 450, "not on the straight: \(distance.label)")
        screenshot("autozoom-01-straight")

        let close = try waitForCamera(camera, timeout: 100) { $0.mode == "following" && $0.zoom >= 17.25 }
        XCTAssertGreaterThan(close.zoom, straight.zoom)
        XCTAssertLessThan(meters(distance.label) ?? .infinity, 200, "zoomed in far from the turn: \(distance.label)")
        screenshot("autozoom-02-approach")
    }

    private var screenSize: CGSize { app.windows.firstMatch.frame.size }

    private func launch(origin: Point, speedKmh: Int = 36, mapStyle: String = "liberty", extra: [String]) {
        app = XCUIApplication()
        app.launchArguments = [
            "-NaviscootSimulateRide", "YES",
            "-NaviscootSimSpeedKmh", "\(speedKmh)",
            "-NaviscootSimOrigin", "\(origin.lat),\(origin.lon)",
            "-NaviscootDiscardActiveRide", "YES",
            "-settings.language", "en",
            "-settings.verifiedOnlyByDefault", "NO",
            "-settings.avoidFerries", "NO",
            "-settings.avoidUnpaved", "NO",
            "-settings.avoidMainRoads", "NO",
            "-settings.mapStyle", mapStyle,
            "-settings.darkMapAtNight", "YES",
            "-settings.northUp", "NO",
            "-settings.threeD", "YES",
            "-settings.autoZoom", "NO",
        ] + extra
        app.launch()
    }

    private func openPreview() {
        let field = app.textFields["search.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(address)
        let result = app.buttons.matching(NSPredicate(format: "identifier == 'search.result' AND label CONTAINS %@", "Woudenbergseweg 42,")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 15))
        result.tap()
        XCTAssertTrue(app.buttons["preview.start"].waitForExistence(timeout: 40))
    }

    private func startRide() {
        openPreview()
        app.buttons["preview.start"].tap()
        XCTAssertTrue(app.buttons["ride.end"].waitForExistence(timeout: 10))
    }

    private func waitForRouteFeatures(_ style: XCUIElement) {
        let drawn = expectation(for: NSPredicate { _, _ in
            guard let range = style.label.range(of: "features=[0-9]+", options: .regularExpression) else { return false }
            return (Int(style.label[range].dropFirst("features=".count)) ?? 0) > 0
        }, evaluatedWith: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [drawn], timeout: 20), .completed, "no route features drawn: \(style.label)")
    }

    private func waitForCamera(_ element: XCUIElement, timeout: TimeInterval = 30, until condition: @escaping (Camera) -> Bool) throws -> Camera {
        let match = expectation(for: NSPredicate { _, _ in Camera(element.label).map(condition) ?? false }, evaluatedWith: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [match], timeout: timeout), .completed, "camera never matched; last: \(element.label)")
        return try XCTUnwrap(Camera(element.label))
    }

    private func course(_ label: String) -> Double? {
        guard let range = label.range(of: "course=-?[0-9]+", options: .regularExpression) else { return nil }
        return Double(label[range].dropFirst("course=".count))
    }

    private func meters(_ label: String) -> Double? {
        let parts = label.split(separator: " ")
        guard parts.count == 2, let value = Double(parts[0]) else { return nil }
        return parts[1] == "km" ? value * 1000 : value
    }

    private static func angle(_ degrees: Double) -> Double {
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value > 180 { value -= 360 }
        if value <= -180 { value += 360 }
        return value
    }

    private func assertDark(_ point: CGPoint, _ what: String) {
        let value = luminance(at: point)
        XCTAssertLessThan(value, 0.25, "\(what) is not dark at \(point): luminance \(value)")
    }

    private func assertLight(_ point: CGPoint, _ what: String) {
        let value = luminance(at: point)
        XCTAssertGreaterThan(value, 0.85, "\(what) is not light at \(point): luminance \(value)")
    }

    private func luminance(at point: CGPoint) -> Double {
        let shot = XCUIScreen.main.screenshot()
        guard let image = shot.image.cgImage else { return -1 }
        let scale = CGFloat(image.width) / shot.image.size.width
        let x = Int(point.x * scale), y = Int(point.y * scale)
        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn = pixel.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
            return true
        }
        guard drawn else { return -1 }
        return (0.2126 * Double(pixel[0]) + 0.7152 * Double(pixel[1]) + 0.0722 * Double(pixel[2])) / 255
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
