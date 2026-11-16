import Combine
import CoreLocation
import FerrostarCore
import FerrostarCoreFFI
import Foundation
import UIKit

@MainActor
final class RideModel: ObservableObject {
    struct Banner: Equatable {
        let distanceM: Double
        let text: String
        let maneuverType: ManeuverType?
        let maneuverModifier: ManeuverModifier?
        var exitNumber: Int?
        var lanes: [LaneHint] = []
        var then: ManeuverSummary?

        init(
            distanceM: Double,
            text: String,
            maneuverType: ManeuverType?,
            maneuverModifier: ManeuverModifier?,
            exitNumber: Int? = nil,
            lanes: [LaneHint] = [],
            then: ManeuverSummary? = nil
        ) {
            self.distanceM = distanceM
            self.text = text
            self.maneuverType = maneuverType
            self.maneuverModifier = maneuverModifier
            self.exitNumber = exitNumber
            self.lanes = lanes
            self.then = then
        }

        init(visual: VisualInstruction, distanceM: Double, remainingSteps: [RouteStep]) {
            self.init(
                distanceM: distanceM,
                text: visual.primaryContent.text,
                maneuverType: visual.primaryContent.maneuverType,
                maneuverModifier: visual.primaryContent.maneuverModifier,
                exitNumber: ManeuverHints.exitNumber(for: visual, remainingSteps: remainingSteps),
                lanes: ManeuverHints.lanes(in: visual),
                then: ManeuverHints.maneuverAfterNext(visual, remainingSteps: remainingSteps)
            )
        }
    }

    enum ReportStatus: Equatable {
        case sending
        case sent
        case queued(pending: Int)
        case rejected
    }

    @Published private(set) var plan: RoutePlan
    @Published private(set) var banner: Banner?
    @Published private(set) var alert: UnverifiedAlert?
    @Published private(set) var speedKmh: Int?
    @Published private(set) var limitKmh: Int?
    @Published private(set) var currentClass: StretchClass?
    @Published private(set) var remainingM: Double?
    @Published private(set) var remainingS: Double?
    @Published private(set) var userCoordinate: Coordinate?
    @Published private(set) var courseDegrees: Double = 0
    @Published private(set) var isRerouting = false
    @Published private(set) var rerouteCount = 0
    @Published private(set) var arrived = false
    @Published private(set) var reportStatus: ReportStatus?
    @Published private(set) var spoken: [SpokenLine] = []
    @Published private(set) var speechDecisions: [SpeechDecision] = []
    @Published private(set) var isSpeeding = false
    @Published private(set) var speedingEpisodes = 0
    @Published private(set) var remainingStops: [Destination]
    @Published private(set) var rerouteTrouble = RerouteTrouble()
    @Published private(set) var destination: Destination
    @Published private(set) var editState: RideEditState?
    @Published private(set) var trim: RouteTrim
    @Published private(set) var activityStats = RideActivityStats()
    @Published private(set) var scooter: ScooterRideStatus?
    @Published private(set) var scooterWarning: ScooterRideWarning?

    private(set) var ride: ActiveRide
    let verifiedOnly: Bool
    let avoid: RouteAvoid
    let language: Language
    let options: RideOptions
    private let reports: ReportQueue
    private let store: ActiveRideStore?
    private let trip: TripRecorder?
    private let activity: RideActivityPresenting?
    private var activityThrottle = ActivityThrottle()
    private var activityEnded = false
    private let watch: RideWatchPresenting?
    private var watchThrottle = WatchThrottle()
    private var watchCues = WatchCueTrigger(rideKey: UUID().uuidString)
    private var watchEnded = false
    private var maneuverKey: String?
    private let planner: RoutePlanning
    private let book = PlanBook()
    private let navigationDelegate = RideNavigationDelegate()
    private let simulator: RideSimulator?
    private let core: FerrostarCore
    private let speech: GuidanceSpeechSynthesizer
    private let settings: AppSettings
    private var speeding: SpeedingMonitor
    private var geometry: RouteGeometry
    private var spans: [UnverifiedSpan]
    private var announcer = WarningAnnouncer()
    private var scooterMonitor: ScooterRideMonitor
    private let scooterStatus: @MainActor () -> ScooterRideStatus?
    private var lastRawLocation: Coordinate?
    private(set) var shapeIndex = 0
    private var ended = false
    private var editFailuresToSimulate: Int
    private var cancellables = Set<AnyCancellable>()
    private var reportStatusTask: Task<Void, Never>?
    private var editTask: Task<Void, Never>?
    private var editStateTask: Task<Void, Never>?

    init(
        plan: RoutePlan,
        ride: ActiveRide,
        planner: RoutePlanning,
        reports: ReportQueue,
        store: ActiveRideStore?,
        options: RideOptions,
        settings: AppSettings = .shared,
        audio: PromptAudio = PromptAudio(),
        trip: TripRecorder? = nil,
        activity: RideActivityPresenting? = nil,
        watch: RideWatchPresenting? = nil,
        scooterStatus: @escaping @MainActor () -> ScooterRideStatus? = { nil }
    ) {
        self.plan = plan
        self.ride = ride
        destination = ride.destination
        verifiedOnly = ride.verifiedOnly
        avoid = ride.avoid
        language = ride.language
        remainingStops = ride.stops
        self.options = options
        self.reports = reports
        self.store = store
        self.trip = trip
        self.activity = activity
        self.watch = watch
        self.planner = planner
        self.settings = settings
        speeding = SpeedingMonitor(toleranceKmh: settings.speedingToleranceKmh)
        editFailuresToSimulate = options.simulatedEditFailures
        geometry = RouteGeometry(route: plan.route)
        spans = UnverifiedWarnings.spans(stretches: plan.meta.stretches, geometry: geometry)
        trim = RouteTrim.split(geometry: geometry, stretches: plan.meta.stretches, atM: 0)
        scooterMonitor = ScooterRideMonitor(start: geometry.points.first)
        self.scooterStatus = scooterStatus
        book.store(plan)

        let locationProvider: LocationProviding
        if options.simulate {
            let simulator = RideSimulator(speedKmh: options.simulatedSpeedKmh, tickInterval: options.tickInterval)
            self.simulator = simulator
            locationProvider = simulator
        } else {
            simulator = nil
            locationProvider = RideLocationProvider()
        }

        var record: (SpeechDecision) -> Void = { _ in }
        let rideLanguage = ride.language
        let synthesizer = GuidanceSpeechSynthesizer(
            language: rideLanguage,
            settings: { settings.speechSettings(for: rideLanguage) },
            audio: audio
        ) { decision in record(decision) }
        speech = synthesizer
        let provider = NaviscootRouteProvider(
            planner: planner,
            verifiedOnly: verifiedOnly,
            avoid: avoid,
            language: language,
            book: book,
            simulatedFailures: options.simulatedRerouteFailures
        )
        core = FerrostarCore(
            customRouteProvider: provider,
            locationProvider: locationProvider,
            navigationControllerConfig: RideOptions.navigationConfig,
            spokenInstructionObserver: SpokenInstructionObserver(synthesizer: synthesizer, isMuted: false, managesAudioSession: false)
        )
        // Ferrostar only retries a failed reroute after the rider moved 50 m; a rider who stopped would never get one.
        core.minimumMovementBeforeRecalculation = 0
        provider.onOutcome = { [weak self] outcome in
            DispatchQueue.main.async { self?.rerouteTrouble.record(outcome) }
        }
        record = { [weak self] decision in
            DispatchQueue.main.async {
                guard let self else { return }
                self.speechDecisions = Array((self.speechDecisions + [decision]).suffix(200))
                if decision.spoken {
                    self.spoken = Array((self.spoken + [decision.line]).suffix(200))
                    if UIApplication.shared.applicationState == .background {
                        self.activityStats.backgroundSpoken += 1
                    }
                }
            }
        }
        core.delegate = navigationDelegate
        navigationDelegate.onReroute = { [weak self] route in self?.acceptReroute(route) }

        core.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.handle(state) }
            .store(in: &cancellables)
    }

    var routeId: String { plan.meta.routeId }
    var activityStatus: String { activity?.status ?? "activity=none" }
    var nextStop: Destination? { remainingStops.first }
    var canEdit: Bool { !arrived }

    var remainingRoute: [Coordinate] {
        RideCamera.remainingRoute(points: geometry.points, from: shapeIndex, user: userCoordinate)
    }

    var optionsSummary: String {
        "verified_only=\(verifiedOnly) ferries=\(avoid.ferries) unpaved=\(avoid.unpaved) main_roads=\(avoid.mainRoads) language=\(language.rawValue)"
    }

    func start() {
        store?.save(ride)
        trip?.begin()
        UIApplication.shared.isIdleTimerDisabled = true
        simulator?.follow(plan.route)
        try? core.startNavigation(route: plan.route, userLocation: simulator?.lastLocation)
        startActivity()
        publishWatch()
        Task { await reports.flush() }
    }

    func end() {
        ended = true
        trip?.finish()
        editTask?.cancel()
        editStateTask?.cancel()
        store?.clear()
        core.stopNavigation()
        speech.release()
        reportStatusTask?.cancel()
        activityEnded = true
        activity?.end(nil, dismissAfter: nil)
        watchEnded = true
        watch?.send(WatchRideMessage(sentAt: Date(), state: nil), urgent: true)
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func activityUpdate(now: Date) -> RideActivityUpdate {
        RideActivityContent.update(
            banner: banner,
            arrived: arrived,
            alert: alert,
            remainingM: remainingM,
            remainingS: remainingS,
            destination: destination.title,
            now: now,
            language: settings.language,
            battery: scooter?.badge(language: settings.language)
        )
    }

    private func startActivity() {
        guard let activity else { return }
        let now = Date()
        let update = activityUpdate(now: now)
        _ = activityThrottle.shouldSend(update, now: now)
        activity.start(update.state, now: now)
        countActivityPush(update.state)
    }

    private func publishActivity() {
        guard let activity, !activityEnded else { return }
        let now = Date()
        let update = activityUpdate(now: now)
        guard activityThrottle.shouldSend(update, now: now) else { return }
        activity.update(update.state, now: now)
        countActivityPush(update.state)
    }

    private func finishActivity() {
        guard let activity, !activityEnded else { return }
        activityEnded = true
        let state = activityUpdate(now: Date()).state
        activity.end(state, dismissAfter: RideActivityStats.arrivedLingerS)
        countActivityPush(state)
    }

    private func publishWatch() {
        guard let watch, !watchEnded else { return }
        let now = Date()
        let activity = activityUpdate(now: now)
        let cue = watchCues.cue(
            maneuverKey: maneuverKey,
            symbol: activity.state.symbol,
            distanceM: banner?.distanceM,
            alertKey: alert?.key,
            arrived: arrived
        )
        let update = WatchRideContent.update(activity: activity, cue: cue, now: now)
        guard let delivery = watchThrottle.delivery(for: update, now: now) else { return }
        watch.send(update.message, urgent: delivery == .urgent)
    }

    private func countActivityPush(_ state: RideActivityAttributes.ContentState) {
        activityStats.pushes += 1
        activityStats.lastState = state
        if UIApplication.shared.applicationState == .background {
            activityStats.backgroundPushes += 1
        }
    }

    func toggleMute() {
        setVoiceMode(settings.guidanceMode.toggledMute(lastAudible: settings.lastAudibleGuidanceMode))
    }

    func setVoiceMode(_ mode: GuidanceMode) {
        settings.guidanceMode = mode
        if mode == .off { speech.stopSpeaking(at: .immediate) }
    }

    func simulateDetour() {
        simulator?.detour()
    }

    func report() {
        guard let position = lastRawLocation ?? userCoordinate else { return }
        let report = PendingReport(id: UUID(), lat: position.lat, lon: position.lon, time: Date(), routeId: routeId)
        reportStatus = .sending
        Task {
            let outcome = await reports.submit(report)
            switch outcome {
            case .sent: reportStatus = .sent
            case .queued: reportStatus = .queued(pending: reports.pending.count)
            case .rejected: reportStatus = .rejected
            }
            reportStatusTask?.cancel()
            reportStatusTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                guard !Task.isCancelled else { return }
                self?.reportStatus = nil
            }
        }
    }

    func edit(_ change: RouteEdit) {
        guard canEdit else { return }
        guard let origin = lastRawLocation ?? userCoordinate else {
            showEditState(.failed(Strings.waitingForLocation))
            return
        }
        editTask?.cancel()
        editStateTask?.cancel()
        editState = .planning
        let ride = ride
        let planner = planner
        let failSimulated = editFailuresToSimulate > 0
        if failSimulated { editFailuresToSimulate -= 1 }
        editTask = Task { [weak self] in
            do {
                if failSimulated { throw URLError(.cannotConnectToHost) }
                let edited = try await change.plan(for: ride, from: origin, planner: planner)
                guard !Task.isCancelled, let self else { return }
                guard !self.ended, !self.arrived else {
                    self.editState = nil
                    return
                }
                if edited.ride.stops.count > change.applied(to: self.ride).stops.count {
                    self.editState = nil
                    self.edit(change)
                    return
                }
                self.apply(edited.plan, ride: edited.ride)
                self.editState = nil
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.showEditState(.failed(Strings.message(for: error)))
            }
        }
    }

    private func showEditState(_ state: RideEditState) {
        editState = state
        editStateTask?.cancel()
        editStateTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled, self?.editState == state else { return }
            self?.editState = nil
        }
    }

    private func apply(_ newPlan: RoutePlan, ride edited: ActiveRide) {
        book.startNewGeneration()
        book.store(newPlan)
        ride = edited
        destination = edited.destination
        remainingStops = edited.stops
        store?.save(edited)
        trip?.destinationChanged(to: edited.destination.title)
        plan = newPlan
        geometry = RouteGeometry(route: newPlan.route)
        spans = UnverifiedWarnings.spans(stretches: newPlan.meta.stretches, geometry: geometry)
        trim = RouteTrim.split(geometry: geometry, stretches: newPlan.meta.stretches, atM: 0)
        announcer = WarningAnnouncer()
        alert = nil
        shapeIndex = 0
        rerouteTrouble = RerouteTrouble()
        simulator?.follow(newPlan.route)
        try? core.startNavigation(route: newPlan.route, userLocation: simulator?.lastLocation)
    }

    private func acceptReroute(_ route: Route) {
        guard !arrived, let newPlan = book.plan(for: route) else { return }
        plan = newPlan
        geometry = RouteGeometry(route: route)
        spans = UnverifiedWarnings.spans(stretches: newPlan.meta.stretches, geometry: geometry)
        trim = RouteTrim.split(geometry: geometry, stretches: newPlan.meta.stretches, atM: 0)
        shapeIndex = 0
        rerouteCount += 1
        simulator?.follow(route)
        try? core.startNavigation(route: route, userLocation: simulator?.lastLocation)
    }

    private func handle(_ state: NavigationState?) {
        guard let state else { return }
        isRerouting = state.isCalculatingNewRoute
        switch state.tripState {
        case .idle:
            return
        case let .complete(userLocation, _):
            trip?.observe(TrackFix(userLocation))
            trip?.finish()
            if !arrived { store?.clear() }
            arrived = true
            alert = nil
            scooterWarning = nil
            banner = nil
            isSpeeding = false
            trim = RouteTrim.split(geometry: geometry, stretches: plan.meta.stretches, atM: geometry.lengthM)
            userCoordinate = Coordinate(userLocation.coordinates)
            speedKmh = 0
            remainingM = 0
            remainingS = 0
            finishActivity()
            publishWatch()
        case let .navigating(stepIndex, userLocation, snapped, remainingSteps, remainingWaypoints, progress, _, deviation, visual, _, _):
            trip?.observe(TrackFix(userLocation))
            guard state.routeGeometry.count == geometry.points.count else { return }
            lastRawLocation = Coordinate(userLocation.coordinates)
            let onRoute = deviation == .noDeviation
            if onRoute, rerouteTrouble.isFailing {
                rerouteTrouble.backOnRoute()
            }
            advanceStops(remainingWaypoints: remainingWaypoints.count)
            let shown = onRoute ? snapped : userLocation
            userCoordinate = Coordinate(shown.coordinates)
            if let course = shown.courseOverGround ?? userLocation.courseOverGround {
                courseDegrees = Double(course.degrees)
            }
            speedKmh = userLocation.speed.map { Int(($0.value * 3.6).rounded()) }
            remainingM = progress.distanceRemaining
            remainingS = progress.durationRemaining

            let completed = plan.route.steps.count - remainingSteps.count
            let index = geometry.globalIndex(completedSteps: completed, stepGeometryIndex: Int(stepIndex ?? 0))
            shapeIndex = index
            let progressM = geometry.progressM(near: index, snapped: Coordinate(snapped.coordinates))
            trim = RouteTrim.split(geometry: geometry, stretches: plan.meta.stretches, atM: progressM)
            limitKmh = RouteLookup.limitKmh(atShapeIndex: index, meta: plan.meta)
            currentClass = RouteLookup.stretch(atShapeIndex: index, in: plan.meta.stretches)?.stretchClass
            checkSpeed()
            checkScooter()

            if let visual {
                banner = Banner(visual: visual, distanceM: progress.distanceToNextManeuver, remainingSteps: remainingSteps)
                maneuverKey = "\(routeId)#\(completed)"
            }

            let next = UnverifiedWarnings.alert(progressM: progressM, spans: spans)
            alert = next
            if let next, announcer.shouldAnnounce(next) {
                announce(SpokenPhrases.announcement(for: next, language: language), kind: .warning)
            }
            publishActivity()
            publishWatch()
        }
    }

    private func advanceStops(remainingWaypoints: Int) {
        let left = max(0, remainingWaypoints - 1)
        guard left < remainingStops.count else { return }
        let reached = remainingStops[remainingStops.count - left - 1]
        remainingStops = Array(remainingStops.suffix(left))
        ride.stops = remainingStops
        store?.save(ride)
        trip?.reachedStop(reached.title)
        announce(SpokenPhrases.stopReached(reached, next: nextStop, destination: destination, language: language), kind: .instruction)
    }

    private func checkSpeed() {
        speeding.toleranceKmh = settings.speedingToleranceKmh
        let alertNow = speeding.update(speedKmh: speedKmh, limitKmh: limitKmh)
        isSpeeding = speeding.isOver
        guard alertNow, let limitKmh else { return }
        speedingEpisodes += 1
        if settings.speedingAlert {
            announce(SpokenPhrases.speeding(limitKmh: limitKmh, language: language), kind: .speeding)
        }
    }

    private func checkScooter() {
        scooter = scooterStatus()
        let evaluation = scooterMonitor.evaluate(
            status: scooter,
            position: lastRawLocation,
            remainingKm: remainingM.map { $0 / 1000 },
            marginPercent: settings.rangeMarginPercent,
            turnBackEnabled: settings.turnBackWarning
        )
        scooterWarning = evaluation.shown
        if let fresh = evaluation.announce {
            announce(fresh.speech(language: language), kind: .warning)
        }
    }

    private func announce(_ text: String, kind: SpeechKind) {
        speech.announce(text, kind: kind)
    }
}

struct RideActivityStats: Equatable {
    static let arrivedLingerS: TimeInterval = 300

    var pushes = 0
    var backgroundPushes = 0
    var backgroundSpoken = 0
    var lastState: RideActivityAttributes.ContentState?
}
