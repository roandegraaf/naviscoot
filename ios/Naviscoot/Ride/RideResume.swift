import SwiftUI

@MainActor
final class ResumeModel: ObservableObject {
    enum State: Equatable {
        case waitingForLocation
        case planning
        case failed(String)
    }

    @Published private(set) var state: State = .waitingForLocation
    let ride: ActiveRide
    var onPlanned: (RoutePlan) -> Void = { _ in }
    private let planner: RoutePlanning
    private var origin: Coordinate?
    private var task: Task<Void, Never>?

    init(ride: ActiveRide, planner: RoutePlanning) {
        self.ride = ride
        self.planner = planner
    }

    func locationChanged(_ coordinate: Coordinate?) {
        guard let coordinate else { return }
        origin = coordinate
        if state == .waitingForLocation { plan() }
    }

    func retry() {
        state = .waitingForLocation
        if origin != nil { plan() }
    }

    func cancel() {
        task?.cancel()
    }

    private func plan() {
        guard let origin else { return }
        state = .planning
        let ride = ride
        let planner = planner
        task = Task { [weak self] in
            do {
                let plan = try await planner.route(
                    from: origin,
                    to: ride.destination.coordinate,
                    stops: ride.stops.map(\.coordinate),
                    avoid: ride.avoid,
                    verifiedOnly: ride.verifiedOnly,
                    language: ride.language
                )
                guard !Task.isCancelled, let self else { return }
                self.onPlanned(plan)
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.state = .failed(Strings.message(for: error))
            }
        }
    }
}

struct ResumeView: View {
    @ObservedObject var model: ResumeModel
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Text(Strings.resumeHeading)
                .font(.system(size: 30, weight: .heavy))
                .foregroundStyle(Theme.ink)
            Text(Strings.resumeMessage(model.ride))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.muted)
            status
            Spacer()
            if case .failed = model.state {
                Button(Strings.retry, action: model.retry)
                    .font(.system(size: 20, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(Theme.line.opacity(0.4), in: Capsule())
                    .accessibilityIdentifier("resume.retry")
            }
            Button {
                model.cancel()
                onCancel()
            } label: {
                Text(Strings.endRideConfirm)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Theme.danger, in: Capsule())
            }
            .accessibilityIdentifier("resume.cancel")
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.screen.ignoresSafeArea())
    }

    @ViewBuilder
    private var status: some View {
        HStack(spacing: 12) {
            switch model.state {
            case .waitingForLocation:
                ProgressView()
                Text(Strings.waitingForLocation)
            case .planning:
                ProgressView()
                Text(Strings.resumePlanning)
            case let .failed(message):
                Text(message)
            }
        }
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(Theme.ink)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("resume.status")
    }
}
