import FerrostarCore
import FerrostarCoreFFI
@testable import Naviscoot
import XCTest

@MainActor
final class WatchTests: XCTestCase {
    private final class FakeWatch: RideWatchPresenting {
        private(set) var sent: [(message: WatchRideMessage, urgent: Bool)] = []
        func send(_ message: WatchRideMessage, urgent: Bool) { sent.append((message, urgent)) }
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
        alert: UnverifiedAlert? = nil,
        cue: WatchCue? = nil,
        language: Language = .english,
        at time: Date? = nil
    ) -> WatchRideUpdate {
        let activity = RideActivityContent.update(
            banner: banner,
            arrived: false,
            alert: alert,
            remainingM: 4230,
            remainingS: 600,
            destination: "Lieve Vrouwestraat 33",
            now: now,
            language: language
        )
        return WatchRideContent.update(activity: activity, cue: cue, now: time ?? now)
    }

    func testTheWatchShowsTheManeuverDistanceStreetArrivalAndWarningInTheRideLanguage() throws {
        let ahead = UnverifiedAlert.ahead(key: "42", distanceM: 412, lengthM: 180)
        let english = try XCTUnwrap(update(banner: leftTurn, alert: ahead).message.state)
        XCTAssertEqual(english.symbol, "arrow.turn.up.left")
        XCTAssertEqual(english.distance, "230 m")
        XCTAssertEqual(english.street, "Biltstraat")
        XCTAssertEqual(english.arrivalLabel, "Arrival")
        XCTAssertEqual(english.arrival, Format.clockTime(now.addingTimeInterval(600), language: .english))
        XCTAssertEqual(english.warning, Strings.unverifiedAhead("410 m", length: "180 m", language: .english))
        XCTAssertFalse(english.arrived)

        let roundabout = RideModel.Banner(distanceM: 1260, text: "Rondweg", maneuverType: .roundabout, maneuverModifier: .right)
        let dutch = try XCTUnwrap(update(banner: roundabout, alert: ahead, language: .dutch).message.state)
        XCTAssertEqual(dutch.symbol, "arrow.triangle.turn.up.right.circle")
        XCTAssertEqual(dutch.distance, "1,3 km")
        XCTAssertEqual(dutch.arrivalLabel, "Aankomst")
        XCTAssertEqual(dutch.arrival, Format.clockTime(now.addingTimeInterval(600), language: .dutch))
        XCTAssertEqual(dutch.warning, Strings.unverifiedAhead("410 m", length: "180 m", language: .dutch))
        XCTAssertNotEqual(dutch.warning, english.warning)
    }

    func testAMessageSurvivesTheWatchConnectivityPayloadRoundTrip() throws {
        let riding = update(banner: leftTurn, alert: .inside(key: "7", remainingM: 90), cue: WatchCue(haptic: .unverified, key: "r|unverified|7")).message
        let payload = try riding.payload()
        XCTAssertTrue(payload[WatchRideMessage.payloadKey] is Data, "application context needs property-list values")
        XCTAssertEqual(WatchRideMessage(payload: payload), riding)

        let idle = WatchRideMessage(sentAt: now, state: nil)
        XCTAssertEqual(WatchRideMessage(payload: try idle.payload()), idle)
        XCTAssertNil(WatchRideMessage(payload: ["other": 1]))
        XCTAssertFalse(riding.isStale(now: now.addingTimeInterval(WatchRideMessage.staleAfter)))
        XCTAssertTrue(riding.isStale(now: now.addingTimeInterval(WatchRideMessage.staleAfter + 1)))
    }

    func testTheThrottleSendsMilestonesAndCuesAtOnceAndDistanceChangesAtMostEveryTwoSeconds() {
        var throttle = WatchThrottle()
        let closer = RideModel.Banner(distanceM: 150, text: "Biltstraat", maneuverType: .turn, maneuverModifier: .left)
        let nextTurn = RideModel.Banner(distanceM: 600, text: "Maliebaan", maneuverType: .turn, maneuverModifier: .right)

        XCTAssertEqual(throttle.delivery(for: update(banner: leftTurn), now: now), .urgent)
        XCTAssertNil(throttle.delivery(for: update(banner: closer), now: now.addingTimeInterval(1.9)))
        XCTAssertEqual(throttle.delivery(for: update(banner: closer), now: now.addingTimeInterval(2)), .routine)
        XCTAssertNil(throttle.delivery(for: update(banner: closer), now: now.addingTimeInterval(20)), "an unchanged state waits for the heartbeat")
        XCTAssertEqual(throttle.delivery(for: update(banner: closer), now: now.addingTimeInterval(32)), .routine, "heartbeat")
        let tap = WatchCue(haptic: .turn, key: "r|turn|a#3")
        XCTAssertEqual(throttle.delivery(for: update(banner: closer, cue: tap), now: now.addingTimeInterval(32.5)), .urgent, "a cue never waits")
        XCTAssertEqual(throttle.delivery(for: update(banner: nextTurn), now: now.addingTimeInterval(33)), .urgent, "a new maneuver goes out at once")
        XCTAssertEqual(
            throttle.delivery(for: update(banner: nextTurn, alert: .ahead(key: "1", distanceM: 900, lengthM: 50)), now: now.addingTimeInterval(33.5)),
            .urgent,
            "a warning goes out at once"
        )
        XCTAssertLessThan(WatchThrottle.heartbeat, WatchRideMessage.staleAfter)
    }

    func testTheTurnTapFiresOnceWithinTheThresholdAndAgainForTheNextManeuver() {
        var trigger = WatchCueTrigger(rideKey: "r")
        let left = "arrow.turn.up.left"
        XCTAssertNil(trigger.cue(maneuverKey: "a#1", symbol: left, distanceM: 300, alertKey: nil, arrived: false))
        XCTAssertNil(trigger.cue(maneuverKey: "a#1", symbol: left, distanceM: WatchCueTrigger.turnWithinM + 1, alertKey: nil, arrived: false))
        XCTAssertEqual(
            trigger.cue(maneuverKey: "a#1", symbol: left, distanceM: WatchCueTrigger.turnWithinM, alertKey: nil, arrived: false),
            WatchCue(haptic: .turn, key: "r|turn|a#1")
        )
        XCTAssertNil(trigger.cue(maneuverKey: "a#1", symbol: left, distanceM: 40, alertKey: nil, arrived: false), "one tap per maneuver")
        XCTAssertEqual(
            trigger.cue(maneuverKey: "a#2", symbol: "arrow.turn.up.right", distanceM: 60, alertKey: nil, arrived: false),
            WatchCue(haptic: .turn, key: "r|turn|a#2"),
            "a first banner already inside the threshold still taps"
        )
        XCTAssertNil(trigger.cue(maneuverKey: "a#3", symbol: "arrow.up", distanceM: 50, alertKey: nil, arrived: false), "going straight on doesn't tap")
        XCTAssertNil(trigger.cue(maneuverKey: "a#4", symbol: "flag.checkered", distanceM: 50, alertKey: nil, arrived: false), "the arrival has its own cue")
        XCTAssertNil(trigger.cue(maneuverKey: nil, symbol: left, distanceM: 50, alertKey: nil, arrived: false))
    }

    func testTheUnverifiedTapFiresOncePerStretchAndWinsOverATurnWhichFollowsOnTheNextFix() {
        var trigger = WatchCueTrigger(rideKey: "r")
        let left = "arrow.turn.up.left"
        XCTAssertEqual(
            trigger.cue(maneuverKey: "a#1", symbol: left, distanceM: 80, alertKey: "42", arrived: false),
            WatchCue(haptic: .unverified, key: "r|unverified|42")
        )
        XCTAssertEqual(trigger.cue(maneuverKey: "a#1", symbol: left, distanceM: 70, alertKey: "42", arrived: false)?.haptic, .turn)
        XCTAssertNil(trigger.cue(maneuverKey: "a#1", symbol: left, distanceM: 60, alertKey: "42", arrived: false), "the stretch already tapped")
        XCTAssertNil(trigger.cue(maneuverKey: "a#1", symbol: left, distanceM: 50, alertKey: nil, arrived: false))
        XCTAssertNil(trigger.cue(maneuverKey: "a#1", symbol: left, distanceM: 40, alertKey: "42", arrived: false), "a stretch taps once, also after the warning flickered off")
        XCTAssertEqual(trigger.cue(maneuverKey: "a#1", symbol: left, distanceM: 30, alertKey: "43", arrived: false)?.haptic, .unverified)

        XCTAssertEqual(
            trigger.cue(maneuverKey: "a#9", symbol: "flag.checkered", distanceM: 0, alertKey: nil, arrived: true),
            WatchCue(haptic: .arrived, key: "r|arrived")
        )
        XCTAssertNil(trigger.cue(maneuverKey: "a#9", symbol: "flag.checkered", distanceM: 0, alertKey: nil, arrived: true))
    }

    func testTheWatchPlaysEachCueOnceIgnoresOldCuesAndKeepsTheNewestState() {
        var inbox = WatchInbox()
        let cue = WatchCue(haptic: .turn, key: "r|turn|a#1")
        let tap = update(banner: leftTurn, cue: cue, at: now).message
        XCTAssertEqual(inbox.receive(tap, now: now.addingTimeInterval(1)), .turn)
        XCTAssertNil(inbox.receive(tap, now: now.addingTimeInterval(1.2)), "the context and the message deliver the same cue")

        let newer = update(banner: RideModel.Banner(distanceM: 600, text: "Maliebaan", maneuverType: .turn, maneuverModifier: .right), at: now.addingTimeInterval(3)).message
        XCTAssertNil(inbox.receive(newer, now: now.addingTimeInterval(3)))
        XCTAssertNil(inbox.receive(tap, now: now.addingTimeInterval(3.5)))
        XCTAssertEqual(inbox.latest, newer, "a late, older message doesn't overwrite the screen")

        let replayed = update(banner: leftTurn, cue: WatchCue(haptic: .unverified, key: "r|unverified|42"), at: now.addingTimeInterval(4)).message
        XCTAssertNil(inbox.receive(replayed, now: now.addingTimeInterval(4 + WatchInbox.cueMaxAge + 1)), "a cold launch replaying an old context doesn't buzz")
        XCTAssertEqual(inbox.latest, replayed)

        var fresh = WatchInbox()
        let warned = update(banner: leftTurn, cue: WatchCue(haptic: .unverified, key: "r|unverified|43"), at: now).message
        XCTAssertEqual(fresh.receive(warned, now: now.addingTimeInterval(WatchInbox.cueMaxAge)), .unverified)
        let idle = WatchRideMessage(sentAt: now.addingTimeInterval(5), state: nil)
        XCTAssertNil(fresh.receive(idle, now: now.addingTimeInterval(5)))
        XCTAssertNil(fresh.latest?.state, "an ended ride clears the watch")
    }

    func testARideSendsItsStartAndFirstManeuverToTheWatchAndClearsItAtTheEnd() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "route-default", withExtension: "json"))
        let plan = try RouteParser.parse(Data(contentsOf: url))
        let setup = ActiveRide(
            destination: Destination(title: "Lieve Vrouwestraat 33", subtitle: "Amersfoort", coordinate: Coordinate(plan.route.geometry.last!)),
            stops: [],
            verifiedOnly: true,
            avoid: RouteAvoid(ferries: false, unpaved: false, mainRoads: false),
            language: .english
        )
        let fake = FakeWatch()
        let model = RideModel(
            plan: plan,
            ride: setup,
            planner: Planner(plan: plan),
            reports: ReportQueue(sender: nil, storeURL: nil),
            store: nil,
            options: RideOptions(simulate: true, simulatedSpeedKmh: 30, tickInterval: 0.05),
            watch: fake
        )
        model.start()
        let initial = try XCTUnwrap(fake.sent.first)
        XCTAssertTrue(initial.urgent)
        XCTAssertEqual(initial.message.state?.street, "Lieve Vrouwestraat 33")

        try await waitUntil(seconds: 10) { model.banner != nil && fake.sent.count >= 2 }
        let first = fake.sent[1]
        XCTAssertTrue(first.urgent, "a new maneuver reaches the wrist at once")
        XCTAssertEqual(first.message.state?.street, model.banner?.text)
        XCTAssertEqual(first.message.state?.symbol, RideView.symbol(for: model.banner, arrived: false))
        XCTAssertFalse(first.message.state?.distance.isEmpty ?? true)

        model.end()
        let last = try XCTUnwrap(fake.sent.last)
        XCTAssertNil(last.message.state)
        XCTAssertTrue(last.urgent)
        let ended = fake.sent.count
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(fake.sent.count, ended, "an ended ride kept updating the watch")
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
