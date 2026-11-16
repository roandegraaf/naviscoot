import Foundation

@MainActor
final class PreviewModel: ObservableObject {
    enum State {
        case waitingForLocation
        case loading
        case loaded([RoutePlan])
        case failed(String)
    }

    @Published private(set) var trip: TripPlan
    @Published private(set) var state: State = .waitingForLocation
    @Published private(set) var selectedIndex = 0
    @Published var verifiedOnly: Bool {
        didSet {
            guard verifiedOnly != oldValue else { return }
            verifiedOnlyTouched = true
            showsVerifiedOnlyToggle = true
            reload()
        }
    }

    @Published private(set) var defaultUnverifiedM: Int?
    @Published private(set) var showsVerifiedOnlyToggle: Bool
    @Published private(set) var bubbleAnchors: [Coordinate] = []
    private var verifiedOnlyTouched = false
    private let client: NaviscootClient?
    private let settings: AppSettings
    private var currentLocation: Coordinate?
    private var task: Task<Void, Never>?
    private(set) var lastRequest: TripRequest?

    init(destination: Destination, client: NaviscootClient?, settings: AppSettings) {
        trip = TripPlan(destination: destination)
        self.client = client
        self.settings = settings
        verifiedOnly = settings.verifiedOnlyByDefault
        showsVerifiedOnlyToggle = settings.verifiedOnlyByDefault
    }

    var destination: Destination { trip.destination }

    var plans: [RoutePlan] {
        if case let .loaded(plans) = state { return plans }
        return []
    }

    var selectedPlan: RoutePlan? {
        plans.indices.contains(selectedIndex) ? plans[selectedIndex] : plans.first
    }

    var canStart: Bool {
        selectedPlan != nil && trip.startsFromCurrentLocation
    }

    func rideToStart() -> ActiveRide? {
        guard canStart else { return nil }
        return ActiveRide(
            destination: destination,
            stops: trip.routableStops(currentLocation: lastRequest?.origin),
            verifiedOnly: verifiedOnly,
            avoid: settings.routeAvoid,
            language: settings.language
        )
    }

    func schedule(now: Date = Date()) -> TripSchedule? {
        selectedPlan.map { TripPlan.schedule(for: trip.time, durationS: $0.durationS, now: now) }
    }

    func originChanged(_ coordinate: Coordinate?) {
        guard currentLocation == nil, let coordinate else { return }
        currentLocation = coordinate
        if trip.startsFromCurrentLocation { reload() }
    }

    func select(_ index: Int) {
        guard plans.indices.contains(index) else { return }
        selectedIndex = index
    }

    func setStart(_ start: TripStart) {
        changeTrip { $0.start = start }
    }

    func addStop(_ stop: Destination) {
        changeTrip { $0.addStop(stop) }
    }

    func removeStop(at index: Int) {
        changeTrip { $0.removeStop(at: index) }
    }

    func moveStop(from source: Int, to destination: Int) {
        changeTrip { $0.moveStop(from: source, to: destination) }
    }

    func setTime(_ time: RouteTime?) {
        changeTrip { $0.time = time }
    }

    private func changeTrip(_ change: (inout TripPlan) -> Void) {
        var next = trip
        change(&next)
        guard next != trip else { return }
        trip = next
        defaultUnverifiedM = nil
        reload()
    }

    func reload() {
        guard let client else {
            state = .failed(Strings.apiNotConfigured)
            return
        }
        guard let request = trip.request(currentLocation: currentLocation, avoid: settings.routeAvoid) else {
            state = .waitingForLocation
            return
        }
        task?.cancel()
        state = .loading
        selectedIndex = 0
        bubbleAnchors = []
        lastRequest = request
        let verifiedOnly = verifiedOnly
        let language = settings.language
        task = Task { [weak self] in
            do {
                let plans: [RoutePlan] = if let simulated = try Self.simulatedPlans(for: request) {
                    simulated
                } else {
                    try await client.routes(
                        from: request.origin,
                        to: request.destination,
                        options: request.options,
                        verifiedOnly: verifiedOnly,
                        language: language
                    )
                }
                guard !Task.isCancelled, let self else { return }
                guard let primary = plans.first else { throw RouteParseError.noRoute }
                if !verifiedOnly { self.defaultUnverifiedM = primary.meta.totalsM.unverified }
                self.showsVerifiedOnlyToggle = VerifiedOnlyToggleRule.isShown(
                    verifiedOnly: verifiedOnly,
                    touched: self.verifiedOnlyTouched,
                    plans: plans.map(\.meta)
                )
                self.bubbleAnchors = plans.count > 1
                    ? RouteBubbles.anchors(for: plans.map { $0.route.geometry.map(Coordinate.init) })
                    : []
                self.state = .loaded(plans)
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.state = .failed(Strings.message(for: error))
            }
        }
    }

    static let simulatedRoutesLaunchKey = "NaviscootSimRoutesFile"

    private static func simulatedPlans(for request: TripRequest, defaults: UserDefaults = .standard) throws -> [RoutePlan]? {
#if DEBUG
        guard request.options.stops.isEmpty, let path = defaults.string(forKey: simulatedRoutesLaunchKey) else { return nil }
        return try RouteParser.parseAll(Data(contentsOf: URL(fileURLWithPath: path)))
#else
        return nil
#endif
    }
}
