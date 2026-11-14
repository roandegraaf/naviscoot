import AVFoundation
import FerrostarCore
import FerrostarCoreFFI
@testable import Naviscoot
import XCTest

final class RideTests: XCTestCase {
    private func plan(_ name: String = "route-default") throws -> RoutePlan {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"))
        return try RouteParser.parse(Data(contentsOf: url))
    }

    func testStepGeometriesShareJointsAndConcatenateToTheRouteGeometry() throws {
        let route = try plan().route
        let counts = route.steps.map(\.geometry.count)
        let arrive = try XCTUnwrap(route.steps.last)
        XCTAssertEqual(arrive.geometry, [route.geometry.last!, route.geometry.last!])
        XCTAssertEqual(counts.dropLast().reduce(0, +) - (counts.count - 2), route.geometry.count)
        let geometry = RouteGeometry(route: route)
        for (index, step) in route.steps.enumerated() {
            XCTAssertEqual(route.geometry[geometry.stepStartIndices[index]], step.geometry.first, "step \(index)")
        }
        let lastStep = route.steps.count - 1
        XCTAssertEqual(geometry.globalIndex(completedSteps: lastStep, stepGeometryIndex: counts[lastStep] - 1), route.geometry.count - 1)
        XCTAssertEqual(geometry.globalIndex(completedSteps: 1, stepGeometryIndex: 2), geometry.stepStartIndices[1] + 2)
    }

    func testProgressProjectsTheSnappedPositionOntoTheRoute() throws {
        let geometry = RouteGeometry(route: try plan().route)
        let index = 700
        let a = geometry.points[index]
        let b = geometry.points[index + 1]
        let between = Coordinate(lat: (a.lat + b.lat) / 2, lon: (a.lon + b.lon) / 2)
        let expected = (geometry.cumulativeM[index] + geometry.cumulativeM[index + 1]) / 2
        XCTAssertEqual(geometry.progressM(near: index, snapped: between), expected, accuracy: 0.5)
        XCTAssertEqual(geometry.progressM(near: index + 1, snapped: between), expected, accuracy: 0.5)
        XCTAssertEqual(geometry.lengthM, 36255, accuracy: 36255 * 0.002)
    }

    func testUnverifiedWarningTriggersWithinTheLeadDistanceAndStaysOnWhileInside() throws {
        let plan = try plan()
        let geometry = RouteGeometry(route: plan.route)
        let spans = UnverifiedWarnings.spans(stretches: plan.meta.stretches, geometry: geometry)
        XCTAssertEqual(spans.count, 1)
        let span = try XCTUnwrap(spans.first)
        XCTAssertEqual(span.key, "1497802338")
        XCTAssertEqual(span.lengthM, 483)
        XCTAssertEqual(span.endM - span.startM, 483, accuracy: 5)

        XCTAssertNil(UnverifiedWarnings.alert(progressM: 0, spans: spans))
        XCTAssertNil(UnverifiedWarnings.alert(progressM: span.startM - 1001, spans: spans))
        guard case let .ahead(key, distance, length) = UnverifiedWarnings.alert(progressM: span.startM - 999, spans: spans) else {
            return XCTFail("expected an ahead warning")
        }
        XCTAssertEqual(key, span.key)
        XCTAssertEqual(distance, 999, accuracy: 0.001)
        XCTAssertEqual(length, 483)
        XCTAssertEqual(
            UnverifiedWarnings.alert(progressM: span.startM + 100, spans: spans),
            .inside(key: span.key, remainingM: span.endM - span.startM - 100)
        )
        XCTAssertNil(UnverifiedWarnings.alert(progressM: span.endM + 1, spans: spans))
    }

    func testWarningPicksTheNextSpanAndIsAnnouncedOncePerStretch() {
        let spans = [
            UnverifiedSpan(key: "1", startM: 100, endM: 200, lengthM: 100),
            UnverifiedSpan(key: "2", startM: 900, endM: 1000, lengthM: 100),
        ]
        XCTAssertEqual(UnverifiedWarnings.alert(progressM: 250, spans: spans)?.key, "2")
        XCTAssertEqual(UnverifiedWarnings.alert(progressM: 0, spans: spans, leadM: 50), nil)

        var announcer = WarningAnnouncer()
        XCTAssertFalse(announcer.shouldAnnounce(nil))
        XCTAssertTrue(announcer.shouldAnnounce(.ahead(key: "1", distanceM: 90, lengthM: 100)))
        XCTAssertFalse(announcer.shouldAnnounce(.ahead(key: "1", distanceM: 40, lengthM: 100)))
        XCTAssertFalse(announcer.shouldAnnounce(.inside(key: "1", remainingM: 50)))
        XCTAssertTrue(announcer.shouldAnnounce(.inside(key: "2", remainingM: 50)))
    }

    func testSpeedLimitAndStretchLookupFollowTheAPIRuns() throws {
        let plan = try plan()
        let runs = try XCTUnwrap(plan.meta.speedLimits)
        XCTAssertEqual(runs.first?.startShapeIndex, 0)
        XCTAssertEqual(runs.last?.endShapeIndex, plan.route.geometry.count - 1)
        let unverified = try XCTUnwrap(plan.unverifiedStretches.first)
        XCTAssertEqual(RouteLookup.limitKmh(atShapeIndex: 0, meta: plan.meta), 45)
        XCTAssertEqual(RouteLookup.limitKmh(atShapeIndex: unverified.startShapeIndex, meta: plan.meta), 30)
        XCTAssertEqual(RouteLookup.stretch(atShapeIndex: unverified.startShapeIndex, in: plan.meta.stretches)?.stretchClass, .unverified)
        let after = try XCTUnwrap(plan.meta.stretches.firstIndex(of: unverified)).advanced(by: 1)
        XCTAssertEqual(RouteLookup.stretch(atShapeIndex: unverified.endShapeIndex, in: plan.meta.stretches), plan.meta.stretches[after])
        XCTAssertEqual(RouteLookup.stretch(atShapeIndex: plan.route.geometry.count - 1, in: plan.meta.stretches), plan.meta.stretches.last)
        for stretch in plan.meta.stretches {
            let limit = RouteLookup.limitKmh(atShapeIndex: stretch.startShapeIndex, meta: plan.meta)
            XCTAssertEqual(limit == 45, stretch.stretchClass == .carriageway, "\(stretch)")
        }
    }

    func testDutchPhrasing() {
        XCTAssertEqual(Dutch.distance(43), "40 meter")
        XCTAssertEqual(Dutch.distance(812), "800 meter")
        XCTAssertEqual(Dutch.distance(990), "1 kilometer")
        XCTAssertEqual(Dutch.distance(1234), "1,2 kilometer")
        XCTAssertEqual(Dutch.distance(2000), "2 kilometer")
        XCTAssertEqual(
            Dutch.announcement(for: .ahead(key: "k", distanceM: 812, lengthM: 483)),
            "Let op: over 800 meter een onbevestigd fietspad van 500 meter."
        )
        XCTAssertEqual(
            Dutch.announcement(for: .inside(key: "k", remainingM: 260)),
            "Let op: u rijdt op een onbevestigd fietspad, nog 250 meter."
        )
    }

    func testSpeechWrapperTurnsSSMLIntoADutchUtteranceAndRecordsIt() throws {
        final class Recorder: SpeechSynthesizer {
            var utterances: [AVSpeechUtterance] = []
            var isSpeaking = false
            func speak(_ utterance: AVSpeechUtterance) { utterances.append(utterance) }
            func stopSpeaking(at _: AVSpeechBoundary) -> Bool { true }
        }
        let recorder = Recorder()
        var lines: [SpokenLine] = []
        let voice = AVSpeechSynthesisVoice(language: "nl-NL")
        let speech = DutchSpeechSynthesizer(synthesizer: recorder, voice: voice) { lines.append($0) }

        let ssml = try XCTUnwrap(AVSpeechUtterance(ssmlRepresentation: "<speak>Over 50 meter, Rechts afslaan.</speak>"))
        speech.speak(ssml)
        speech.speak(AVSpeechUtterance(string: "Links afslaan naar Holkerpad."))

        XCTAssertEqual(recorder.utterances.map(\.speechString), ["Over 50 meter, Rechts afslaan.", "Links afslaan naar Holkerpad."])
        XCTAssertEqual(lines.map(\.text), ["Over 50 meter, Rechts afslaan.", "Links afslaan naar Holkerpad."])
        XCTAssertTrue(recorder.utterances.allSatisfy { $0.voice?.language == voice?.language })
        XCTAssertEqual(lines.first?.language, voice?.language)
        XCTAssertEqual(DutchSpeechSynthesizer.plainText("<speak>Rechts <break/>afslaan.</speak>"), "Rechts afslaan.")
    }

    func testRouteProviderAsksTheAPIFromTheUserToTheLastWaypointWithTheSameVerifiedOnlyChoice() async throws {
        final class Planner: RoutePlanning {
            let plan: RoutePlan
            var calls: [(Coordinate, Coordinate, Bool)] = []
            init(plan: RoutePlan) { self.plan = plan }
            func route(from origin: Coordinate, to destination: Coordinate, verifiedOnly: Bool) async throws -> RoutePlan {
                calls.append((origin, destination, verifiedOnly))
                return plan
            }
        }
        let plan = try plan("route-verified-only")
        let planner = Planner(plan: plan)
        let book = PlanBook()
        let provider = NaviscootRouteProvider(planner: planner, verifiedOnly: true, book: book)
        let user = UserLocation(
            coordinates: GeographicCoordinate(lat: 52.2, lng: 5.4),
            horizontalAccuracy: 5,
            courseOverGround: nil,
            timestamp: Date(),
            speed: nil
        )
        let waypoints = [
            Waypoint(coordinate: GeographicCoordinate(lat: 52.29, lng: 5.44), kind: .break),
            Waypoint(coordinate: GeographicCoordinate(lat: 52.04, lng: 5.40), kind: .break),
        ]

        let routes = try await provider.getRoutes(userLocation: user, waypoints: waypoints)

        XCTAssertEqual(routes, [plan.route])
        XCTAssertEqual(planner.calls.count, 1)
        XCTAssertEqual(planner.calls.first?.0, Coordinate(lat: 52.2, lon: 5.4))
        XCTAssertEqual(planner.calls.first?.1, Coordinate(lat: 52.04, lon: 5.40))
        XCTAssertEqual(planner.calls.first?.2, true)
        XCTAssertEqual(book.plan(for: plan.route)?.meta, plan.meta)
        XCTAssertNil(book.plan(for: try self.plan().route))

        do {
            _ = try await provider.getRoutes(userLocation: user, waypoints: [])
            XCTFail("expected noDestination")
        } catch {
            XCTAssertEqual(error as? RideError, .noDestination)
        }
        let destination = try XCTUnwrap(plan.route.waypoints.last)
        XCTAssertEqual(destination.coordinate.lat, 52.0464515, accuracy: 0.001)
        XCTAssertEqual(destination.coordinate.lng, 5.4059619, accuracy: 0.001)
    }

    func testSimulatorStartsAtTheRouteStartAndADetourLeavesTheRoute() throws {
        let route = try plan().route
        let simulator = RideSimulator(speedKmh: 45, tickInterval: 1)
        simulator.follow(route)
        let start = try XCTUnwrap(simulator.lastLocation)
        XCTAssertEqual(Coordinate(start.coordinates), Coordinate(route.geometry[0]))
        let geometry = RouteGeometry(route: route)
        let (point, bearing) = geometry.position(atM: 1000)
        let off = Geo.offset(point, bearing: bearing + 90, distanceM: RideSimulator.detourOffsetM)
        XCTAssertEqual(Geo.distanceM(point, off), RideSimulator.detourOffsetM, accuracy: 0.5)
        XCTAssertEqual(geometry.position(atM: geometry.lengthM).coordinate, Coordinate(route.geometry.last!))
    }
}

@MainActor
final class ReportQueueTests: XCTestCase {
    private final class Sender: ReportSending {
        var results: [Error?]
        var sent: [PendingReport] = []
        init(_ results: [Error?]) { self.results = results }
        func send(_ report: PendingReport) async throws {
            let result = results.isEmpty ? nil : results.removeFirst()
            if let result { throw result }
            sent.append(report)
        }
    }

    private func report(_ n: Int) -> PendingReport {
        PendingReport(id: UUID(), lat: 52 + Double(n) / 100, lon: 5.4, time: Date(timeIntervalSince1970: 1_800_000_000 + Double(n)), routeId: "r\(n)")
    }

    private func storeURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "reports-\(UUID().uuidString).json")
    }

    func testAFailedReportIsKeptOnDiskAndSentLaterInOrderWithItsOriginalTime() async {
        let url = storeURL()
        let sender = Sender([ReportSendError.retryable])
        let queue = ReportQueue(sender: sender, storeURL: url, retryDelays: [])
        let first = report(1)
        let outcome = await queue.submit(first)
        XCTAssertEqual(outcome, .queued)
        XCTAssertEqual(queue.pending, [first])

        let reopened = ReportQueue(sender: sender, storeURL: url, retryDelays: [])
        XCTAssertEqual(reopened.pending, [first])
        let second = report(2)
        let secondOutcome = await reopened.submit(second)
        XCTAssertEqual(secondOutcome, .sent)
        XCTAssertEqual(sender.sent, [first, second])
        XCTAssertEqual(sender.sent.first?.time, Date(timeIntervalSince1970: 1_800_000_001))
        XCTAssertEqual(reopened.pending, [])
        XCTAssertEqual(ReportQueue(sender: nil, storeURL: url).pending, [])
    }

    func testARejectedReportIsDroppedAndTheQueueMovesOn() async {
        let sender = Sender([ReportSendError.rejected(status: 400)])
        let queue = ReportQueue(sender: sender, storeURL: storeURL(), retryDelays: [])
        let outcome = await queue.submit(report(1))
        XCTAssertEqual(outcome, .rejected)
        XCTAssertEqual(queue.pending, [])
        let next = await queue.submit(report(2))
        XCTAssertEqual(next, .sent)
    }

    func testTheQueueRetriesOnItsOwnAfterTheDelay() async throws {
        let sender = Sender([ReportSendError.retryable])
        let queue = ReportQueue(sender: sender, storeURL: storeURL(), retryDelays: [0.2])
        let outcome = await queue.submit(report(1))
        XCTAssertEqual(outcome, .queued)
        try await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertEqual(queue.pending, [])
        XCTAssertEqual(sender.sent.count, 1)
    }

    func testReportRequestCarriesPositionTimeRouteAndKey() throws {
        let client = NaviscootClient(config: APIConfig(baseURL: URL(string: "http://127.0.0.1:8080")!, apiKey: "k"))
        let request = try client.makeReportRequest(report(3))
        XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:8080/reports")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "k")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["lat"] as? Double, 52.03)
        XCTAssertEqual(body["lon"] as? Double, 5.4)
        XCTAssertEqual(body["route_id"] as? String, "r3")
        XCTAssertEqual(body["time"] as? String, "2027-01-15T08:00:03Z")
    }
}
