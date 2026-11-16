@testable import Naviscoot
import XCTest

@MainActor
final class ScooterRideTests: XCTestCase {
    private let start = Coordinate(lat: 52.0907, lon: 5.1214)
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func north(_ km: Double) -> Coordinate {
        Coordinate(lat: start.lat + km / 111.2, lon: start.lon)
    }

    private func status(_ rangeKm: Double) -> ScooterRideStatus {
        ScooterRideStatus(batteryPercent: 40, rangeKm: rangeKm)
    }

    func testLowRangeIsShownWhileTrueButSpokenOnce() {
        var monitor = ScooterRideMonitor(start: start)
        let fine = monitor.evaluate(status: status(30), position: start, remainingKm: 20, marginPercent: 15, turnBackEnabled: false)
        XCTAssertEqual(fine, ScooterRideMonitor.Evaluation(shown: nil, announce: nil))

        let first = monitor.evaluate(status: status(22), position: start, remainingKm: 20, marginPercent: 15, turnBackEnabled: false)
        XCTAssertEqual(first, ScooterRideMonitor.Evaluation(shown: .lowRange, announce: .lowRange))
        let again = monitor.evaluate(status: status(21), position: start, remainingKm: 20, marginPercent: 15, turnBackEnabled: false)
        XCTAssertEqual(again, ScooterRideMonitor.Evaluation(shown: .lowRange, announce: nil))

        let recovered = monitor.evaluate(status: status(40), position: start, remainingKm: 20, marginPercent: 15, turnBackEnabled: false)
        XCTAssertNil(recovered.shown)
        let dropped = monitor.evaluate(status: status(21), position: start, remainingKm: 20, marginPercent: 15, turnBackEnabled: false)
        XCTAssertNil(dropped.announce)
    }

    func testTurnBackWaitsForOneKilometreAndUsesTheDetourFactor() {
        var monitor = ScooterRideMonitor(start: start)
        XCTAssertNil(monitor.evaluate(status: status(0.5), position: north(0.9), remainingKm: nil, marginPercent: 0, turnBackEnabled: true).shown)

        let returnKm = 5 * ScooterRideMonitor.returnDetourFactor
        XCTAssertNil(monitor.evaluate(status: status(returnKm + 0.1), position: north(5), remainingKm: nil, marginPercent: 0, turnBackEnabled: true).shown)
        let warned = monitor.evaluate(status: status(returnKm - 0.1), position: north(5), remainingKm: nil, marginPercent: 0, turnBackEnabled: true)
        XCTAssertEqual(warned, ScooterRideMonitor.Evaluation(shown: .turnBack, announce: .turnBack))
    }

    func testTurnBackStaysQuietWhenSwitchedOffAndNothingHappensWithoutAScooter() {
        var monitor = ScooterRideMonitor(start: start)
        XCTAssertNil(monitor.evaluate(status: status(1), position: north(5), remainingKm: nil, marginPercent: 15, turnBackEnabled: false).shown)
        XCTAssertNil(monitor.evaluate(status: nil, position: north(5), remainingKm: 50, marginPercent: 15, turnBackEnabled: true).shown)
    }

    func testBothWarningsAreEachSpokenOnce() {
        var monitor = ScooterRideMonitor(start: start)
        let first = monitor.evaluate(status: status(1), position: north(5), remainingKm: 10, marginPercent: 15, turnBackEnabled: true)
        XCTAssertEqual(first, ScooterRideMonitor.Evaluation(shown: .lowRange, announce: .lowRange))
        let second = monitor.evaluate(status: status(1), position: north(5), remainingKm: 10, marginPercent: 15, turnBackEnabled: true)
        XCTAssertEqual(second, ScooterRideMonitor.Evaluation(shown: .lowRange, announce: .turnBack))
        XCTAssertNil(monitor.evaluate(status: status(1), position: north(5), remainingKm: 10, marginPercent: 15, turnBackEnabled: true).announce)
    }

    func testOnlyAFreshReadingFromAConnectedScooterCounts() {
        let telemetry = ScooterTelemetry(batteryPercent: 47, rangeKm: 23.4, odometerKm: 100, speedKmh: 0)
        let model = ConsumptionModel(samples: [])
        XCTAssertEqual(
            ScooterRideStatus.current(telemetry: telemetry, readAt: now.addingTimeInterval(-30), connected: true, now: now, model: model),
            ScooterRideStatus(batteryPercent: 47, rangeKm: 23.4)
        )
        XCTAssertNil(ScooterRideStatus.current(telemetry: telemetry, readAt: now.addingTimeInterval(-30), connected: false, now: now, model: model))
        XCTAssertNil(ScooterRideStatus.current(telemetry: telemetry, readAt: now.addingTimeInterval(-ScooterRideStatus.freshForS), connected: true, now: now, model: model))
    }

    func testTheBadgeRoundsTheRangeToWholeKilometres() {
        XCTAssertEqual(ScooterRideStatus(batteryPercent: 47, rangeKm: 23.4).badge(language: .english), "47% · 23 km")
        XCTAssertEqual(ScooterRideStatus(batteryPercent: 47, rangeKm: 23.6).badge(language: .dutch), "47% · 24 km")
    }

    func testBatteryRidesInTheActivityStateButNotInTheMilestone() {
        let banner = RideModel.Banner(distanceM: 234, text: "Biltstraat", maneuverType: .turn, maneuverModifier: .left)
        func update(_ battery: String?) -> RideActivityUpdate {
            RideActivityContent.update(banner: banner, arrived: false, alert: nil, remainingM: 4000, remainingS: 600, destination: "Utrecht", now: now, language: .english, battery: battery)
        }
        XCTAssertEqual(update("47% · 23 km").state.battery, "47% · 23 km")
        XCTAssertEqual(update("47% · 23 km").milestone, update("46% · 22 km").milestone)
        XCTAssertEqual(WatchRideContent.state(update("47% · 23 km").state).battery, "47% · 23 km")
    }

    func testPayloadsWithoutBatteryStillDecode() throws {
        let activity = Data("""
        {"symbol":"arrow.up","distance":"200 m","street":"Biltstraat","destination":"Utrecht","arrivalLabel":"Arrival","arrival":"14:05","remaining":"4.0 km","arrived":false}
        """.utf8)
        let state = try JSONDecoder().decode(RideActivityAttributes.ContentState.self, from: activity)
        XCTAssertNil(state.battery)
        XCTAssertEqual(state.street, "Biltstraat")

        let watch = Data("""
        {"sentAt":0,"state":{"symbol":"arrow.up","distance":"200 m","street":"Biltstraat","arrivalLabel":"Arrival","arrival":"14:05","arrived":false}}
        """.utf8)
        let message = try JSONDecoder().decode(WatchRideMessage.self, from: watch)
        XCTAssertNil(message.state?.battery)
        XCTAssertEqual(message.state?.street, "Biltstraat")
    }

    func testALinkLostWhileParkedOrJustBeforeStoppingTheRideIsRecorded() {
        XCTAssertTrue(ParkingRule.recordsLoss(rideActive: false))
        XCTAssertFalse(ParkingRule.recordsLoss(rideActive: true))
        XCTAssertTrue(ParkingRule.recordsPendingLoss(lostAt: now, rideEndedAt: now.addingTimeInterval(90)))
        XCTAssertFalse(ParkingRule.recordsPendingLoss(lostAt: now, rideEndedAt: now.addingTimeInterval(ParkingRule.beforeRideEndGraceS + 1)))
    }

    func testTheParkedSpotSurvivesARelaunchAndClears() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "parked-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let store = ParkedScooterStore(url: url)
        XCTAssertNil(store.parked)

        store.record(start, at: now)
        XCTAssertEqual(ParkedScooterStore(url: url).parked, ParkedScooter(coordinate: start, at: now))

        store.clear()
        XCTAssertNil(ParkedScooterStore(url: url).parked)
    }

    func testTheParkedSubtitleSaysHowLongAgo() {
        let spot = ParkedScooter(coordinate: start, at: now)
        XCTAssertEqual(spot.subtitle(now: now.addingTimeInterval(20), language: .english), "Parked just now")
        XCTAssertEqual(spot.subtitle(now: now.addingTimeInterval(12 * 60), language: .english), "Parked 12 min ago")
        XCTAssertEqual(spot.subtitle(now: now.addingTimeInterval(12 * 60), language: .dutch), "12 min geleden geparkeerd")
    }
}
