import Foundation

struct ScooterRideStatus: Equatable {
    static let freshForS: TimeInterval = 120

    let batteryPercent: Int
    let rangeKm: Double

    static func current(telemetry: ScooterTelemetry?, readAt: Date?, connected: Bool, now: Date, model: ConsumptionModel) -> ScooterRideStatus? {
        guard connected, let telemetry, let readAt, now.timeIntervalSince(readAt) < freshForS else { return nil }
        return ScooterRideStatus(batteryPercent: telemetry.batteryPercent, rangeKm: model.rangeKm(for: telemetry))
    }

    func badge(language: Language = .current) -> String {
        Strings.scooterRideBattery(batteryPercent, "\(Int(max(0, rangeKm).rounded())) km", language: language)
    }
}

enum ScooterRideWarning: Equatable {
    case lowRange
    case turnBack

    func text(language: Language = .current) -> String {
        switch self {
        case .lowRange: Strings.tr("scooter.ride.lowRange", language: language)
        case .turnBack: Strings.tr("scooter.ride.turnBack", language: language)
        }
    }

    func speech(language: Language) -> String {
        switch self {
        case .lowRange: Strings.tr("scooter.ride.lowRange.speech", language: language)
        case .turnBack: Strings.tr("scooter.ride.turnBack.speech", language: language)
        }
    }
}

struct ScooterRideMonitor {
    // Roads home are longer than the crow flies; 1.3 is a common road-to-straight-line ratio.
    static let returnDetourFactor = 1.3
    static let turnBackAfterKm = 1.0

    struct Evaluation: Equatable {
        var shown: ScooterRideWarning?
        var announce: ScooterRideWarning?
    }

    let start: Coordinate?
    private var announced: Set<ScooterRideWarning> = []

    init(start: Coordinate?) {
        self.start = start
    }

    mutating func evaluate(status: ScooterRideStatus?, position: Coordinate?, remainingKm: Double?, marginPercent: Int, turnBackEnabled: Bool) -> Evaluation {
        guard let status else { return Evaluation() }
        var active: [ScooterRideWarning] = []
        if let remainingKm, status.rangeKm < remainingKm * (1 + Double(marginPercent) / 100) {
            active.append(.lowRange)
        }
        if turnBackEnabled, let start, let position {
            let awayKm = Geo.distanceM(start, position) / 1000
            if awayKm > Self.turnBackAfterKm,
               ReturnCheck.mustTurnBack(rangeKm: status.rangeKm, returnKm: awayKm * Self.returnDetourFactor, marginPercent: marginPercent) {
                active.append(.turnBack)
            }
        }
        let fresh = active.first { !announced.contains($0) }
        if let fresh { announced.insert(fresh) }
        return Evaluation(shown: active.first, announce: fresh)
    }
}
