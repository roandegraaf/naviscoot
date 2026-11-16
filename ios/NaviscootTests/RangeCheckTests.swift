@testable import Naviscoot
import XCTest

final class RangeCheckTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let telemetry = ScooterTelemetry(batteryPercent: 47, rangeKm: 23.4, odometerKm: 0, speedKmh: 0)

    private func check(routeM: Int, readAgoS: TimeInterval = 30, samples: [ScooterTripSample] = []) -> RangeCheck? {
        RangeCheck(
            routeM: routeM,
            telemetry: telemetry,
            readAt: now.addingTimeInterval(-readAgoS),
            now: now,
            model: ConsumptionModel(samples: samples),
            marginPercent: 15
        )
    }

    func testNoTelemetryMeansNoRangeLine() {
        XCTAssertNil(RangeCheck(routeM: 5000, telemetry: nil, readAt: nil, now: now, model: ConsumptionModel(samples: []), marginPercent: 15))
    }

    func testAShortTripFitsBothWaysOnTheSegwayEstimate() throws {
        let check = try XCTUnwrap(check(routeM: 10000))
        XCTAssertEqual(check.oneWay, .fits(spareKm: 23.4 - 10))
        XCTAssertEqual(check.roundTrip, .tight(spareKm: 23.4 - 20))
        XCTAssertFalse(check.learned)
        XCTAssertNil(check.readAgoS)
        XCTAssertEqual(Strings.format("range.fits", "13.4 km", language: .english), "Fits · 13.4 km to spare")
    }

    func testALongTripIsShortAndTheWayBackIsFlagged() throws {
        let check = try XCTUnwrap(check(routeM: 30000))
        XCTAssertEqual(check.oneWay, .short(missingKm: 30 - 23.4))
        XCTAssertEqual(check.roundTrip, .short(missingKm: 60 - 23.4))
    }

    func testLearnedConsumptionReplacesTheSegwayEstimate() throws {
        let check = try XCTUnwrap(check(routeM: 10000, samples: [ScooterTripSample(distanceKm: 20, batteryUsedPercent: 25)]))
        XCTAssertTrue(check.learned)
        XCTAssertEqual(check.rangeKm, 47 * 0.8, accuracy: 1e-9)
    }

    func testAnOldReadingSaysHowOldItIs() throws {
        XCTAssertNil(try XCTUnwrap(check(routeM: 10000, readAgoS: 9 * 60)).readAgoS)
        XCTAssertEqual(try XCTUnwrap(check(routeM: 10000, readAgoS: 25 * 60)).readAgoS, 25 * 60)
    }

    func testTheDetailLineReadsInBothLanguages() {
        XCTAssertEqual(Strings.format("range.battery", 47, "23 km", "Segway estimate", language: .english), "Battery 47% · 23 km range, Segway estimate")
        XCTAssertEqual(Strings.format("range.battery", 47, "23 km", "schatting van Segway", language: .dutch), "Accu 47% · 23 km bereik, schatting van Segway")
    }
}
