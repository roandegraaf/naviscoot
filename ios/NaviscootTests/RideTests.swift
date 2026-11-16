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

    func testMultiLegStepsMapOntoTheConcatenatedGeometryAcrossIntermediateArrivals() throws {
        let plan = try plan("route-multi-stop")
        let route = plan.route
        let legs = try XCTUnwrap(plan.meta.legs)
        XCTAssertEqual(legs.count, 3)
        XCTAssertEqual(route.waypoints.count, 4)
        let geometry = RouteGeometry(route: route)
        XCTAssertEqual(geometry.stepStartIndices.count, route.steps.count)
        for (index, step) in route.steps.enumerated() {
            for (offset, point) in step.geometry.enumerated() {
                let global = geometry.globalIndex(completedSteps: index, stepGeometryIndex: offset)
                XCTAssertEqual(route.geometry[global], point, "step \(index) point \(offset)")
            }
        }
        let departs = route.steps.indices.filter { index in
            index == 0 || Set(route.steps[index - 1].geometry.map(Coordinate.init)).count == 1
        }
        XCTAssertEqual(departs.map { geometry.stepStartIndices[$0] }, legs.map(\.startShapeIndex))
        let lastStep = route.steps.count - 1
        XCTAssertEqual(geometry.globalIndex(completedSteps: lastStep, stepGeometryIndex: 0), route.geometry.count - 1)

        let lastLeg = try XCTUnwrap(legs.last)
        let inLastLeg = lastLeg.startShapeIndex + 40
        let a = geometry.points[inLastLeg]
        let b = geometry.points[inLastLeg + 1]
        let between = Coordinate(lat: (a.lat + b.lat) / 2, lon: (a.lon + b.lon) / 2)
        let expected = (geometry.cumulativeM[inLastLeg] + geometry.cumulativeM[inLastLeg + 1]) / 2
        XCTAssertEqual(geometry.progressM(near: inLastLeg, snapped: between), expected, accuracy: 0.5)

        let span = UnverifiedSpan(key: "x", startM: expected + 200, endM: expected + 300, lengthM: 100)
        XCTAssertEqual(UnverifiedWarnings.alert(progressM: expected, spans: [span]), .ahead(key: "x", distanceM: 200, lengthM: 100))
        let later = geometry.position(atM: expected + 250).coordinate
        let laterIndex = try XCTUnwrap(geometry.cumulativeM.lastIndex { $0 <= expected + 250 })
        XCTAssertEqual(UnverifiedWarnings.alert(progressM: geometry.progressM(near: laterIndex, snapped: later), spans: [span])?.key, "x")
        XCTAssertGreaterThan(expected, geometry.distanceM(atShapeIndex: lastLeg.startShapeIndex))
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
        XCTAssertEqual(SpokenPhrases.distance(43, language: .dutch), "40 meter")
        XCTAssertEqual(SpokenPhrases.distance(812, language: .dutch), "800 meter")
        XCTAssertEqual(SpokenPhrases.distance(990, language: .dutch), "1 kilometer")
        XCTAssertEqual(SpokenPhrases.distance(1234, language: .dutch), "1,2 kilometer")
        XCTAssertEqual(SpokenPhrases.distance(2000, language: .dutch), "2 kilometer")
        XCTAssertEqual(
            SpokenPhrases.announcement(for: .ahead(key: "k", distanceM: 812, lengthM: 483), language: .dutch),
            "Let op: over 800 meter een onbevestigd fietspad van 500 meter."
        )
        XCTAssertEqual(
            SpokenPhrases.announcement(for: .inside(key: "k", remainingM: 260), language: .dutch),
            "Let op: u rijdt op een onbevestigd fietspad, nog 250 meter."
        )
    }

    func testEnglishPhrasingMatchesValhallasBritishUnits() {
        XCTAssertEqual(SpokenPhrases.distance(43, language: .english), "40 metres")
        XCTAssertEqual(SpokenPhrases.distance(812, language: .english), "800 metres")
        XCTAssertEqual(SpokenPhrases.distance(990, language: .english), "1 kilometre")
        XCTAssertEqual(SpokenPhrases.distance(1234, language: .english), "1.2 kilometres")
        XCTAssertEqual(SpokenPhrases.distance(2000, language: .english), "2 kilometres")
        XCTAssertEqual(
            SpokenPhrases.announcement(for: .ahead(key: "k", distanceM: 812, lengthM: 483), language: .english),
            "Caution: in 800 metres, an unverified cycle path of 500 metres."
        )
        XCTAssertEqual(
            SpokenPhrases.announcement(for: .inside(key: "k", remainingM: 260), language: .english),
            "Caution: you are on an unverified cycle path, 250 metres left."
        )
    }

    func testSpeechWrapperTurnsSSMLIntoAPlainUtteranceInTheVoiceAndRecordsIt() throws {
        final class Recorder: SpeechSynthesizer {
            var utterances: [AVSpeechUtterance] = []
            var isSpeaking = false
            func speak(_ utterance: AVSpeechUtterance) { utterances.append(utterance) }
            func stopSpeaking(at _: AVSpeechBoundary) -> Bool { true }
        }
        let recorder = Recorder()
        var lines: [SpokenLine] = []
        let voice = AVSpeechSynthesisVoice(language: "nl-NL")
        let speech = GuidanceSpeechSynthesizer(synthesizer: recorder, language: .dutch, settings: { SpeechSettings() }) {
            lines.append($0.line)
        }

        let ssml = try XCTUnwrap(AVSpeechUtterance(ssmlRepresentation: "<speak>Over 50 meter, Rechts afslaan.</speak>"))
        speech.speak(ssml)
        speech.speak(AVSpeechUtterance(string: "Links afslaan naar Holkerpad."))

        XCTAssertEqual(recorder.utterances.map(\.speechString), ["Over 50 meter, Rechts afslaan.", "Links afslaan naar Holkerpad."])
        XCTAssertEqual(lines.map(\.text), ["Over 50 meter, Rechts afslaan.", "Links afslaan naar Holkerpad."])
        XCTAssertTrue(recorder.utterances.allSatisfy { $0.voice?.language == voice?.language })
        XCTAssertEqual(lines.first?.language, voice?.language)
        XCTAssertEqual(GuidanceSpeechSynthesizer.plainText("<speak>Rechts <break/>afslaan.</speak>"), "Rechts afslaan.")
    }

    func testBothGuidanceVoicesExistOnThisSystem() {
        for language in Language.allCases {
            XCTAssertEqual(AVSpeechSynthesisVoice(language: language.speechCode)?.language, language.speechCode, "\(language)")
        }
    }

    private final class Planner: RoutePlanning {
        struct Call: Equatable {
            let origin: Coordinate
            let destination: Coordinate
            let stops: [Coordinate]
            let avoid: RouteAvoid
            let verifiedOnly: Bool
            let language: Language
        }

        let plan: RoutePlan
        var failures: [Error]
        private(set) var calls: [Call] = []

        init(plan: RoutePlan, failures: [Error] = []) {
            self.plan = plan
            self.failures = failures
        }

        func route(from origin: Coordinate, to destination: Coordinate, stops: [Coordinate], avoid: RouteAvoid, verifiedOnly: Bool, language: Language) async throws -> RoutePlan {
            calls.append(Call(origin: origin, destination: destination, stops: stops, avoid: avoid, verifiedOnly: verifiedOnly, language: language))
            if !failures.isEmpty { throw failures.removeFirst() }
            return plan
        }
    }

    private let user = UserLocation(
        coordinates: GeographicCoordinate(lat: 52.2, lng: 5.4),
        horizontalAccuracy: 5,
        courseOverGround: nil,
        timestamp: Date(),
        speed: nil
    )

    func testRouteProviderRoutesThroughEveryRemainingWaypointWithTheRidesVerifiedOnlyAvoidAndLanguage() async throws {
        let plan = try plan("route-verified-only")
        let planner = Planner(plan: plan)
        let book = PlanBook()
        let avoid = RouteAvoid(ferries: true, unpaved: false, mainRoads: true)
        let provider = NaviscootRouteProvider(planner: planner, verifiedOnly: true, avoid: avoid, language: .english, book: book)
        var outcomes: [Bool] = []
        provider.onOutcome = { outcomes.append((try? $0.get()) != nil) }
        let waypoints = [
            Waypoint(coordinate: GeographicCoordinate(lat: 52.08, lng: 5.24), kind: .break),
            Waypoint(coordinate: GeographicCoordinate(lat: 52.12, lng: 5.28), kind: .break),
            Waypoint(coordinate: GeographicCoordinate(lat: 52.04, lng: 5.40), kind: .break),
        ]

        let routes = try await provider.getRoutes(userLocation: user, waypoints: waypoints)

        XCTAssertEqual(routes, [plan.route])
        XCTAssertEqual(planner.calls, [Planner.Call(
            origin: Coordinate(lat: 52.2, lon: 5.4),
            destination: Coordinate(lat: 52.04, lon: 5.40),
            stops: [Coordinate(lat: 52.08, lon: 5.24), Coordinate(lat: 52.12, lon: 5.28)],
            avoid: avoid,
            verifiedOnly: true,
            language: .english
        )])
        XCTAssertEqual(outcomes, [true])
        XCTAssertEqual(book.plan(for: plan.route)?.meta, plan.meta)
        XCTAssertNil(book.plan(for: try self.plan().route))

        _ = try await provider.getRoutes(userLocation: user, waypoints: Array(waypoints.suffix(1)))
        XCTAssertEqual(planner.calls.last?.stops, [])
        XCTAssertEqual(planner.calls.last?.destination, Coordinate(lat: 52.04, lon: 5.40))

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

    func testAFailedRerouteIsReportedAndTheRetryStateClearsOnSuccessOrBackOnRoute() async throws {
        let plan = try plan()
        let planner = Planner(plan: plan, failures: [URLError(.notConnectedToInternet)])
        let provider = NaviscootRouteProvider(planner: planner, verifiedOnly: false, avoid: RouteAvoid(), language: .dutch, book: PlanBook(), simulatedFailures: 1)
        var trouble = RerouteTrouble()
        provider.onOutcome = { trouble.record($0) }
        let destination = [Waypoint(coordinate: GeographicCoordinate(lat: 52.04, lng: 5.40), kind: .break)]
        XCTAssertFalse(trouble.isFailing)

        for expectedFailures in 1 ... 2 {
            do {
                _ = try await provider.getRoutes(userLocation: user, waypoints: destination)
                XCTFail("expected a failure")
            } catch {
                XCTAssertTrue(error is URLError, "\(error)")
            }
            XCTAssertTrue(trouble.isFailing)
            XCTAssertEqual(trouble.failures, expectedFailures)
        }
        XCTAssertEqual(planner.calls.count, 1, "the simulated failure must not reach the API")

        let routes = try await provider.getRoutes(userLocation: user, waypoints: destination)
        XCTAssertEqual(routes, [plan.route])
        XCTAssertFalse(trouble.isFailing)

        trouble.record(.failure(URLError(.timedOut)))
        XCTAssertTrue(trouble.isFailing)
        trouble.backOnRoute()
        XCTAssertFalse(trouble.isFailing)
    }

    func testTheStopAnnouncementNamesTheStopAndWhatComesNextInBothLanguages() {
        let zeist = Destination(title: "Slotlaan 10", subtitle: "Zeist", coordinate: Coordinate(lat: 52.08, lon: 5.24))
        let soesterberg = Destination(title: "Kampweg 1", subtitle: "Soesterberg", coordinate: Coordinate(lat: 52.12, lon: 5.28))
        let amersfoort = Destination(title: "Lieve Vrouwestraat 33", subtitle: "Amersfoort", coordinate: Coordinate(lat: 52.15, lon: 5.38))
        XCTAssertEqual(
            SpokenPhrases.stopReached(zeist, next: soesterberg, destination: amersfoort, language: .english),
            "Arriving at your stop, Slotlaan 10. After that, on to Kampweg 1."
        )
        XCTAssertEqual(
            SpokenPhrases.stopReached(soesterberg, next: nil, destination: amersfoort, language: .english),
            "Arriving at your stop, Kampweg 1. After that, on to your destination, Lieve Vrouwestraat 33."
        )
        XCTAssertEqual(
            SpokenPhrases.stopReached(zeist, next: soesterberg, destination: amersfoort, language: .dutch),
            "Je komt aan bij je tussenstop, Slotlaan 10. Daarna door naar Kampweg 1."
        )
        XCTAssertEqual(
            SpokenPhrases.stopReached(soesterberg, next: nil, destination: amersfoort, language: .dutch),
            "Je komt aan bij je tussenstop, Kampweg 1. Daarna door naar je bestemming, Lieve Vrouwestraat 33."
        )
    }

    func testTheActiveRideSurvivesAReopenedStoreAndIsGoneAfterClear() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "active-ride-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let ride = ActiveRide(
            destination: Destination(title: "Lieve Vrouwestraat 33", subtitle: "Amersfoort", coordinate: Coordinate(lat: 52.15612897, lon: 5.38786971)),
            stops: [Destination(title: "Kampweg 1", subtitle: "Soesterberg", coordinate: Coordinate(lat: 52.12033201, lon: 5.28612696))],
            verifiedOnly: true,
            avoid: RouteAvoid(ferries: true, unpaved: false, mainRoads: true),
            language: .dutch
        )
        XCTAssertNil(ActiveRideStore(url: url).load())
        ActiveRideStore(url: url).save(ride)
        XCTAssertEqual(ActiveRideStore(url: url).load(), ride)

        var advanced = ride
        advanced.stops = []
        ActiveRideStore(url: url).save(advanced)
        XCTAssertEqual(ActiveRideStore(url: url).load(), advanced)

        ActiveRideStore(url: url).clear()
        XCTAssertNil(ActiveRideStore(url: url).load())
        XCTAssertNil(ActiveRideStore(url: nil).load())
    }

    @MainActor
    func testResumePlansFromTheCurrentPositionThroughTheRemainingStopsWithTheSameOptions() async throws {
        let plan = try plan("route-multi-stop")
        let planner = Planner(plan: plan, failures: [URLError(.notConnectedToInternet)])
        let ride = ActiveRide(
            destination: Destination(title: "Lieve Vrouwestraat 33", subtitle: "Amersfoort", coordinate: Coordinate(lat: 52.15612897, lon: 5.38786971)),
            stops: [Destination(title: "Kampweg 1", subtitle: "Soesterberg", coordinate: Coordinate(lat: 52.12033201, lon: 5.28612696))],
            verifiedOnly: true,
            avoid: RouteAvoid(ferries: false, unpaved: true, mainRoads: false),
            language: .english
        )
        let model = ResumeModel(ride: ride, planner: planner)
        var planned: RoutePlan?
        model.onPlanned = { planned = $0 }
        model.locationChanged(nil)
        XCTAssertEqual(model.state, .waitingForLocation)

        let here = Coordinate(lat: 52.0823, lon: 5.2401)
        model.locationChanged(here)
        try await waitUntil { if case .failed = model.state { true } else { false } }
        XCTAssertEqual(model.state, .failed(Strings.networkFailed))
        model.retry()
        try await waitUntil { planned != nil }

        XCTAssertEqual(planned?.meta.routeId, plan.meta.routeId)
        let expected = Planner.Call(
            origin: here,
            destination: ride.destination.coordinate,
            stops: [ride.stops[0].coordinate],
            avoid: ride.avoid,
            verifiedOnly: true,
            language: .english
        )
        XCTAssertEqual(planner.calls, [expected, expected])
        XCTAssertEqual(Strings.resumeMessage(ride), "On to Lieve Vrouwestraat 33 via Kampweg 1, from where you are now.")
    }

    func testLocationTroubleIsShownForDeniedOrReducedAccessOnly() {
        XCTAssertEqual(LocationTrouble(status: .denied, accuracy: .fullAccuracy), .denied)
        XCTAssertEqual(LocationTrouble(status: .restricted, accuracy: .fullAccuracy), .denied)
        XCTAssertEqual(LocationTrouble(status: .authorizedWhenInUse, accuracy: .reducedAccuracy), .reducedAccuracy)
        XCTAssertEqual(LocationTrouble(status: .authorizedAlways, accuracy: .reducedAccuracy), .reducedAccuracy)
        XCTAssertNil(LocationTrouble(status: .authorizedWhenInUse, accuracy: .fullAccuracy))
        XCTAssertNil(LocationTrouble(status: .notDetermined, accuracy: .reducedAccuracy))
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0 ..< 200 {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("condition never became true")
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
