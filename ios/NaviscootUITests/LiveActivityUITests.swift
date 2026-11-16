import CoreLocation
import XCTest

final class LiveActivityUITests: XCTestCase {
    private typealias Point = (lat: Double, lon: Double)

    private struct Stats {
        let pushes: Int
        let backgroundPushes: Int
        let backgroundSpoken: Int
        let remainingM: Int
    }

    private let domplein: Point = (52.0907, 5.1214)
    private let amersfoort = (query: "Lieve Vrouwestraat 33 Amersfoort", label: "Lieve Vrouwestraat 33,")
    private let biltstraat = (query: "Biltstraat 100 Utrecht", label: "Biltstraat 100,")
    private let speedKmh = 60.0
    private let backgroundS: TimeInterval = 180
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard ProcessInfo.processInfo.environment["NAVISCOOT_API_KEY"] != nil else {
            throw XCTSkip("set TEST_RUNNER_NAVISCOOT_API_KEY to run the Live Activity proof against the local API")
        }
    }

    func testARideInTheBackgroundKeepsGuidingAndUpdatingItsLiveActivity() throws {
        launch()
        planAndStart(query: amersfoort.query, label: amersfoort.label)
        let activity = app.staticTexts["sim.activity"]
        wait(for: activity, labelContains: "activity=active system=active live=1", timeout: 15)
        wait(for: app.staticTexts["sim.spoken"], valueContains: "en-GB|", timeout: 30)
        let before = try stats(activity)
        let shownBefore = activity.value as? String ?? ""
        XCTAssertTrue(shownBefore.contains("|Arrival|"), shownBefore)

        XCUIDevice.shared.press(.home)
        let sent = Date()
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10), "the ride did not go to the background: \(app.state.rawValue)")
        let island = liveActivity()
        XCTAssertTrue(island.waitForExistence(timeout: 10), "the Dynamic Island shows no activity")
        Thread.sleep(forTimeInterval: 3)
        let islandBefore = activitySummary()
        XCTAssertTrue(islandBefore.hasSuffix(" m") || islandBefore.hasSuffix(" km"), islandBefore)
        screenshot("activity-01-home-screen-island")
        var islandLabels: Set<String> = [islandBefore]
        while Date().timeIntervalSince(sent) < backgroundS {
            Thread.sleep(forTimeInterval: 15)
            XCTAssertEqual(app.state, .runningBackground, "iOS suspended the ride after \(Int(Date().timeIntervalSince(sent))) s")
            islandLabels.insert(activitySummary())
        }
        XCTAssertGreaterThanOrEqual(islandLabels.count, 4, "the Dynamic Island barely changed: \(islandLabels)")
        screenshot("activity-02-home-screen-later")
        let elapsed = Date().timeIntervalSince(sent)

        app.activate()
        XCTAssertTrue(activity.waitForExistence(timeout: 10))
        let after = try stats(activity)
        let riddenM = Double(before.remainingM - after.remainingM)
        XCTAssertGreaterThan(riddenM, 0.7 * speedKmh / 3.6 * elapsed, "the ride stood still in the background: \(before) → \(after)")
        XCTAssertGreaterThanOrEqual(after.backgroundSpoken, 1, "no instruction was spoken in the background: \(activity.label)")
        XCTAssertGreaterThanOrEqual(after.backgroundPushes, Int(elapsed / 10), "the activity barely updated in the background: \(activity.label)")
        XCTAssertNotEqual(activity.value as? String, shownBefore)
        screenshot("activity-03-back-in-the-app")

        endThroughTheAlert()
    }

    func testArrivalLeavesTheArrivedStateAndEndRemovesTheActivity() throws {
        launch()
        planAndStart(query: biltstraat.query, label: biltstraat.label)
        let activity = app.staticTexts["sim.activity"]
        wait(for: activity, labelContains: "activity=active system=active live=1", timeout: 15)

        let street = app.staticTexts["ride.banner.street"]
        let arrived = expectation(for: NSPredicate(format: "label == 'You have arrived'"), evaluatedWith: street)
        XCTAssertEqual(XCTWaiter.wait(for: [arrived], timeout: 240), .completed, "the ride did not arrive")
        wait(for: activity, labelContains: "activity=ended system=ended", timeout: 10)
        XCTAssertTrue((activity.value as? String ?? "").hasPrefix("flag.checkered||You have arrived|Arrival|"), activity.value as? String ?? "")
        XCTAssertTrue((activity.value as? String ?? "").hasSuffix("|arrived"), activity.value as? String ?? "")
        try lockAndWake()
        XCTAssertTrue(liveActivity().waitForExistence(timeout: 10), "the arrived activity is not on the lock screen")
        acceptLiveActivities()
        Thread.sleep(forTimeInterval: 2)
        XCTAssertTrue(activitySummary().contains("You have arrived"), activitySummary())
        screenshot("activity-04-arrived-lock-screen")
        unlock()

        XCTAssertTrue(app.buttons["ride.end"].waitForExistence(timeout: 10))
        app.buttons["ride.end"].tap()
        XCTAssertTrue(app.textFields["search.field"].waitForExistence(timeout: 10))
        try lockAndWake()
        XCTAssertTrue(liveActivity().waitForNonExistence(timeout: 10), "End left the arrived activity on the lock screen")
        unlock()
    }

    func testEndingARideRemovesItsActivity() throws {
        launch()
        planAndStart(query: amersfoort.query, label: amersfoort.label)
        wait(for: app.staticTexts["sim.activity"], labelContains: "activity=active system=active live=1", timeout: 15)
        endThroughTheAlert()
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(liveActivity().waitForNonExistence(timeout: 10), "End left the activity up")
    }

    func testAKilledRidesActivityIsReplacedOnResumeAndEndedWhenTheOfferIsDeclined() throws {
        launch()
        planAndStart(query: amersfoort.query, label: amersfoort.label)
        wait(for: app.staticTexts["sim.activity"], labelContains: "activity=active system=active live=1", timeout: 15)

        app.terminate()
        XCTAssertTrue(liveActivity().waitForExistence(timeout: 10), "a killed ride's activity is expected to stay up until the app ends it")
        screenshot("activity-05-killed-leftover")
        launch(discardRide: false)
        let offer = app.alerts["Resume your ride?"]
        XCTAssertTrue(offer.waitForExistence(timeout: 10), "the killed ride was not offered")
        offer.buttons["Resume"].tap()
        XCTAssertTrue(app.buttons["ride.end"].waitForExistence(timeout: 60), "the resumed ride did not start")
        wait(for: app.staticTexts["sim.activity"], labelContains: "activity=active system=active live=1", timeout: 15)

        app.terminate()
        launch(discardRide: false)
        XCTAssertTrue(offer.waitForExistence(timeout: 10), "the resumed ride was not offered again")
        offer.buttons["End ride"].tap()
        XCTAssertTrue(offer.waitForNonExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(liveActivity().waitForNonExistence(timeout: 10), "declining the resume offer left the old activity up")
        screenshot("activity-06-declined-gone")
    }

    func testTheLockScreenShowsTheRide() throws {
        launch()
        planAndStart(query: amersfoort.query, label: amersfoort.label)
        wait(for: app.staticTexts["sim.activity"], labelContains: "activity=active system=active live=1", timeout: 15)
        wait(for: app.staticTexts["sim.spoken"], valueContains: "en-GB|", timeout: 30)

        try lockAndWake()
        screenshot("activity-07-lock-screen")
        dumpSpringboard("activity-07-lock-screen")
        let card = liveActivity()
        XCTAssertTrue(card.waitForExistence(timeout: 10), "the lock screen shows no activity")
        acceptLiveActivities()
        let texts = card.staticTexts.allElementsBoundByIndex.map(\.label)
        XCTAssertTrue(texts.contains("Arrival"), "\(texts)")
        XCTAssertTrue(texts.contains { $0.hasSuffix(" km") }, "\(texts)")

        unlock()
        if app.buttons["ride.end"].waitForExistence(timeout: 10) {
            endThroughTheAlert()
        }
    }

    func testARideWithoutSimulationIsGuidedByTheDevicesLocation() throws {
        let start = CLLocationCoordinate2D(latitude: domplein.lat, longitude: domplein.lon)
        XCUIDevice.shared.location = XCUILocation(location: CLLocation(latitude: start.latitude, longitude: start.longitude))
        let path = try Self.walk(Self.decodePolyline6(fetchGeometry(to: (52.09545846, 5.13137094))), stepM: 15)
        app = XCUIApplication()
        app.launchArguments = [
            "-NaviscootSimulateRide", "NO",
            "-NaviscootDiscardActiveRide", "YES",
            "-settings.language", "en",
            "-settings.verifiedOnlyByDefault", "NO",
            "-settings.avoidFerries", "NO",
            "-settings.avoidUnpaved", "NO",
            "-settings.avoidMainRoads", "NO",
        ]
        app.launch()
        XCTAssertTrue(app.textFields["search.field"].waitForExistence(timeout: 10))
        planAndStart(query: biltstraat.query, label: biltstraat.label)
        XCTAssertFalse(app.staticTexts["sim.activity"].exists, "this ride must not be simulated")
        let remaining = app.descendants(matching: .any)["ride.remaining"]
        XCTAssertTrue(remaining.waitForExistence(timeout: 10))
        let distance = app.staticTexts["ride.banner.distance"]
        XCTAssertTrue(distance.waitForExistence(timeout: 20), "no banner from the device's location")
        let before = try XCTUnwrap(Self.metres(in: remaining.label), remaining.label)

        let walked = Array(path.prefix(Int(Double(path.count) * 0.6)))
        for (index, point) in walked.enumerated() {
            let next = walked[min(index + 1, walked.count - 1)]
            let course = Self.bearing(from: point, to: next)
            XCUIDevice.shared.location = XCUILocation(location: CLLocation(
                coordinate: point, altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
                course: course, speed: 15, timestamp: Date()
            ))
            Thread.sleep(forTimeInterval: 1)
        }
        Thread.sleep(forTimeInterval: 2)
        let after = try XCTUnwrap(Self.metres(in: remaining.label), remaining.label)
        let walkedM = Double(walked.count - 1) * 15
        XCTAssertLessThan(after, before - 0.6 * walkedM, "guidance did not follow the device: \(before) m → \(after) m after \(walkedM) m")
        XCTAssertFalse(app.descendants(matching: .any)["ride.rerouteFailed"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["ride.locationTrouble"].exists)
        screenshot("activity-08-device-location-ride")
        endThroughTheAlert()
        XCUIDevice.shared.location = XCUILocation(location: CLLocation(latitude: 52.2977646, longitude: 5.445363))
    }

    private func fetchGeometry(to destination: Point) throws -> String {
        let base = ProcessInfo.processInfo.environment["NAVISCOOT_API_BASE_URL"] ?? "http://127.0.0.1:8080"
        var request = URLRequest(url: URL(string: "\(base)/route")!)
        request.httpMethod = "POST"
        request.setValue(ProcessInfo.processInfo.environment["NAVISCOOT_API_KEY"], forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "origin": ["lat": domplein.lat, "lon": domplein.lon],
            "destination": ["lat": destination.lat, "lon": destination.lon],
            "verified_only": false,
            "format": "osrm",
            "language": "en-GB",
        ] as [String: Any])
        var data: Data?
        let done = expectation(description: "route")
        URLSession.shared.dataTask(with: request) { body, _, _ in
            data = body
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 90)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(data)) as? [String: Any])
        let routes = try XCTUnwrap(json["routes"] as? [[String: Any]], "\(json)")
        return try XCTUnwrap(routes.first?["geometry"] as? String)
    }

    private static func decodePolyline6(_ encoded: String) -> [CLLocationCoordinate2D] {
        var points: [CLLocationCoordinate2D] = []
        var lat = 0, lon = 0
        var bytes = encoded.utf8.makeIterator()
        func next() -> Int? {
            var result = 0, shift = 0
            while let byte = bytes.next() {
                let chunk = Int(byte) - 63
                result |= (chunk & 0x1F) << shift
                shift += 5
                if chunk < 0x20 { return (result & 1) != 0 ? ~(result >> 1) : result >> 1 }
            }
            return nil
        }
        while let dLat = next(), let dLon = next() {
            lat += dLat
            lon += dLon
            points.append(CLLocationCoordinate2D(latitude: Double(lat) / 1e6, longitude: Double(lon) / 1e6))
        }
        return points
    }

    private static func walk(_ points: [CLLocationCoordinate2D], stepM: Double) -> [CLLocationCoordinate2D] {
        guard var previous = points.first else { return [] }
        var result = [previous]
        var carried = 0.0
        for point in points.dropFirst() {
            let length = CLLocation(latitude: previous.latitude, longitude: previous.longitude)
                .distance(from: CLLocation(latitude: point.latitude, longitude: point.longitude))
            var along = stepM - carried
            while along <= length {
                let t = along / length
                result.append(CLLocationCoordinate2D(
                    latitude: previous.latitude + (point.latitude - previous.latitude) * t,
                    longitude: previous.longitude + (point.longitude - previous.longitude) * t
                ))
                along += stepM
            }
            carried = length - (along - stepM)
            previous = point
        }
        return result
    }

    private static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> CLLocationDirection {
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    private static func metres(in label: String) -> Double? {
        if let range = label.range(of: #"[0-9]+(\.[0-9])? km"#, options: .regularExpression) {
            return Double(label[range].dropLast(3)).map { $0 * 1000 }
        }
        if let range = label.range(of: #"[0-9]+ m"#, options: .regularExpression) {
            return Double(label[range].dropLast(2))
        }
        return nil
    }

    private func launch(discardRide: Bool = true) {
        app = XCUIApplication()
        app.launchArguments = [
            "-NaviscootSimulateRide", "YES",
            "-NaviscootSimSpeedKmh", "\(Int(speedKmh))",
            "-NaviscootSimOrigin", "\(domplein.lat),\(domplein.lon)",
            "-settings.language", "en",
            "-settings.verifiedOnlyByDefault", "NO",
            "-settings.avoidFerries", "NO",
            "-settings.avoidUnpaved", "NO",
            "-settings.avoidMainRoads", "NO",
        ]
        if discardRide {
            app.launchArguments += ["-NaviscootDiscardActiveRide", "YES"]
        }
        app.launch()
        XCTAssertTrue(app.textFields["search.field"].waitForExistence(timeout: 10))
    }

    private func planAndStart(query: String, label: String) {
        let field = app.textFields["search.field"]
        field.tap()
        field.typeText(query)
        let result = app.buttons.matching(NSPredicate(format: "identifier == 'search.result' AND label CONTAINS %@", label)).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 15), "no result for \(query)")
        result.tap()
        let start = app.buttons["preview.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 60), "Start is not offered")
        start.tap()
        XCTAssertTrue(app.buttons["ride.end"].waitForExistence(timeout: 10))
    }

    private func endThroughTheAlert() {
        app.buttons["ride.end"].tap()
        let confirm = app.alerts.buttons.matching(identifier: "End ride").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "End did not ask first")
        confirm.tap()
        XCTAssertTrue(app.textFields["search.field"].waitForExistence(timeout: 10))
    }

    private func stats(_ element: XCUIElement) throws -> Stats {
        var values: [String: Int] = [:]
        for pair in element.label.split(separator: " ") {
            let parts = pair.split(separator: "=")
            if parts.count == 2, let number = Int(parts[1]) { values[String(parts[0])] = number }
        }
        return try Stats(
            pushes: XCTUnwrap(values["pushes"], element.label),
            backgroundPushes: XCTUnwrap(values["bg"], element.label),
            backgroundSpoken: XCTUnwrap(values["spokenBg"], element.label),
            remainingM: XCTUnwrap(values["remainingM"], element.label)
        )
    }

    private func wait(for element: XCUIElement, labelContains text: String, timeout: TimeInterval) {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let result = XCTWaiter.wait(for: [expectation(for: predicate, evaluatedWith: element)], timeout: timeout)
        XCTAssertEqual(result, .completed, "\(element.identifier) never contained \(text): \(element.exists ? element.label : "missing")")
    }

    private func wait(for element: XCUIElement, valueContains text: String, timeout: TimeInterval) {
        let predicate = NSPredicate(format: "value CONTAINS %@", text)
        let result = XCTWaiter.wait(for: [expectation(for: predicate, evaluatedWith: element)], timeout: timeout)
        XCTAssertEqual(result, .completed, "\(element.identifier) never contained \(text)")
    }

    private func liveActivity() -> XCUIElement {
        XCUIApplication(bundleIdentifier: "com.apple.springboard").descendants(matching: .any)
            .matching(NSPredicate(format: "identifier CONTAINS 'WidgetRenderer-Activities' OR identifier == 'activity-content-view'")).firstMatch
    }

    private func lockAndWake() throws {
        let lock = NSSelectorFromString("pressLockButton")
        guard XCUIDevice.shared.responds(to: lock) else { throw XCTSkip("this XCUIDevice cannot lock the simulator") }
        XCUIDevice.shared.perform(lock)
        Thread.sleep(forTimeInterval: 3)
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 3)
    }

    private func unlock() {
        XCUIDevice.shared.press(.home)
        XCUIApplication(bundleIdentifier: "com.apple.springboard").swipeUp()
        app.activate()
    }

    private func acceptLiveActivities() {
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow"]
        if allow.exists { allow.tap() }
    }

    private func activitySummary() -> String {
        let card = liveActivity()
        return (card.images.allElementsBoundByIndex.map(\.label) + card.staticTexts.allElementsBoundByIndex.map(\.label)).joined(separator: ", ")
    }

    private func dumpSpringboard(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] else { return }
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        try? springboard.debugDescription.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).txt"), atomically: true, encoding: .utf8)
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
