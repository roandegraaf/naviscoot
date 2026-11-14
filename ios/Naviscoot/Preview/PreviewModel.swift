import Foundation

@MainActor
final class PreviewModel: ObservableObject {
    enum State {
        case waitingForLocation
        case loading
        case loaded(RoutePlan)
        case failed(String)
    }

    let destination: Destination
    @Published private(set) var state: State = .waitingForLocation
    @Published var verifiedOnly = false {
        didSet {
            if verifiedOnly != oldValue { reload() }
        }
    }

    @Published private(set) var defaultUnverifiedM: Int?
    private let client: NaviscootClient?
    private var origin: Coordinate?
    private var task: Task<Void, Never>?

    init(destination: Destination, client: NaviscootClient?) {
        self.destination = destination
        self.client = client
    }

    func originChanged(_ coordinate: Coordinate?) {
        guard origin == nil, let coordinate else { return }
        origin = coordinate
        reload()
    }

    func reload() {
        guard let client else {
            state = .failed(Strings.apiNotConfigured)
            return
        }
        guard let origin else {
            state = .waitingForLocation
            return
        }
        task?.cancel()
        state = .loading
        let verifiedOnly = verifiedOnly
        let destination = destination.coordinate
        task = Task { [weak self] in
            do {
                let plan = try await client.route(from: origin, to: destination, verifiedOnly: verifiedOnly)
                guard !Task.isCancelled, let self else { return }
                if !verifiedOnly { self.defaultUnverifiedM = plan.meta.totalsM.unverified }
                self.state = .loaded(plan)
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.state = .failed(Strings.message(for: error))
            }
        }
    }
}
