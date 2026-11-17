@testable import Naviscoot
import XCTest

final class AppearanceTests: XCTestCase {
    private let utrecht = Coordinate(lat: 52.0907, lon: 5.1214)

    private func freshDefaults() -> UserDefaults {
        let name = "appearance-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    private func utc(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }

    func testAFreshInstallFollowsTheSystemAndKeepsTodaysRideMap() {
        let settings = AppSettings(defaults: freshDefaults())
        XCTAssertEqual(settings.appearance, .system)
        XCTAssertEqual(settings.mapStyle, .liberty)
        XCTAssertTrue(settings.darkMapAtNight)
        XCTAssertFalse(settings.northUp)
        XCTAssertTrue(settings.threeD)
        XCTAssertFalse(settings.autoZoom)
        XCTAssertEqual(settings.followOptions, RideCamera.FollowOptions(northUp: false, threeD: true, autoZoom: false))
    }

    func testAppearanceAndMapSettingsAreReadBackByANewInstance() {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.appearance = .dark
        settings.mapStyle = .fiord
        settings.darkMapAtNight = false
        settings.northUp = true
        settings.threeD = false
        settings.autoZoom = true

        let reopened = AppSettings(defaults: defaults)
        XCTAssertEqual(reopened.appearance, .dark)
        XCTAssertEqual(reopened.mapStyle, .fiord)
        XCTAssertFalse(reopened.darkMapAtNight)
        XCTAssertTrue(reopened.northUp)
        XCTAssertFalse(reopened.threeD)
        XCTAssertTrue(reopened.autoZoom)
    }

    func testLaunchArgumentStringsAreReadForTheSettingsThatDefaultToOn() {
        let defaults = freshDefaults()
        defaults.set("NO", forKey: AppSettings.Key.darkMapAtNight)
        defaults.set("NO", forKey: AppSettings.Key.threeD)
        let settings = AppSettings(defaults: defaults)
        XCTAssertFalse(settings.darkMapAtNight)
        XCTAssertFalse(settings.threeD)
    }

    func testAppearanceMapsOntoTheWindowStyle() {
        XCTAssertEqual(AppearanceChoice.system.interfaceStyle, .unspecified)
        XCTAssertEqual(AppearanceChoice.light.interfaceStyle, .light)
        XCTAssertEqual(AppearanceChoice.dark.interfaceStyle, .dark)
    }

    func testEveryOfferedStyleIsAnOpenFreeMapStyleWithAtLeastOneLightAndOneDark() {
        XCTAssertEqual(MapStyle.allCases.map(\.rawValue), ["liberty", "bright", "positron", "dark", "fiord"])
        XCTAssertTrue(MapStyle.allCases.contains { !$0.isDark })
        XCTAssertTrue(MapStyle.allCases.contains(where: \.isDark))
        for style in MapStyle.allCases where style != .dark {
            XCTAssertEqual(style.url.absoluteString, "https://tiles.openfreemap.org/styles/\(style.rawValue)")
        }
        XCTAssertTrue(MapStyle.night.isDark)
    }

    func testTheNightStyleIsTheBundledLibertyVariantWithThreeDBuildings() throws {
        XCTAssertTrue(MapStyle.dark.url.isFileURL)
        let style = try JSONSerialization.jsonObject(with: Data(contentsOf: MapStyle.dark.url)) as? [String: Any]
        let layers = try XCTUnwrap(style?["layers"] as? [[String: Any]])
        let ids = layers.compactMap { $0["id"] as? String }
        XCTAssertTrue(ids.contains("building-3d"))
        XCTAssertTrue(ids.contains("road_minor_casing"))
        let sources = try XCTUnwrap(style?["sources"] as? [String: Any])
        XCTAssertNotNil(sources["openmaptiles"])
    }

    func testALightStyleIsUsedByDayInALightApp() {
        for style in MapStyle.allCases where !style.isDark {
            XCTAssertEqual(MapStyle.resolve(choice: style, darkAppearance: false, darkAtNight: true, isNight: false), style)
        }
    }

    func testALightStyleTurnsDarkAtNightOnlyWithTheSettingOn() {
        XCTAssertEqual(MapStyle.resolve(choice: .positron, darkAppearance: false, darkAtNight: true, isNight: true), .dark)
        XCTAssertEqual(MapStyle.resolve(choice: .positron, darkAppearance: false, darkAtNight: false, isNight: true), .positron)
    }

    func testADarkAppTurnsALightStyleDarkByDayToo() {
        XCTAssertEqual(MapStyle.resolve(choice: .liberty, darkAppearance: true, darkAtNight: false, isNight: false), .dark)
        XCTAssertEqual(MapStyle.resolve(choice: .bright, darkAppearance: true, darkAtNight: true, isNight: true), .dark)
    }

    func testAChosenDarkStyleIsAlwaysKept() {
        for darkAppearance in [false, true] {
            for darkAtNight in [false, true] {
                for isNight in [false, true] {
                    XCTAssertEqual(MapStyle.resolve(choice: .fiord, darkAppearance: darkAppearance, darkAtNight: darkAtNight, isNight: isNight), .fiord)
                    XCTAssertEqual(MapStyle.resolve(choice: .dark, darkAppearance: darkAppearance, darkAtNight: darkAtNight, isNight: isNight), .dark)
                }
            }
        }
    }

    func testTheDarkStyleGetsTheDarkPaletteWithAForbiddenCasing() {
        XCTAssertEqual(MapPalette.palette(for: .liberty), .light)
        XCTAssertEqual(MapPalette.palette(for: .fiord), .dark)
        let dark = MapPalette.dark
        let lineColours = [dark.verified, dark.unverified, dark.forbidden, dark.ridden]
        XCTAssertEqual(Set(lineColours.map(\.description)).count, lineColours.count)
        XCTAssertNotEqual(dark.forbiddenCasing, .clear)
    }

    // Reference times from the NOAA algorithm (Python astral 3, Utrecht 52.0907 N 5.1214 E); timeanddate.com gives
    // 08:45 / 16:29 CET for 2026-12-21.
    func testSunriseAndSunsetAtUtrechtMatchTheReferenceWithinThreeMinutes() throws {
        let references: [(day: String, sunrise: String, sunset: String)] = [
            ("2026-03-20T12:00:00Z", "2026-03-20T05:42:38Z", "2026-03-20T17:52:17Z"),
            ("2026-03-29T12:00:00Z", "2026-03-29T05:21:43Z", "2026-03-29T18:07:50Z"),
            ("2026-06-21T12:00:00Z", "2026-06-21T03:19:08Z", "2026-06-21T20:03:31Z"),
            ("2026-09-23T12:00:00Z", "2026-09-23T05:27:18Z", "2026-09-23T17:35:30Z"),
            ("2026-10-25T12:00:00Z", "2026-10-25T06:22:08Z", "2026-10-25T16:24:09Z"),
            ("2026-12-21T12:00:00Z", "2026-12-21T07:46:07Z", "2026-12-21T15:29:01Z"),
        ]
        for reference in references {
            let day = try XCTUnwrap(SolarTimes.day(containing: utc(reference.day), at: utrecht))
            XCTAssertEqual(day.sunrise.timeIntervalSince(utc(reference.sunrise)), 0, accuracy: 180, "sunrise on \(reference.day)")
            XCTAssertEqual(day.sunset.timeIntervalSince(utc(reference.sunset)), 0, accuracy: 180, "sunset on \(reference.day)")
        }
    }

    func testTheSameDayIsFoundFromAnyMomentOfTheUTCDay() throws {
        let morning = try XCTUnwrap(SolarTimes.day(containing: utc("2026-12-21T00:05:00Z"), at: utrecht))
        let evening = try XCTUnwrap(SolarTimes.day(containing: utc("2026-12-21T23:55:00Z"), at: utrecht))
        XCTAssertEqual(morning.sunset.timeIntervalSince(evening.sunset), 0, accuracy: 1)
    }

    func testNightIsBeforeSunriseAndFromSunset() {
        XCTAssertTrue(SolarTimes.isNight(at: utc("2026-11-15T05:00:00Z"), coordinate: utrecht))
        XCTAssertFalse(SolarTimes.isNight(at: utc("2026-11-15T12:00:00Z"), coordinate: utrecht))
        XCTAssertFalse(SolarTimes.isNight(at: utc("2026-11-15T15:40:00Z"), coordinate: utrecht))
        XCTAssertTrue(SolarTimes.isNight(at: utc("2026-11-15T15:55:00Z"), coordinate: utrecht))
        XCTAssertTrue(SolarTimes.isNight(at: utc("2026-11-15T22:00:00Z"), coordinate: utrecht))
        XCTAssertFalse(SolarTimes.isNight(at: utc("2026-06-21T19:50:00Z"), coordinate: utrecht), "a June evening at 21:50 CEST is still light")
    }

    func testTheSimulatedClockStartsAtTheGivenTimeAndRunsOn() {
        let defaults = freshDefaults()
        let launch = Date()
        defaults.set("2026-11-15T15:47:00Z", forKey: AppClock.simulatedClockKey)
        let clock = AppClock(defaults: defaults, launch: launch)
        XCTAssertEqual(clock.now(current: launch), utc("2026-11-15T15:47:00Z"))
        XCTAssertEqual(clock.now(current: launch.addingTimeInterval(90)), utc("2026-11-15T15:48:30Z"))

        let real = AppClock(defaults: freshDefaults(), launch: launch)
        XCTAssertNil(real.simulatedStart)
        XCTAssertEqual(real.now(current: launch.addingTimeInterval(5)), launch.addingTimeInterval(5))
    }

    private let viewport = RideCamera.Viewport(aheadPoints: 300, viewHeight: 852)

    private func visibleAheadM(zoom: Double, pitch: Double) -> Double {
        let radians = pitch * .pi / 180
        let groundPoints = viewport.aheadPoints / (cos(radians) - viewport.aheadPoints / (1.5 * viewport.viewHeight) * sin(radians))
        return groundPoints * RideCamera.metersPerPointAtZoomZero * cos(52.09 * .pi / 180) / pow(2, zoom)
    }

    private func follow(_ options: RideCamera.FollowOptions, distance: Double?, speedKmh: Double?, bearing: Double = 137) -> RideCamera.Follow {
        RideCamera.follow(bearing: bearing, options: options, distanceToManeuverM: distance, speedKmh: speedKmh, latitude: 52.09, viewport: viewport)
    }

    func testTheFollowingCameraForEveryOptionCombination() {
        for northUp in [false, true] {
            for threeD in [false, true] {
                let fixed = follow(RideCamera.FollowOptions(northUp: northUp, threeD: threeD, autoZoom: false), distance: 60, speedKmh: 40)
                XCTAssertEqual(fixed.direction, northUp ? 0 : 137, "northUp=\(northUp) threeD=\(threeD)")
                XCTAssertEqual(fixed.pitch, threeD ? 40 : 0, "northUp=\(northUp) threeD=\(threeD)")
                XCTAssertEqual(fixed.zoom, 16.5, "fixed zoom without auto-zoom")

                let auto = follow(RideCamera.FollowOptions(northUp: northUp, threeD: threeD, autoZoom: true), distance: 60, speedKmh: 40)
                XCTAssertEqual(auto.direction, fixed.direction)
                XCTAssertEqual(auto.pitch, fixed.pitch)
                XCTAssertEqual(auto.zoom, RideCamera.maxZoom, "close to the maneuver the map is zoomed in all the way")
            }
        }
    }

    func testTheDefaultFollowingCameraIsTodaysCamera() {
        XCTAssertEqual(follow(RideCamera.FollowOptions(), distance: 900, speedKmh: 45, bearing: 250), RideCamera.Follow(zoom: 16.5, pitch: 40, direction: 250))
    }

    func testAutoZoomWithoutAMeasuredMapKeepsTheFixedZoom() {
        let follow = RideCamera.follow(
            bearing: 0,
            options: RideCamera.FollowOptions(autoZoom: true),
            distanceToManeuverM: 60,
            speedKmh: 40,
            latitude: 52.09,
            viewport: nil
        )
        XCTAssertEqual(follow.zoom, RideCamera.fixedZoom)
    }

    func testAutoZoomShowsTheNextManeuverFromTwoHundredMetresOut() {
        for threeD in [false, true] {
            let options = RideCamera.FollowOptions(threeD: threeD, autoZoom: true)
            for speed in [0.0, 15, 25, 45] {
                for distance in stride(from: 200.0, through: 60, by: -10) {
                    let zoom = follow(options, distance: distance, speedKmh: speed).zoom
                    let visible = visibleAheadM(zoom: zoom, pitch: threeD ? 40 : 0)
                    XCTAssertGreaterThanOrEqual(visible, distance, "a maneuver \(distance) m ahead at \(speed) km/h is off the map (threeD=\(threeD))")
                }
            }
            for distance in stride(from: 300.0, through: 200, by: -10) {
                let zoom = follow(options, distance: distance, speedKmh: 45).zoom
                XCTAssertGreaterThanOrEqual(visibleAheadM(zoom: zoom, pitch: threeD ? 40 : 0), distance, "at speed the maneuver shows from 300 m")
            }
        }
    }

    func testAutoZoomClosesInOnAManeuverAndOpensUpOnAFastStraight() {
        let options = RideCamera.FollowOptions(autoZoom: true)
        let cruisingFast = follow(options, distance: 2000, speedKmh: 45).zoom
        let cruisingSlow = follow(options, distance: 2000, speedKmh: 10).zoom
        XCTAssertLessThan(cruisingFast, cruisingSlow, "a fast straight shows more road")
        XCTAssertEqual(follow(options, distance: 2000, speedKmh: 80).zoom, cruisingFast)
        XCTAssertEqual(follow(options, distance: nil, speedKmh: nil).zoom, cruisingSlow)
        XCTAssertEqual(visibleAheadM(zoom: cruisingFast, pitch: 40), RideCamera.fastAheadM, accuracy: 1)
        XCTAssertEqual(visibleAheadM(zoom: cruisingSlow, pitch: 40), RideCamera.slowAheadM, accuracy: 1)
        XCTAssertGreaterThan(follow(options, distance: 150, speedKmh: 45).zoom, cruisingFast)
        XCTAssertEqual(follow(options, distance: 20, speedKmh: 45).zoom, RideCamera.maxZoom)
    }

    func testAutoZoomNeverZoomsOutWhileGettingCloser() {
        var previous = -Double.infinity
        for distance in stride(from: 1500.0, through: 0, by: -10) {
            let zoom = follow(RideCamera.FollowOptions(autoZoom: true), distance: distance, speedKmh: 36).zoom
            XCTAssertGreaterThanOrEqual(zoom, previous, "zoomed out at \(distance) m")
            previous = zoom
        }
    }

    func testTheRiderSitsLowOnTheMapWhenTheCourseIsUpAndInTheMiddleWhenNorthIs() throws {
        let window = CGSize(width: 393, height: 852)
        let area = CGRect(x: 8, y: 240, width: 301, height: 370)
        let courseUp = try XCTUnwrap(RideCamera.followLayout(area: area, window: window, northUp: false, landscape: false))
        XCTAssertEqual(courseUp.anchor.x, 196.5)
        XCTAssertEqual(courseUp.anchor.y, 240 + 370 * RideCamera.courseUpAnchorShare, accuracy: 0.01)
        XCTAssertEqual(courseUp.viewport.aheadPoints, 370 * RideCamera.courseUpAnchorShare - RideCamera.aheadMarginPoints, accuracy: 0.01)
        XCTAssertEqual(courseUp.anchor.y + courseUp.halfSize.height, area.maxY, accuracy: 0.01)

        let northUp = try XCTUnwrap(RideCamera.followLayout(area: area, window: window, northUp: true, landscape: false))
        XCTAssertEqual(northUp.anchor.y, area.midY, accuracy: 0.01)
        XCTAssertEqual(northUp.viewport.aheadPoints, 185 - RideCamera.aheadMarginPoints, accuracy: 0.01)

        let landscapeArea = CGRect(x: 360, y: 8, width: 300, height: 370)
        let landscape = try XCTUnwrap(RideCamera.followLayout(area: landscapeArea, window: CGSize(width: 852, height: 393), northUp: false, landscape: true))
        XCTAssertEqual(landscape.anchor.x, landscapeArea.midX)
        XCTAssertEqual(landscape.halfSize.width, 150)

        XCTAssertNil(RideCamera.followLayout(area: .zero, window: window, northUp: false, landscape: false))
    }
}
