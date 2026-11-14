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
    @Published private(set) var isMuted = false
    @Published private(set) var reportStatus: ReportStatus?
    @Published private(set) var spoken: [SpokenLine] = []

    let destination: Destination
    let verifiedOnly: Bool
    let options: RideOptions
    private let reports: ReportQueue
    private let book = PlanBook()
    private let navigationDelegate = RideNavigationDelegate()
    private let simulator: RideSimulator?
    private let core: FerrostarCore
    private var geometry: RouteGeometry
    private var spans: [UnverifiedSpan]
    private var announcer = WarningAnnouncer()
    private var lastRawLocation: Coordinate?
    private var cancellables = Set<AnyCancellable>()
    private var reportStatusTask: Task<Void, Never>?

    init(plan: RoutePlan, destination: Destination, verifiedOnly: Bool, planner: RoutePlanning, reports: ReportQueue, options: RideOptions) {
        self.plan = plan
        self.destination = destination
        self.verifiedOnly = verifiedOnly
        self.options = options
        self.reports = reports
        geometry = RouteGeometry(route: plan.route)
        spans = UnverifiedWarnings.spans(stretches: plan.meta.stretches, geometry: geometry)
        book.store(plan)

        let locationProvider: LocationProviding
        if options.simulate {
            let simulator = RideSimulator(speedKmh: options.simulatedSpeedKmh, tickInterval: options.tickInterval)
            self.simulator = simulator
            locationProvider = simulator
        } else {
            simulator = nil
            locationProvider = CoreLocationProvider(activityType: .otherNavigation, allowBackgroundLocationUpdates: true)
        }

        var record: (SpokenLine) -> Void = { _ in }
        let synthesizer = DutchSpeechSynthesizer { line in record(line) }
        core = FerrostarCore(
            customRouteProvider: NaviscootRouteProvider(planner: planner, verifiedOnly: verifiedOnly, book: book),
            locationProvider: locationProvider,
            navigationControllerConfig: RideOptions.navigationConfig,
            spokenInstructionObserver: SpokenInstructionObserver(synthesizer: synthesizer, isMuted: false)
        )
        record = { [weak self] line in
            DispatchQueue.main.async {
                guard let self else { return }
                self.spoken = Array((self.spoken + [line]).suffix(200))
            }
        }
        core.delegate = navigationDelegate
        navigationDelegate.onReroute = { [weak self] route in self?.acceptReroute(route) }

        core.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.handle(state) }
            .store(in: &cancellables)
        core.spokenInstructionObserver.$isMuted
            .receive(on: DispatchQueue.main)
            .sink { [weak self] muted in self?.isMuted = muted }
            .store(in: &cancellables)
    }

    var routeId: String { plan.meta.routeId }

    func start() {
        UIApplication.shared.isIdleTimerDisabled = true
        simulator?.follow(plan.route)
        try? core.startNavigation(route: plan.route, userLocation: simulator?.lastLocation)
        Task { await reports.flush() }
    }

    func end() {
        core.stopNavigation()
        reportStatusTask?.cancel()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func toggleMute() {
        core.spokenInstructionObserver.toggleMute()
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

    private func acceptReroute(_ route: Route) {
        guard !arrived, let newPlan = book.plan(for: route) else { return }
        plan = newPlan
        geometry = RouteGeometry(route: route)
        spans = UnverifiedWarnings.spans(stretches: newPlan.meta.stretches, geometry: geometry)
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
            arrived = true
            alert = nil
            banner = nil
            userCoordinate = Coordinate(userLocation.coordinates)
            speedKmh = 0
            remainingM = 0
            remainingS = 0
        case let .navigating(stepIndex, userLocation, snapped, remainingSteps, _, progress, _, deviation, visual, _, _):
            guard state.routeGeometry.count == geometry.points.count else { return }
            lastRawLocation = Coordinate(userLocation.coordinates)
            let onRoute = deviation == .noDeviation
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
            let progressM = geometry.progressM(near: index, snapped: Coordinate(snapped.coordinates))
            limitKmh = RouteLookup.limitKmh(atShapeIndex: index, meta: plan.meta)
            currentClass = RouteLookup.stretch(atShapeIndex: index, in: plan.meta.stretches)?.stretchClass

            if let visual {
                banner = Banner(
                    distanceM: progress.distanceToNextManeuver,
                    text: visual.primaryContent.text,
                    maneuverType: visual.primaryContent.maneuverType,
                    maneuverModifier: visual.primaryContent.maneuverModifier
                )
            }

            let next = UnverifiedWarnings.alert(progressM: progressM, spans: spans)
            alert = next
            if let next, announcer.shouldAnnounce(next) {
                core.spokenInstructionObserver.spokenInstructionTriggered(SpokenInstruction(
                    text: Dutch.announcement(for: next),
                    ssml: nil,
                    triggerDistanceBeforeManeuver: 0,
                    utteranceId: UUID()
                ))
            }
        }
    }
}
