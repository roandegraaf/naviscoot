import FerrostarCore
import FerrostarCoreFFI
@testable import Naviscoot
import XCTest

@MainActor
final class LiveActivityTests: XCTestCase {
    private final class FakeActivity: RideActivityPresenting {
        enum Call: Equatable {
            case start(RideActivityAttributes.ContentState)
            case update(RideActivityAttributes.ContentState)
            case end(RideActivityAttributes.ContentState?, dismissAfter: TimeInterval?)
        }

        private(set) var calls: [Call] = []
        let status = "activity=fake"

        func start(_ state: RideActivityAttributes.ContentState, now _: Date) { calls.append(.start(state)) }
        func update(_ state: RideActivityAttributes.ContentState, now _: Date) { calls.append(.update(state)) }
        func end(_ state: RideActivityAttributes.ContentState?, dismissAfter: TimeInterval?) {
            calls.append(.end(state, dismissAfter: dismissAfter))
        }
    }

    private final class Planner: RoutePlanning, @unchecked Sendable {
        let plan: RoutePlan
        init(plan: RoutePlan) { self.plan = plan }
        func route(from _: Coordinate, to _: Coordinate, stops _: [Coordinate], avoid _: RouteAvoid, verifiedOnly _: Bool, language _: Language) async throws -> RoutePlan {
            plan
        }
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let leftTurn = RideModel.Banner(distanceM: 234, text: "Biltstraat", maneuverType: .turn, maneuverModifier: .left)

    private func update(
        banner: RideModel.Banner?,
        arrived: Bool = false,
        alert: UnverifiedAlert? = nil,
        remainingM: Double? = 4230,
        remainingS: Double? = 600,
        language: Language
    ) -> RideActivityUpdate {
        RideActivityContent.update(
            banner: banner,
            arrived: arrived,
            alert: alert,
            remainingM: remainingM,
            remainingS: remainingS,
            destination: "Lieve Vrouwestraat 33",
            now: now,
            language: language
        )
    }

    func testTheBannerBecomesTheManeuverDistanceStreetArrivalAndRemainingDistanceInTheChosenLanguage() {
        let english = update(banner: leftTurn, language: .english).state
        XCTAssertEqual(english.symbol, "arrow.turn.up.left")
        XCTAssertEqual(english.distance, "230 m")
        XCTAssertEqual(english.street, "Biltstraat")
        XCTAssertEqual(english.destination, "Lieve Vrouwestraat 33")
        XCTAssertEqual(english.arrivalLabel, "Arrival")
        XCTAssertEqual(english.arrival, Format.clockTime(now.addingTimeInterval(600), language: .english))
        XCTAssertEqual(english.remaining, "4.2 km")
        XCTAssertNil(english.warning)
        XCTAssertFalse(english.arrived)

        let dutch = update(banner: leftTurn, language: .dutch).state
        XCTAssertEqual(dutch.arrivalLabel, "Aankomst")
        XCTAssertEqual(dutch.remaining, "4,2 km")
        XCTAssertEqual(dutch.arrival, Format.clockTime(now.addingTimeInterval(600), language: .dutch))
        XCTAssertNotEqual(update(banner: leftTurn, language: .dutch).milestone, update(banner: leftTurn, language: .english).milestone)

        let roundabout = RideModel.Banner(distanceM: 1260, text: "Rondweg", maneuverType: .roundabout, maneuverModifier: .right)
        XCTAssertEqual(update(banner: roundabout, language: .dutch).state.symbol, "arrow.triangle.turn.up.right.circle")
        XCTAssertEqual(update(banner: roundabout, language: .dutch).state.distance, "1,3 km")
    }

    func testBeforeTheFirstBannerAndAfterArrivalTheActivityShowsTheDestinationOrArrived() {
        let waiting = update(banner: nil, remainingM: nil, remainingS: nil, language: .english).state
        XCTAssertEqual(waiting.street, "Lieve Vrouwestraat 33")
        XCTAssertEqual(waiting.distance, "")
        XCTAssertEqual(waiting.arrival, "–")
        XCTAssertEqual(waiting.remaining, "–")

        let alert = UnverifiedAlert.inside(key: "42", remainingM: 80)
        let arrived = update(banner: nil, arrived: true, alert: alert, remainingM: 0, remainingS: 0, language: .dutch)
        XCTAssertEqual(arrived.state.symbol, "flag.checkered")
        XCTAssertEqual(arrived.state.street, "Je bent er")
        XCTAssertEqual(arrived.state.distance, "")
        XCTAssertNil(arrived.state.warning)
        XCTAssertTrue(arrived.state.arrived)
        XCTAssertEqual(arrived.state.arrival, Format.clockTime(now, language: .dutch))
    }

    func testTheUnverifiedWarningIsTheRideScreensTextInBothLanguagesAndItsKindIsAMilestone() {
        let ahead = UnverifiedAlert.ahead(key: "42", distanceM: 412, lengthM: 180)
        let inside = UnverifiedAlert.inside(key: "42", remainingM: 96)
        XCTAssertEqual(update(banner: leftTurn, alert: ahead, language: .english).state.warning, Strings.unverifiedAhead("410 m", length: "180 m", language: .english))
        XCTAssertEqual(update(banner: leftTurn, alert: inside, language: .english).state.warning, Strings.unverifiedInside("100 m", language: .english))
        let dutch = update(banner: leftTurn, alert: ahead, language: .dutch).state.warning
        XCTAssertEqual(dutch, Strings.unverifiedAhead("410 m", length: "180 m", language: .dutch))
        XCTAssertNotEqual(dutch, update(banner: leftTurn, alert: ahead, language: .english).state.warning)

        let none = update(banner: leftTurn, language: .english).milestone
        let aheadFar = update(banner: leftTurn, alert: ahead, language: .english).milestone
        let aheadNear = update(banner: leftTurn, alert: .ahead(key: "42", distanceM: 120, lengthM: 180), language: .english).milestone
        let within = update(banner: leftTurn, alert: inside, language: .english).milestone
        XCTAssertNotEqual(none, aheadFar)
        XCTAssertEqual(aheadFar, aheadNear, "a shrinking distance is not a milestone")
        XCTAssertNotEqual(aheadFar, within)
    }

    func testTheThrottleSendsMilestonesAtOnceAndOtherChangesAtMostEveryFiveSecondsWithAMinuteHeartbeat() {
        var throttle = ActivityThrottle()
        let first = update(banner: leftTurn, language: .english)
        let closer = update(banner: RideModel.Banner(distanceM: 150, text: "Biltstraat", maneuverType: .turn, maneuverModifier: .left), language: .english)
        let nextTurn = update(banner: RideModel.Banner(distanceM: 600, text: "Maliebaan", maneuverType: .turn, maneuverModifier: .right), language: .english)
        let warned = update(banner: leftTurn, alert: .ahead(key: "1", distanceM: 900, lengthM: 50), language: .english)

        XCTAssertTrue(throttle.shouldSend(first, now: now))
        XCTAssertFalse(throttle.shouldSend(closer, now: now.addingTimeInterval(4.9)))
        XCTAssertTrue(throttle.shouldSend(closer, now: now.addingTimeInterval(5)))
        XCTAssertFalse(throttle.shouldSend(closer, now: now.addingTimeInterval(20)), "an unchanged state waits for the heartbeat")
        XCTAssertTrue(throttle.shouldSend(nextTurn, now: now.addingTimeInterval(20.5)), "a new maneuver goes out at once")
        XCTAssertTrue(throttle.shouldSend(warned, now: now.addingTimeInterval(21)), "a warning goes out at once")
        XCTAssertFalse(throttle.shouldSend(warned, now: now.addingTimeInterval(80)))
        XCTAssertTrue(throttle.shouldSend(warned, now: now.addingTimeInterval(81)), "the heartbeat keeps the activity from going stale")
        XCTAssertLessThan(ActivityThrottle.heartbeat, ActivityThrottle.staleAfter)
    }

    func testARideStartsItsActivitySendsTheFirstManeuverAtOnceAndEndingRemovesItImmediately() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "route-default", withExtension: "json"))
        let plan = try RouteParser.parse(Data(contentsOf: url))
        let setup = ActiveRide(
            destination: Destination(title: "Lieve Vrouwestraat 33", subtitle: "Amersfoort", coordinate: Coordinate(plan.route.geometry.last!)),
            stops: [],
            verifiedOnly: true,
            avoid: RouteAvoid(ferries: false, unpaved: false, mainRoads: false),
            language: .english
        )
        let fake = FakeActivity()
        let model = RideModel(
            plan: plan,
            ride: setup,
            planner: Planner(plan: plan),
            reports: ReportQueue(sender: nil, storeURL: nil),
            store: nil,
            options: RideOptions(simulate: true, simulatedSpeedKmh: 30, tickInterval: 0.05),
            activity: fake
        )
        model.start()
        guard case let .start(initial)? = fake.calls.first else { return XCTFail("the ride did not start its activity: \(fake.calls)") }
        XCTAssertEqual(initial.destination, "Lieve Vrouwestraat 33")
        XCTAssertEqual(model.activityStats.pushes, 1)

        try await waitUntil(seconds: 10) { model.banner != nil && fake.calls.count >= 2 }
        guard case let .update(first) = fake.calls[1] else { return XCTFail("no update after the first banner: \(fake.calls)") }
        XCTAssertEqual(first.street, model.banner?.text)
        XCTAssertFalse(first.distance.isEmpty)
        XCTAssertNotEqual(first.remaining, "–")
        try await Task.sleep(nanoseconds: 1_000_000_000)
        XCTAssertEqual(fake.calls.count, 2, "distance changes within five seconds are held back: \(fake.calls)")

        model.end()
        XCTAssertEqual(fake.calls.last, .end(nil, dismissAfter: nil))
        let ended = fake.calls.count
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(fake.calls.count, ended, "an ended ride kept updating its activity")
        XCTAssertEqual(fake.calls.filter { if case .start = $0 { true } else { false } }.count, 1)
    }

    private func waitUntil(seconds: Double, _ condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("condition never became true")
    }
}
