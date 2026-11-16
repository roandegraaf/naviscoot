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

    func testTheFollowingCameraForEveryOptionCombination() {
        for northUp in [false, true] {
            for threeD in [false, true] {
                let options = RideCamera.FollowOptions(northUp: northUp, threeD: threeD, autoZoom: false)
                let follow = RideCamera.follow(course: 137, options: options, distanceToManeuverM: 60, speedKmh: 40)
                XCTAssertEqual(follow.direction, northUp ? 0 : 137, "northUp=\(northUp) threeD=\(threeD)")
                XCTAssertEqual(follow.pitch, threeD ? 40 : 0, "northUp=\(northUp) threeD=\(threeD)")
                XCTAssertEqual(follow.zoom, 16.5, "fixed zoom without auto-zoom")

                let auto = RideCamera.follow(
                    course: 137,
                    options: RideCamera.FollowOptions(northUp: northUp, threeD: threeD, autoZoom: true),
                    distanceToManeuverM: 60,
                    speedKmh: 40
                )
                XCTAssertEqual(auto.direction, follow.direction)
                XCTAssertEqual(auto.pitch, follow.pitch)
                XCTAssertEqual(auto.zoom, 17.5)
            }
        }
    }

    func testTheDefaultFollowingCameraIsTodaysCamera() {
        let follow = RideCamera.follow(course: 250, options: RideCamera.FollowOptions(), distanceToManeuverM: 900, speedKmh: 45)
        XCTAssertEqual(follow, RideCamera.Follow(zoom: 16.5, pitch: 40, direction: 250))
    }

    func testAutoZoomClosesInOnAManeuverAndOpensUpOnAFastStraight() {
        XCTAssertEqual(RideCamera.autoZoom(distanceToManeuverM: 50, speedKmh: 45), 17.5)
        XCTAssertEqual(RideCamera.autoZoom(distanceToManeuverM: 100, speedKmh: 45), 17.5)
        XCTAssertEqual(RideCamera.autoZoom(distanceToManeuverM: 300, speedKmh: 45), 16.5)
        XCTAssertEqual(RideCamera.autoZoom(distanceToManeuverM: 500, speedKmh: 45), 15.5)
        XCTAssertEqual(RideCamera.autoZoom(distanceToManeuverM: 2000, speedKmh: 45), 15.5)
        XCTAssertEqual(RideCamera.autoZoom(distanceToManeuverM: 2000, speedKmh: 80), 15.5)
        XCTAssertEqual(RideCamera.autoZoom(distanceToManeuverM: 2000, speedKmh: 36), 15.75)
        XCTAssertEqual(RideCamera.autoZoom(distanceToManeuverM: 2000, speedKmh: 10), 16.5)
        XCTAssertEqual(RideCamera.autoZoom(distanceToManeuverM: nil, speedKmh: nil), 16.5)
        XCTAssertEqual(RideCamera.autoZoom(distanceToManeuverM: 2000, speedKmh: nil), 16.5)
    }

    func testAutoZoomNeverZoomsOutWhileGettingCloserAndMovesInQuarterSteps() {
        var previous = -Double.infinity
        for distance in stride(from: 1500.0, through: 0, by: -10) {
            let zoom = RideCamera.autoZoom(distanceToManeuverM: distance, speedKmh: 36)
            XCTAssertGreaterThanOrEqual(zoom, previous, "zoomed out at \(distance) m")
            XCTAssertEqual((zoom * 4).rounded(), zoom * 4, "not a quarter step at \(distance) m")
            previous = zoom
        }
    }
}
