import Foundation
import WatchConnectivity

struct WatchRideUpdate: Equatable {
    let message: WatchRideMessage
    let milestone: String
}

enum WatchRideContent {
    static func state(_ activity: RideActivityAttributes.ContentState) -> WatchRideState {
        WatchRideState(
            symbol: activity.symbol,
            distance: activity.distance,
            street: activity.street,
            arrivalLabel: activity.arrivalLabel,
            arrival: activity.arrival,
            warning: activity.warning,
            arrived: activity.arrived,
            battery: activity.battery
        )
    }

    static func update(activity: RideActivityUpdate, cue: WatchCue?, now: Date) -> WatchRideUpdate {
        WatchRideUpdate(message: WatchRideMessage(sentAt: now, state: state(activity.state), cue: cue), milestone: activity.milestone)
    }
}

// The phone sees every fix, the watch only throttled ones, so the phone decides when the wrist taps.
struct WatchCueTrigger {
    static let turnWithinM: Double = 120
    static let silentSymbols: Set<String> = ["arrow.up", "flag.checkered", "location.north.line"]

    let rideKey: String
    private var tappedManeuver: String?
    private var warnedStretches: Set<String> = []
    private var arrivedCued = false

    init(rideKey: String) {
        self.rideKey = rideKey
    }

    mutating func cue(maneuverKey: String?, symbol: String, distanceM: Double?, alertKey: String?, arrived: Bool) -> WatchCue? {
        if arrived {
            guard !arrivedCued else { return nil }
            arrivedCued = true
            return WatchCue(haptic: .arrived, key: "\(rideKey)|arrived")
        }
        if let alertKey, !warnedStretches.contains(alertKey) {
            warnedStretches.insert(alertKey)
            return WatchCue(haptic: .unverified, key: "\(rideKey)|unverified|\(alertKey)")
        }
        if let maneuverKey, let distanceM, distanceM <= Self.turnWithinM,
           !Self.silentSymbols.contains(symbol), maneuverKey != tappedManeuver {
            tappedManeuver = maneuverKey
            return WatchCue(haptic: .turn, key: "\(rideKey)|turn|\(maneuverKey)")
        }
        return nil
    }
}

struct WatchThrottle {
    enum Delivery: Equatable {
        case routine
        case urgent
    }

    static let minimumInterval: TimeInterval = 2
    static let heartbeat: TimeInterval = 30

    private(set) var last: (update: WatchRideUpdate, at: Date)?

    mutating func delivery(for update: WatchRideUpdate, now: Date) -> Delivery? {
        guard let last else { return record(update, now, .urgent) }
        if update.message.cue != nil || update.milestone != last.update.milestone { return record(update, now, .urgent) }
        let elapsed = now.timeIntervalSince(last.at)
        if elapsed >= Self.heartbeat { return record(update, now, .routine) }
        if elapsed >= Self.minimumInterval, update.message.state != last.update.message.state { return record(update, now, .routine) }
        return nil
    }

    private mutating func record(_ update: WatchRideUpdate, _ now: Date, _ delivery: Delivery) -> Delivery {
        last = (update, now)
        return delivery
    }
}

@MainActor
protocol RideWatchPresenting: AnyObject {
    func send(_ message: WatchRideMessage, urgent: Bool)
}

@MainActor
final class PhoneWatchLink: NSObject, RideWatchPresenting {
    static let shared = PhoneWatchLink()

    private var pending: (message: WatchRideMessage, urgent: Bool)?

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.delegate == nil else { return }
        session.delegate = self
        session.activate()
    }

    func clear() {
        send(WatchRideMessage(sentAt: Date(), state: nil), urgent: true)
    }

    func send(_ message: WatchRideMessage, urgent: Bool) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            pending = (message, urgent || pending?.urgent == true)
            return
        }
        deliver(message, urgent: urgent, over: session)
    }

    private func deliver(_ message: WatchRideMessage, urgent: Bool, over session: WCSession) {
        guard session.isPaired, session.isWatchAppInstalled, let payload = try? message.payload() else { return }
        try? session.updateApplicationContext(payload)
        if urgent, session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
    }

    private func flushPending() {
        guard let pending else { return }
        self.pending = nil
        send(pending.message, urgent: pending.urgent)
    }
}

extension PhoneWatchLink: WCSessionDelegate {
    nonisolated func session(_: WCSession, activationDidCompleteWith _: WCSessionActivationState, error _: Error?) {
        Task { @MainActor in self.flushPending() }
    }

    nonisolated func sessionDidBecomeInactive(_: WCSession) {}

    // A watch switch deactivates the session; activating again connects to the newly paired watch.
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
