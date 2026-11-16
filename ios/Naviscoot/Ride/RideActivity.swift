import ActivityKit
import Foundation

struct RideActivityUpdate: Equatable {
    let state: RideActivityAttributes.ContentState
    let milestone: String
}

enum RideActivityContent {
    static func update(
        banner: RideModel.Banner?,
        arrived: Bool,
        alert: UnverifiedAlert?,
        remainingM: Double?,
        remainingS: Double?,
        destination: String,
        now: Date,
        language: Language,
        battery: String? = nil
    ) -> RideActivityUpdate {
        let street: String
        let distance: String
        if arrived {
            street = Strings.tr("ride.arrived", language: language)
            distance = ""
        } else if let banner {
            street = banner.text
            distance = Format.approximateDistance(meters: banner.distanceM, language: language)
        } else {
            street = destination
            distance = ""
        }
        let state = RideActivityAttributes.ContentState(
            symbol: RideView.symbol(for: banner, arrived: arrived),
            distance: distance,
            street: street,
            destination: destination,
            arrivalLabel: Strings.tr("activity.arrival", language: language),
            arrival: remainingS.map { Format.clockTime(now.addingTimeInterval($0), language: language) } ?? "–",
            remaining: remainingM.map { Format.distance(meters: Int($0.rounded()), language: language) } ?? "–",
            warning: arrived ? nil : alert.map { warningText($0, language: language) },
            arrived: arrived,
            battery: arrived ? nil : battery
        )
        let warningKind = switch alert {
        case let .ahead(key, _, _): "ahead:\(key)"
        case let .inside(key, _): "inside:\(key)"
        case nil: "none"
        }
        let milestone = [state.symbol, state.street, destination, arrived ? "arrived" : "riding", arrived ? "none" : warningKind, language.rawValue]
            .joined(separator: "|")
        return RideActivityUpdate(state: state, milestone: milestone)
    }

    static func warningText(_ alert: UnverifiedAlert, language: Language) -> String {
        switch alert {
        case let .ahead(_, distanceM, lengthM):
            Strings.unverifiedAhead(
                Format.approximateDistance(meters: distanceM, language: language),
                length: Format.distance(meters: lengthM, language: language),
                language: language
            )
        case let .inside(_, remainingM):
            Strings.unverifiedInside(Format.approximateDistance(meters: remainingM, language: language), language: language)
        }
    }
}

struct ActivityThrottle {
    static let minimumInterval: TimeInterval = 5
    static let heartbeat: TimeInterval = 60
    static let staleAfter: TimeInterval = 150

    private(set) var last: (update: RideActivityUpdate, at: Date)?

    mutating func shouldSend(_ update: RideActivityUpdate, now: Date) -> Bool {
        guard let last else { return record(update, now) }
        if update.milestone != last.update.milestone { return record(update, now) }
        let elapsed = now.timeIntervalSince(last.at)
        if elapsed >= Self.heartbeat { return record(update, now) }
        if elapsed >= Self.minimumInterval, update.state != last.update.state { return record(update, now) }
        return false
    }

    mutating func reset() {
        last = nil
    }

    private mutating func record(_ update: RideActivityUpdate, _ now: Date) -> Bool {
        last = (update, now)
        return true
    }
}

@MainActor
protocol RideActivityPresenting: AnyObject {
    var status: String { get }
    func start(_ state: RideActivityAttributes.ContentState, now: Date)
    func update(_ state: RideActivityAttributes.ContentState, now: Date)
    func end(_ state: RideActivityAttributes.ContentState?, dismissAfter: TimeInterval?)
}

@MainActor
final class RideLiveActivity: RideActivityPresenting {
    private var activity: Activity<RideActivityAttributes>?
    private var queue: Task<Void, Never>?
    private var outcome = "none"

    var status: String {
        let system = activity.map { "\($0.activityState)" } ?? "none"
        return "activity=\(outcome) system=\(system) live=\(Activity<RideActivityAttributes>.activities.count)"
    }

    func start(_ state: RideActivityAttributes.ContentState, now: Date) {
        Self.endAll()
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            outcome = "disabled"
            return
        }
        do {
            activity = try Activity.request(
                attributes: RideActivityAttributes(),
                content: ActivityContent(state: state, staleDate: now.addingTimeInterval(ActivityThrottle.staleAfter)),
                pushType: nil
            )
            outcome = "active"
        } catch {
            outcome = "failed"
        }
    }

    func update(_ state: RideActivityAttributes.ContentState, now: Date) {
        guard let activity else { return }
        let content = ActivityContent(state: state, staleDate: now.addingTimeInterval(ActivityThrottle.staleAfter))
        enqueue { await activity.update(content) }
    }

    func end(_ state: RideActivityAttributes.ContentState?, dismissAfter: TimeInterval?) {
        guard let activity else { return }
        if dismissAfter == nil { self.activity = nil }
        outcome = "ended"
        let content = state.map { ActivityContent(state: $0, staleDate: nil) }
        let policy: ActivityUIDismissalPolicy = dismissAfter.map { .after(Date().addingTimeInterval($0)) } ?? .immediate
        enqueue { await activity.end(content, dismissalPolicy: policy) }
    }

    // A killed app leaves its activity on the lock screen; nothing else will ever end it.
    static func endAll() {
        for activity in Activity<RideActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    private func enqueue(_ work: @escaping @Sendable () async -> Void) {
        let previous = queue
        queue = Task {
            await previous?.value
            await work()
        }
    }
}
