import XCTest

final class VoiceUITests: XCTestCase {
    typealias Point = (lat: Double, lon: Double)

    private let caseOrigin: Point = (52.2977646, 5.445363)
    private let destination: Point = (52.04779119, 5.40516261)
    private let address = "Woudenbergseweg 42 Maarsbergen"
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        _ = try apiKey()
    }

    func testAlertsOnlySpeaksTheUnverifiedWarningButNoTurnInstruction() throws {
        let start = try point(before: { $0.stretches.first { $0["class"] as? String == "unverified" }?["start_shape_index"] as? Int }, meters: 1400)
        let firstInstruction = try XCTUnwrap(fetchRoute(from: start).firstAnnouncement)

        launch(origin: start, speedKmh: 90, extra: ["-settings.guidanceMode", "alerts"])
        startRide()

        let speech = app.staticTexts["sim.speech"]
        wait(for: speech, valueContains: "instruction|suppressed|\(firstInstruction)", timeout: 20)
        XCTAssertTrue(speech.label.hasPrefix("mode=alerts suppressed="), speech.label)

        let spoken = app.staticTexts["sim.spoken"]
        wait(for: spoken, valueContains: "en-GB|Caution: in ", timeout: 60)
        wait(for: spoken, valueContains: "an unverified cycle path of 500 metres.", timeout: 5)
        screenshot("voice-01-alerts-only-warning")

        wait(for: app.descendants(matching: .any)["ride.warning"], labelBeginsWith: "On unverified path, ", timeout: 90)
        let lines = spokenLines()
        XCTAssertEqual(lines.count, 1, lines.joined(separator: "\n"))
        let decisions = (speech.value as? String ?? "").split(separator: "\n").map(String.init)
        XCTAssertGreaterThanOrEqual(decisions.filter { $0.hasPrefix("instruction|suppressed|") }.count, 2, decisions.joined(separator: "\n"))
        XCTAssertFalse(decisions.contains { $0.hasPrefix("instruction|spoken|") }, decisions.joined(separator: "\n"))
        XCTAssertTrue(speech.label.contains(" last=warning "), speech.label)
        screenshot("voice-02-alerts-only-inside")
        endRide()
    }

    func testVoiceRateAndVolumePickedInSettingsShapeTheNextSpokenLineAndPersist() throws {
        launch(origin: caseOrigin, speedKmh: 36, extra: ["-settings.voice.en", "", "-settings.speechRate", "100", "-settings.speechVolume", "100"])
        let field = app.textFields["search.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        app.buttons["search.settings"].tap()
        XCTAssertTrue(app.buttons["settings.done"].waitForExistence(timeout: 5))

        let rate = app.steppers["settings.speechRate"]
        scroll(to: app.steppers["settings.speechVolume"])
        XCTAssertEqual(rate.label, "Speaking rate 100%")
        rate.buttons[rate.identifier + "-Increment"].tap()
        rate.buttons[rate.identifier + "-Increment"].tap()
        let volume = app.steppers["settings.speechVolume"]
        for _ in 0 ..< 3 { volume.buttons[volume.identifier + "-Decrement"].tap() }
        XCTAssertEqual(rate.label, "Speaking rate 120%")
        XCTAssertEqual(volume.label, "Volume 70%")

        let chosen = try pickOtherVoice()
        addTeardownBlock { [weak self] in self?.restoreDefaultVoiceIfStillChosen() }
        screenshot("voice-03-settings")
        app.buttons["settings.done"].tap()

        startRide()
        let speech = app.staticTexts["sim.speech"]
        let expected = "rate=0.60 volume=0.70 voice=\(chosen)"
        wait(for: speech, labelContains: expected, timeout: 30)
        XCTAssertTrue(speech.label.contains(" last=instruction "), speech.label)
        XCTAssertFalse(spokenLines().isEmpty)
        screenshot("voice-04-ride-spoken-line")
        endRide()

        app.terminate()
        launch(origin: caseOrigin, speedKmh: 36)
        XCTAssertTrue(app.textFields["search.field"].waitForExistence(timeout: 10))
        app.buttons["search.settings"].tap()
        XCTAssertTrue(app.buttons["settings.done"].waitForExistence(timeout: 5))
        let relaunchedRate = app.steppers["settings.speechRate"]
        let relaunchedVolume = app.steppers["settings.speechVolume"]
        scroll(to: relaunchedVolume)
        XCTAssertEqual(relaunchedRate.label, "Speaking rate 120%")
        XCTAssertEqual(relaunchedVolume.label, "Volume 70%")
        XCTAssertTrue(shown(app.buttons["settings.voice"]).contains(chosenName), shown(app.buttons["settings.voice"]))

        for _ in 0 ..< 2 { relaunchedRate.buttons[relaunchedRate.identifier + "-Decrement"].tap() }
        for _ in 0 ..< 3 { relaunchedVolume.buttons[relaunchedVolume.identifier + "-Increment"].tap() }
        app.buttons["settings.voice"].tap()
        let defaultRow = app.buttons["settings.voice.default"]
        XCTAssertTrue(defaultRow.waitForExistence(timeout: 5))
        defaultRow.tap()
        voiceRestored = true
        XCTAssertTrue(app.buttons["settings.done"].waitForExistence(timeout: 5))
        XCTAssertEqual(relaunchedRate.label, "Speaking rate 100%")
        XCTAssertEqual(relaunchedVolume.label, "Volume 100%")
        app.buttons["settings.done"].tap()
    }

    func testOverTheLimitTheSpeedTurnsRedAndOneAlertSounds() throws {
        let start = try originBeforeLongThirtyZone()
        launch(origin: start, speedKmh: 37, extra: ["-settings.speedingAlert", "YES", "-settings.speedingTolerance", "5"])
        startRide()

        let speed = app.descendants(matching: .any)["ride.speed"]
        let limit = app.descendants(matching: .any)["ride.limit"]
        wait(for: limit, labelEquals: "Speed limit 40", timeout: 20)
        XCTAssertEqual(speed.value as? String ?? "", "", "over the limit at 37 in a 40 zone")

        wait(for: limit, labelEquals: "Speed limit 30", timeout: 60)
        wait(for: speed, valueEquals: "Over the speed limit", timeout: 5)
        let spoken = app.staticTexts["sim.spoken"]
        wait(for: spoken, valueContains: "en-GB|Slow down: the speed limit is 30.", timeout: 5)
        assertRed(speed)
        screenshot("speeding-01-alert")

        sleep(20)
        XCTAssertEqual(limit.label, "Speed limit 30")
        XCTAssertEqual(speed.value as? String, "Over the speed limit")
        XCTAssertEqual(spokenLines().filter { $0.contains("Slow down") }.count, 1, spokenLines().joined(separator: "\n"))
        XCTAssertTrue(app.staticTexts["sim.speech"].label.contains("speeding=yes episodes=1"), app.staticTexts["sim.speech"].label)
        assertRed(speed)
        screenshot("speeding-02-still-over")
        endRide()
    }

    func testAtThirtyFourInAThirtyZoneNothingChanges() throws {
        let start = try originBeforeLongThirtyZone()
        launch(origin: start, speedKmh: 34, extra: ["-settings.speedingAlert", "YES", "-settings.speedingTolerance", "5"])
        startRide()

        let speed = app.descendants(matching: .any)["ride.speed"]
        let limit = app.descendants(matching: .any)["ride.limit"]
        wait(for: limit, labelEquals: "Speed limit 30", timeout: 60)
        sleep(15)
        XCTAssertEqual(limit.label, "Speed limit 30")
        XCTAssertEqual(speed.value as? String ?? "", "")
        XCTAssertFalse(spokenLines().contains { $0.contains("Slow down") }, spokenLines().joined(separator: "\n"))
        XCTAssertTrue(app.staticTexts["sim.speech"].label.contains("speeding=no episodes=0"), app.staticTexts["sim.speech"].label)
        assertNotRed(speed)
        screenshot("speeding-03-under-tolerance")
        endRide()
    }

    private var chosenName = ""
    private var voiceRestored = false

    private func restoreDefaultVoiceIfStillChosen() {
        guard !voiceRestored else { return }
        launch(origin: caseOrigin, speedKmh: 36)
        guard app.buttons["search.settings"].waitForExistence(timeout: 10) else { return }
        app.buttons["search.settings"].tap()
        let picker = app.buttons["settings.voice"]
        for _ in 0 ..< 10 where !(picker.exists && picker.isHittable) { app.swipeUp() }
        picker.tap()
        let defaultRow = app.buttons["settings.voice.default"]
        if defaultRow.waitForExistence(timeout: 5) { defaultRow.tap() }
    }

    private func pickOtherVoice() throws -> String {
        let picker = app.buttons["settings.voice"]
        scroll(to: picker)
        picker.tap()
        let defaultRow = app.buttons["settings.voice.default"]
        XCTAssertTrue(defaultRow.waitForExistence(timeout: 5))
        let defaultName = defaultRow.label.replacingOccurrences(of: "Default (", with: "").replacingOccurrences(of: ")", with: "")
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'settings.voice.com.'")).allElementsBoundByIndex
        let candidates = rows.filter { !$0.label.hasPrefix(defaultName + " ") }
        let row = try XCTUnwrap(
            candidates.first { $0.identifier.contains(".en-GB.") } ?? candidates.first,
            "no English voice other than \(defaultName): \(rows.map(\.identifier))"
        )
        let identifier = String(row.identifier.dropFirst("settings.voice.".count))
        chosenName = String(row.label.split(separator: "·").first ?? "").trimmingCharacters(in: .whitespaces)
        for _ in 0 ..< 8 where !row.isHittable { app.swipeUp() }
        row.tap()
        XCTAssertTrue(app.buttons["settings.done"].waitForExistence(timeout: 5))
        XCTAssertTrue(shown(picker).contains(chosenName), shown(picker))
        return identifier
    }

    private func shown(_ element: XCUIElement) -> String {
        "\(element.label) \(element.value as? String ?? "")"
    }

    private func scroll(to element: XCUIElement) {
        for _ in 0 ..< 10 where !(element.exists && element.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable, "\(element) not reachable")
    }

    private func originBeforeLongThirtyZone() throws -> Point {
        let route = try fetchRoute(from: caseOrigin)
        let run = try XCTUnwrap(route.limits.first { $0.kmh == 30 && route.length(from: $0.start, to: $0.end) > 1000 }, "no long 30 zone")
        let start = route.point(before: run.start, meters: 200)
        let fromStart = try fetchRoute(from: start)
        let ahead = fromStart.limits.first { $0.kmh == 30 }
        XCTAssertNotNil(ahead, "no 30 zone from \(start)")
        if let ahead {
            XCTAssertLessThan(fromStart.length(from: 0, to: ahead.start), 400, "the 30 zone moved away from \(start)")
            XCTAssertGreaterThan(fromStart.length(from: ahead.start, to: ahead.end), 1000)
            XCTAssertTrue(fromStart.limits.prefix { $0.start < ahead.start }.allSatisfy { $0.kmh >= 40 }, "\(fromStart.limits.prefix(3))")
        }
        return start
    }

    private func point(before index: (APIRoute) -> Int?, meters: Double) throws -> Point {
        let route = try fetchRoute(from: caseOrigin)
        return try route.point(before: XCTUnwrap(index(route)), meters: meters)
    }

    private func launch(origin: Point, speedKmh: Int, extra: [String] = []) {
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
            "-settings.autoZoom", "NO",
        ] + extra
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

    private func endRide() {
        app.buttons["ride.end"].tap()
        let button = app.alerts.buttons["End ride"]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "no end confirmation")
        button.tap()
        XCTAssertTrue(app.textFields["search.field"].waitForExistence(timeout: 10))
    }

    private func spokenLines() -> [String] {
        let value = app.staticTexts["sim.spoken"].value as? String ?? ""
        return value.split(separator: "\n").map(String.init)
    }

    private func assertRed(_ element: XCUIElement) {
        let (r, g, b) = color(at: CGPoint(x: element.frame.midX, y: element.frame.minY + 12))
        XCTAssertTrue(r > 0.55 && g < 0.35 && b < 0.35, "speed readout is not red: \(r), \(g), \(b)")
    }

    private func assertNotRed(_ element: XCUIElement) {
        let (r, g, b) = color(at: CGPoint(x: element.frame.midX, y: element.frame.minY + 12))
        XCTAssertFalse(r > 0.55 && g < 0.35 && b < 0.35, "speed readout is red: \(r), \(g), \(b)")
    }

    private func color(at point: CGPoint) -> (Double, Double, Double) {
        let shot = XCUIScreen.main.screenshot()
        guard let image = shot.image.cgImage else { return (-1, -1, -1) }
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
        guard drawn else { return (-1, -1, -1) }
        return (Double(pixel[0]) / 255, Double(pixel[1]) / 255, Double(pixel[2]) / 255)
    }

    private func wait(for element: XCUIElement, valueContains text: String, timeout: TimeInterval) {
        let match = expectation(for: NSPredicate(format: "value CONTAINS %@", text), evaluatedWith: element)
        XCTAssertEqual(XCTWaiter.wait(for: [match], timeout: timeout), .completed, "'\(text)' not in \(element.value ?? "nil")")
    }

    private func wait(for element: XCUIElement, valueEquals text: String, timeout: TimeInterval) {
        let match = expectation(for: NSPredicate(format: "value == %@", text), evaluatedWith: element)
        XCTAssertEqual(XCTWaiter.wait(for: [match], timeout: timeout), .completed, "expected value '\(text)', shown '\(element.value ?? "nil")'")
    }

    private func wait(for element: XCUIElement, labelContains text: String, timeout: TimeInterval) {
        let match = expectation(for: NSPredicate(format: "label CONTAINS %@", text), evaluatedWith: element)
        XCTAssertEqual(XCTWaiter.wait(for: [match], timeout: timeout), .completed, "'\(text)' not in '\(element.label)'")
    }

    private func wait(for element: XCUIElement, labelEquals text: String, timeout: TimeInterval) {
        let match = expectation(for: NSPredicate(format: "label == %@", text), evaluatedWith: element)
        XCTAssertEqual(XCTWaiter.wait(for: [match], timeout: timeout), .completed, "expected '\(text)', shown '\(element.label)'")
    }

    private func wait(for element: XCUIElement, labelBeginsWith text: String, timeout: TimeInterval) {
        let match = expectation(for: NSPredicate(format: "label BEGINSWITH %@", text), evaluatedWith: element)
        XCTAssertEqual(XCTWaiter.wait(for: [match], timeout: timeout), .completed, "expected '\(text)…', shown '\(element.label)'")
    }

    private struct LimitRun {
        let kmh: Int
        let start: Int
        let end: Int
    }

    private struct APIRoute {
        let geometry: [Point]
        let stretches: [[String: Any]]
        let limits: [LimitRun]
        let firstAnnouncement: String?

        func length(from start: Int, to end: Int) -> Double {
            guard start < end else { return 0 }
            return (start ..< min(end, geometry.count - 1)).reduce(0) { $0 + VoiceUITests.distance(geometry[$1], geometry[$1 + 1]) }
        }

        func point(before index: Int, meters: Double) -> Point {
            var index = index
            var travelled = 0.0
            while index > 0, travelled < meters {
                travelled += VoiceUITests.distance(geometry[index - 1], geometry[index])
                index -= 1
            }
            return geometry[index]
        }
    }

    private func apiKey() throws -> String {
        guard let key = ProcessInfo.processInfo.environment["NAVISCOOT_API_KEY"] else {
            throw XCTSkip("set TEST_RUNNER_NAVISCOOT_API_KEY to run the voice proof against the local API")
        }
        return key
    }

    private var baseURL: String {
        ProcessInfo.processInfo.environment["NAVISCOOT_API_BASE_URL"] ?? "http://127.0.0.1:8080"
    }

    private func fetchRoute(from origin: Point) throws -> APIRoute {
        var request = URLRequest(url: URL(string: "\(baseURL)/route")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(try apiKey(), forHTTPHeaderField: "x-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "origin": ["lat": origin.lat, "lon": origin.lon],
            "destination": ["lat": destination.lat, "lon": destination.lon],
            "verified_only": false,
            "format": "osrm",
            "language": "en-GB",
        ])
        var body: Data?
        let done = expectation(description: "api")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            body = data
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 60)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(body)) as? [String: Any])
        let naviscoot = try XCTUnwrap(json["naviscoot"] as? [String: Any])
        let routes = try XCTUnwrap(json["routes"] as? [[String: Any]])
        let geometry = try XCTUnwrap(routes.first?["geometry"] as? String)
        let steps = (routes.first?["legs"] as? [[String: Any]])?.first?["steps"] as? [[String: Any]]
        let voice = steps?.first?["voiceInstructions"] as? [[String: Any]]
        let limits = (naviscoot["speed_limits"] as? [[String: Any]] ?? []).compactMap { run -> LimitRun? in
            guard let kmh = run["kmh"] as? Int, let start = run["start_shape_index"] as? Int, let end = run["end_shape_index"] as? Int else { return nil }
            return LimitRun(kmh: kmh, start: start, end: end)
        }
        return try APIRoute(
            geometry: Self.decodePolyline6(geometry),
            stretches: XCTUnwrap(naviscoot["stretches"] as? [[String: Any]]),
            limits: limits,
            firstAnnouncement: voice?.first?["announcement"] as? String
        )
    }

    private static func decodePolyline6(_ encoded: String) -> [Point] {
        var points: [Point] = []
        let bytes = Array(encoded.utf8)
        var index = 0
        var lat = 0
        var lon = 0
        func next() -> Int {
            var result = 0
            var shift = 0
            var byte: Int
            repeat {
                byte = Int(bytes[index]) - 63
                index += 1
                result |= (byte & 0x1F) << shift
                shift += 5
            } while byte >= 0x20
            return (result & 1) != 0 ? ~(result >> 1) : result >> 1
        }
        while index < bytes.count {
            lat += next()
            lon += next()
            points.append((Double(lat) / 1e6, Double(lon) / 1e6))
        }
        return points
    }

    static func distance(_ a: Point, _ b: Point) -> Double {
        let dLat = (b.lat - a.lat) * .pi / 180
        let dLon = (b.lon - a.lon) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(a.lat * .pi / 180) * cos(b.lat * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * 6_371_008.8 * asin(min(1, sqrt(h)))
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
