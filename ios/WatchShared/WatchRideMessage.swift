import Foundation

// The phone resolves every text in the rider's language; the watch only lays it out.
struct WatchRideState: Codable, Equatable {
    var symbol: String
    var distance: String
    var street: String
    var arrivalLabel: String
    var arrival: String
    var warning: String?
    var arrived: Bool
    var battery: String? = nil
}

enum WatchHaptic: String, Codable {
    case turn
    case unverified
    case arrived
}

struct WatchCue: Codable, Equatable {
    var haptic: WatchHaptic
    var key: String
}

struct WatchRideMessage: Codable, Equatable {
    static let payloadKey = "ride"
    static let staleAfter: TimeInterval = 150

    var sentAt: Date
    var state: WatchRideState?
    var cue: WatchCue?

    func payload() throws -> [String: Any] {
        [Self.payloadKey: try JSONEncoder().encode(self)]
    }

    init(sentAt: Date, state: WatchRideState?, cue: WatchCue? = nil) {
        self.sentAt = sentAt
        self.state = state
        self.cue = cue
    }

    init?(payload: [String: Any]) {
        guard let data = payload[Self.payloadKey] as? Data,
              let message = try? JSONDecoder().decode(Self.self, from: data) else { return nil }
        self = message
    }

    func isStale(now: Date) -> Bool {
        now.timeIntervalSince(sentAt) > Self.staleAfter
    }
}

// The same message can arrive twice (application context and sendMessage), out of order, or replayed at a cold launch.
struct WatchInbox {
    static let cueMaxAge: TimeInterval = 10
    static let rememberedCues = 50

    private(set) var latest: WatchRideMessage?
    private var played: [String] = []

    mutating func receive(_ message: WatchRideMessage, now: Date) -> WatchHaptic? {
        if latest.map({ message.sentAt >= $0.sentAt }) ?? true {
            latest = message
        }
        guard let cue = message.cue,
              now.timeIntervalSince(message.sentAt) <= Self.cueMaxAge,
              !played.contains(cue.key) else { return nil }
        played = Array((played + [cue.key]).suffix(Self.rememberedCues))
        return cue.haptic
    }
}
