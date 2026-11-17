@testable import Naviscoot
import SwiftUI
import XCTest

@MainActor
final class PlaceETATests: XCTestCase {
    private struct Unreachable: Error {}

    private final class FakePlanner {
        var requests: [Coordinate] = []
        var fails = false
        var cancelsCaller = false

        func fetch(_: Coordinate, _ destination: Coordinate) async throws -> TimeInterval {
            requests.append(destination)
            if cancelsCaller {
                withUnsafeCurrentTask { $0?.cancel() }
                throw CancellationError()
            }
            if fails { throw Unreachable() }
            return 720
        }
    }

    private let origin = PlaceETATests.centre(of: PlaceETAStore.OriginCell(Coordinate(lat: 52.1950, lon: 5.3738)))
    private let home = Coordinate(lat: 52.1491, lon: 5.3738)
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)
    private let planner = FakePlanner()

    private func makeStore() -> PlaceETAStore {
        PlaceETAStore(fetch: { [planner] origin, destination in try await planner.fetch(origin, destination) }, now: { [unowned self] in clock })
    }

    nonisolated private static func centre(of cell: PlaceETAStore.OriginCell) -> Coordinate {
        let lat = Double(cell.row) * PlaceETAStore.originCellM / 111_320
        let lon = Double(cell.column) * PlaceETAStore.originCellM / (111_320 * cos(lat * .pi / 180))
        return Coordinate(lat: lat, lon: lon)
    }

    private func offset(_ coordinate: Coordinate, northM: Double, eastM: Double = 0) -> Coordinate {
        Coordinate(
            lat: coordinate.lat + northM / 111_320,
            lon: coordinate.lon + eastM / (111_320 * cos(coordinate.lat * .pi / 180))
        )
    }

    func testAPlaceFarAwayGetsItsMinutesFromOneRequest() async {
        let store = makeStore()
        XCTAssertNil(store.seconds(to: home, from: origin))
        await store.refresh(from: origin, to: [home])
        XCTAssertEqual(store.seconds(to: home, from: origin), 720)
        XCTAssertEqual(planner.requests, [home])
    }

    func testAPlaceWithin300MetresGetsNoRequest() async {
        let store = makeStore()
        let near = offset(origin, northM: 250)
        let justOutside = offset(origin, northM: 320)
        await store.refresh(from: origin, to: [near, justOutside])
        XCTAssertEqual(planner.requests, [justOutside])
        XCTAssertNil(store.seconds(to: near, from: origin))
    }

    func testOriginsInTheSame200MetreCellShareTheCacheAndANewCellAsksAgain() async {
        let store = makeStore()
        let cell = PlaceETAStore.OriginCell(origin)
        let sameCell = [offset(origin, northM: 60, eastM: -40), offset(origin, northM: -40, eastM: 60)]
        for moved in sameCell {
            XCTAssertEqual(PlaceETAStore.OriginCell(moved), cell)
        }
        let nextCell = offset(origin, northM: 250)
        XCTAssertNotEqual(PlaceETAStore.OriginCell(nextCell), cell)
        XCTAssertNotEqual(PlaceETAStore.OriginCell(offset(origin, northM: 0, eastM: 250)), cell)

        await store.refresh(from: origin, to: [home])
        for moved in sameCell {
            await store.refresh(from: moved, to: [home])
            XCTAssertEqual(store.seconds(to: home, from: moved), 720)
        }
        XCTAssertEqual(planner.requests.count, 1)

        XCTAssertNil(store.seconds(to: home, from: nextCell))
        await store.refresh(from: nextCell, to: [home])
        XCTAssertEqual(planner.requests.count, 2)
    }

    func testTheCacheHoldsForFiveMinutes() async {
        let store = makeStore()
        await store.refresh(from: origin, to: [home])
        clock.addTimeInterval(299)
        await store.refresh(from: origin, to: [home])
        XCTAssertEqual(store.seconds(to: home, from: origin), 720)
        XCTAssertEqual(planner.requests.count, 1)

        clock.addTimeInterval(2)
        XCTAssertNil(store.seconds(to: home, from: origin), "an expired ETA still shows")
        await store.refresh(from: origin, to: [home])
        XCTAssertEqual(planner.requests.count, 2)
        XCTAssertEqual(store.seconds(to: home, from: origin), 720)
    }

    func testAFailureLeavesTheDistanceOnlyAndIsNotRetriedWithinFiveMinutes() async {
        let store = makeStore()
        planner.fails = true
        await store.refresh(from: origin, to: [home])
        XCTAssertNil(store.seconds(to: home, from: origin))
        await store.refresh(from: origin, to: [home])
        XCTAssertEqual(planner.requests.count, 1, "a failing API is asked again before the cache expires")

        planner.fails = false
        clock.addTimeInterval(301)
        await store.refresh(from: origin, to: [home])
        XCTAssertEqual(store.seconds(to: home, from: origin), 720)
    }

    func testARequestCancelledMidFlightIsAskedAgainNextTime() async {
        let store = makeStore()
        planner.cancelsCaller = true
        await Task { await store.refresh(from: origin, to: [home]) }.value

        planner.cancelsCaller = false
        await store.refresh(from: origin, to: [home])
        XCTAssertEqual(planner.requests.count, 2, "a cancelled request was cached as a failure")
        XCTAssertEqual(store.seconds(to: home, from: origin), 720)
    }

    func testOnlyTheFirstFivePlacesAreAsked() async {
        let store = makeStore()
        let places = (1 ... 7).map { offset(origin, northM: Double($0) * 1000) }
        await store.refresh(from: origin, to: places)
        XCTAssertEqual(planner.requests, Array(places.prefix(5)))
    }

    func testNoETAWhileTheDrawerIsCollapsedOrShowsSearchResults() {
        XCTAssertFalse(HomeDrawer.wantsETA(detent: .drawerCollapsed, showsPlaces: true))
        XCTAssertTrue(HomeDrawer.wantsETA(detent: .medium, showsPlaces: true))
        XCTAssertTrue(HomeDrawer.wantsETA(detent: .large, showsPlaces: true))
        XCTAssertFalse(HomeDrawer.wantsETA(detent: .large, showsPlaces: false))
    }
}
