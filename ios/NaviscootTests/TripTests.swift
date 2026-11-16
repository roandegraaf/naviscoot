import CoreLocation
@testable import Naviscoot
import SwiftData
import XCTest

@MainActor
final class TripTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    // Measured with CoreLocation itself and shrunk by 0.001 %, so a nominal 15 m step is never 14.9999 m.
    private static let origin = CLLocation(latitude: 52.1, longitude: 5.4)
    private static let metresPerDegreeLat = origin.distance(from: CLLocation(latitude: 52.11, longitude: 5.4)) / 0.01 / 1.00001
    private static let metresPerDegreeLon = origin.distance(from: CLLocation(latitude: 52.1, longitude: 5.41)) / 0.01 / 1.00001

    private func fix(northM: Double, eastM: Double = 0, at seconds: Double, course: Double? = nil, accuracy: Double = 5) -> TrackFix {
        let lat = 52.1 + northM / Self.metresPerDegreeLat
        let lon = 5.4 + eastM / Self.metresPerDegreeLon
        return TrackFix(coordinate: Coordinate(lat: lat, lon: lon), time: start.addingTimeInterval(seconds), courseDegrees: course, horizontalAccuracyM: accuracy)
    }

    private func straightDraft(metres: Double, seconds: Double, stepM: Double = 5) -> TripDraft {
        var draft = TripDraft(startedAt: start, destination: "Biltstraat 100")
        let steps = Int(metres / stepM)
        for index in 0 ... steps {
            draft.add(fix(northM: Double(index) * stepM, at: seconds * Double(index) / Double(steps), course: 0))
        }
        return draft
    }

    private func store(url: URL? = nil) throws -> TripStore {
        TripStore(container: try TripStore.container(url: url))
    }

    func testAStraightTrackIsSampledEveryFifteenMetresAndKeepsItsTail() {
        var draft = straightDraft(metres: 1000, seconds: 120)
        XCTAssertEqual(draft.segments[0].count, 67, "one point every 15 m from 0 to 990 m")
        draft.close()
        XCTAssertEqual(draft.track[0].count, 68, "the last fix is kept as the tail")
        XCTAssertEqual(draft.distanceM, 1000, accuracy: 1)
        XCTAssertEqual(draft.durationS, 120, accuracy: 0.001)
        XCTAssertEqual(draft.averageKmh, 30, accuracy: 0.1)
        XCTAssertTrue(draft.isWorthKeeping)
    }

    func testATurnIsKeptBeforeFifteenMetresButJitterIsNot() {
        var draft = TripDraft(startedAt: start, destination: "X")
        XCTAssertTrue(draft.add(fix(northM: 0, at: 0, course: 0)))
        XCTAssertFalse(draft.add(fix(northM: 4, at: 1, course: 0)), "4 m straight on is jitter")
        XCTAssertFalse(draft.add(fix(northM: 8, at: 2, course: 10)), "8 m with a 10° change is not a turn")
        XCTAssertTrue(draft.add(fix(northM: 8, eastM: 3, at: 3, course: 90)), "≥ 5 m with a 90° change is a turn")
        XCTAssertFalse(draft.add(fix(northM: 8, eastM: 10, at: 4, course: 90)))
        XCTAssertTrue(draft.add(fix(northM: 8, eastM: 20, at: 5, course: 90)))
        XCTAssertEqual(draft.segments[0].count, 3)
    }

    func testCourseChangeWrapsAroundNorth() {
        var draft = TripDraft(startedAt: start, destination: "X")
        draft.add(fix(northM: 0, at: 0, course: 350))
        XCTAssertFalse(draft.add(fix(northM: 8, at: 1, course: 10)), "350° → 10° is a 20° change")
    }

    func testInaccurateOrInvalidFixesAreIgnored() {
        var draft = TripDraft(startedAt: start, destination: "X")
        XCTAssertFalse(draft.add(fix(northM: 0, at: 0, accuracy: 80)))
        XCTAssertFalse(draft.add(fix(northM: 0, at: 0, accuracy: -1)))
        XCTAssertTrue(draft.segments[0].isEmpty)
        XCTAssertTrue(draft.add(fix(northM: 0, at: 1, accuracy: 50)))
        XCTAssertFalse(draft.add(fix(northM: 500, at: 2, accuracy: 120)), "an inaccurate jump adds no distance")
        XCTAssertEqual(draft.distanceM, 0)
    }

    func testNearEmptyRidesAreNotWorthKeeping() {
        XCTAssertFalse(straightDraft(metres: 90, seconds: 60).isWorthKeeping, "90 m")
        XCTAssertFalse(straightDraft(metres: 200, seconds: 20).isWorthKeeping, "20 s")
        XCTAssertTrue(straightDraft(metres: 100, seconds: 30).isWorthKeeping, "exactly 100 m in 30 s")
        XCTAssertFalse(TripDraft(startedAt: start, destination: "X").isWorthKeeping, "no fixes")
        XCTAssertEqual(TripDraft.minimumDistanceM, 100)
        XCTAssertEqual(TripDraft.minimumDurationS, 30)
    }

    func testAResumedTripContinuesWithoutCountingTheGap() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "trip-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let drafts = TripDraftStore(url: url)

        var before = TripDraft(startedAt: start, destination: "Lieve Vrouwestraat 33")
        before.stops = ["Biltstraat 100"]
        for index in 0 ... 40 {
            before.add(fix(northM: Double(index) * 15, at: Double(index) * 2, course: 0))
        }
        drafts.save(before)
        let saved = try XCTUnwrap(drafts.load())
        XCTAssertEqual(saved, before, "the draft survives a kill")

        var delivered: [TripDraft] = []
        let recorder = TripRecorder.resuming(saved, drafts: drafts) { delivered.append($0) }
        for index in 0 ... 20 {
            recorder.observe(fix(northM: 2000 + Double(index) * 15, at: 600 + Double(index) * 2, course: 0))
        }
        recorder.finish()

        let trip = try XCTUnwrap(delivered.first)
        XCTAssertEqual(trip.startedAt, start)
        XCTAssertEqual(trip.stops, ["Biltstraat 100"])
        XCTAssertEqual(trip.track.count, 2, "two segments, one before and one after the kill")
        XCTAssertEqual(trip.distanceM, 600 + 300, accuracy: 2, "the 1400 m gap is not counted")
        XCTAssertEqual(trip.durationS, 80 + 40, accuracy: 0.001, "the time the app was dead is not counted")
        XCTAssertNil(drafts.load(), "the finished draft is cleared")
    }

    func testTheRecorderFinishesOnceAndTracksStopsAndDestinationChanges() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "trip-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let drafts = TripDraftStore(url: url)
        var delivered: [TripDraft] = []
        let recorder = TripRecorder(draft: TripDraft(startedAt: start, destination: "A"), drafts: drafts) { delivered.append($0) }
        recorder.begin()
        XCTAssertEqual(drafts.load()?.destination, "A", "Start writes the draft at once")

        recorder.observe(fix(northM: 0, at: 0))
        recorder.observe(fix(northM: 15, at: 2))
        XCTAssertEqual(drafts.load()?.segments[0].count, 1, "saves are throttled to one per \(TripRecorder.saveInterval) s")
        recorder.observe(fix(northM: 30, at: 6))
        XCTAssertEqual(drafts.load()?.segments[0].count, 3)

        recorder.reachedStop("Stop 1")
        recorder.destinationChanged(to: "B")
        XCTAssertEqual(drafts.load()?.stops, ["Stop 1"])
        XCTAssertEqual(drafts.load()?.destination, "B")

        recorder.finish()
        recorder.observe(fix(northM: 400, at: 60))
        recorder.finish()
        XCTAssertEqual(delivered.count, 1, "arrival and End must not record twice")
        XCTAssertEqual(delivered[0].destination, "B")
        XCTAssertEqual(delivered[0].distanceM, 30, accuracy: 0.5)
        XCTAssertNil(drafts.load())
    }

    func testTheStoreListsNewestFirstRejectsNearEmptyTripsAndDeletes() throws {
        let trips = try store()
        var older = straightDraft(metres: 1000, seconds: 120)
        older.stops = ["Biltstraat 100"]
        let newer = TripDraft(startedAt: start.addingTimeInterval(3600), destination: "Kampweg 1")
        var newerRide = newer
        for index in 0 ... 100 {
            newerRide.add(fix(northM: Double(index) * 20, at: Double(index) * 3, course: 0))
        }

        XCTAssertTrue(trips.add(older))
        XCTAssertTrue(trips.add(newerRide))
        XCTAssertFalse(trips.add(straightDraft(metres: 50, seconds: 60)), "near-empty")
        XCTAssertEqual(trips.trips.map(\.destination), ["Kampweg 1", "Biltstraat 100"])
        XCTAssertEqual(trips.trips[1].stops, ["Biltstraat 100"])
        XCTAssertEqual(trips.trips[1].distanceM, 1000, accuracy: 1)
        XCTAssertEqual(trips.trips[1].averageKmh, 30, accuracy: 0.1)

        trips.delete(trips.trips[0])
        XCTAssertEqual(trips.trips.map(\.destination), ["Biltstraat 100"])
        XCTAssertEqual(trips.totals.count, 1)
    }

    func testTotalsAverageIsTotalDistanceOverTotalTime() throws {
        let trips = try store()
        trips.add(straightDraft(metres: 1000, seconds: 60))
        var slow = TripDraft(startedAt: start.addingTimeInterval(100), destination: "Slow")
        slow.add(fix(northM: 0, at: 0))
        slow.add(fix(northM: 1000, at: 600))
        trips.add(slow)

        XCTAssertEqual(trips.totals.count, 2)
        XCTAssertEqual(trips.totals.distanceM, 2000, accuracy: 1)
        XCTAssertEqual(trips.totals.durationS, 660, accuracy: 0.001)
        XCTAssertEqual(trips.totals.averageKmh, 2000 / 660 * 3.6, accuracy: 0.05, "not the mean of 60 and 6 km/h")
    }

    func testTripsAndTheirTrackSurviveANewContainerOnDisk() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "trips-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
            }
        }
        var draft = straightDraft(metres: 500, seconds: 60)
        draft.close()
        do {
            let trips = try store(url: url)
            XCTAssertTrue(trips.add(draft))
        }

        let reopened = try store(url: url)
        let trip = try XCTUnwrap(reopened.trips.first)
        XCTAssertEqual(trip.destination, "Biltstraat 100")
        XCTAssertEqual(trip.startedAt, start)
        XCTAssertEqual(trip.distanceM, draft.distanceM, accuracy: 0.001)
        XCTAssertEqual(trip.durationS, 60, accuracy: 0.001)
        let track = reopened.track(for: trip)
        XCTAssertEqual(track, draft.track)
        XCTAssertEqual(track.first?.count, 35)

        reopened.removeAll()
        XCTAssertTrue(try store(url: url).trips.isEmpty)
    }

    private func telemetry(_ battery: Int, _ odometerKm: Double) -> ScooterTelemetry {
        ScooterTelemetry(batteryPercent: battery, rangeKm: 0, odometerKm: odometerKm, speedKmh: 0)
    }

    func testTheRecorderKeepsTheFirstAndLatestScooterReading() {
        var delivered: [TripDraft] = []
        let recorder = TripRecorder(draft: straightDraft(metres: 1000, seconds: 120), drafts: nil) { delivered.append($0) }
        recorder.scooterSample(telemetry(80, 1000))
        recorder.scooterSample(telemetry(75, 1004))
        recorder.scooterSample(telemetry(70, 1008))
        recorder.finish()
        recorder.scooterSample(telemetry(10, 2000))

        XCTAssertEqual(delivered.first?.scooterStart, ScooterReading(batteryPercent: 80, odometerKm: 1000))
        XCTAssertEqual(delivered.first?.scooterEnd, ScooterReading(batteryPercent: 70, odometerKm: 1008))
        XCTAssertEqual(delivered.first?.scooterSample, ScooterTripSample(distanceKm: 8, batteryUsedPercent: 10))
    }

    func testASwappedOrChargedPackRestartsTheConsumptionWindow() {
        var draft = straightDraft(metres: 1000, seconds: 120)
        draft.recordScooter(telemetry(30, 500))
        draft.recordScooter(telemetry(20, 505))
        draft.recordScooter(telemetry(21, 505.1))
        XCTAssertEqual(draft.scooterStart?.batteryPercent, 30, "a 1 % bounce is noise")
        draft.recordScooter(telemetry(95, 505.2))
        draft.recordScooter(telemetry(85, 512.2))
        XCTAssertEqual(draft.scooterSample?.batteryUsedPercent, 10)
        XCTAssertEqual(draft.scooterSample?.distanceKm ?? 0, 7, accuracy: 1e-9)
    }

    func testTheStorePoolsScooterTripsIntoAConsumptionModel() throws {
        let trips = try store()
        for (index, (used, km)) in [(12, 6.0), (10, 5.0), (3, 9.0)].enumerated() {
            var draft = straightDraft(metres: 1000, seconds: 120)
            draft.recordScooter(telemetry(90, 100 + Double(index) * 100))
            draft.recordScooter(telemetry(90 - used, 100 + Double(index) * 100 + km))
            trips.add(draft)
        }
        trips.add(straightDraft(metres: 1000, seconds: 120))

        XCTAssertEqual(trips.trips.compactMap(\.scooterSample).count, 3)
        XCTAssertEqual(trips.consumption.kmPerPercent ?? 0, 0.5, accuracy: 1e-9, "the 3 % trip is too small to count")
    }

    func testAStoreWrittenBeforeScooterFieldsStillOpens() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "trips-legacy-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
            }
        }
        do {
            let container = try ModelContainer(for: LegacyTrips.RecordedTrip.self, configurations: ModelConfiguration(url: url))
            let context = ModelContext(container)
            context.insert(LegacyTrips.RecordedTrip(startedAt: start, destination: "Biltstraat 100"))
            try context.save()
        }

        let reopened = try store(url: url)
        XCTAssertEqual(reopened.trips.map(\.destination), ["Biltstraat 100"])
        XCTAssertNil(reopened.trips.first?.scooterSample)
        XCTAssertNil(reopened.consumption.kmPerPercent)
    }

    func testSpeedAndDatesFollowTheLanguage() {
        XCTAssertEqual(Format.speed(kmh: 29.6, language: .english), "30 km/h")
        XCTAssertEqual(Format.speed(kmh: 29.4, language: .dutch), "29 km/u")
        XCTAssertEqual(Format.distance(meters: 1234, language: .dutch), "1,2 km")
        XCTAssertEqual(Strings.format("trip.via", "Biltstraat 100", language: .dutch), "Via Biltstraat 100")
        XCTAssertEqual(Strings.tr("trips.title", language: .dutch), "Ritgeschiedenis")
        XCTAssertEqual(Strings.tr("trips.title", language: .english), "Trip history")
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertNotEqual(Format.dayTime(date, timeZone: TimeZone(identifier: "Europe/Amsterdam")!, language: .dutch),
                          Format.dayTime(date, timeZone: TimeZone(identifier: "Europe/Amsterdam")!, language: .english))
    }
}

private enum LegacyTrips {
    @Model
    final class RecordedTrip {
        var startedAt: Date
        var destination: String
        var stops: [String] = []
        var distanceM: Double = 1000
        var durationS: Double = 120
        @Attribute(.externalStorage) var trackData = Data()

        init(startedAt: Date, destination: String) {
            self.startedAt = startedAt
            self.destination = destination
        }
    }
}
