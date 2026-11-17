import Foundation

struct ScooterTripSample: Codable, Hashable {
    let distanceKm: Double
    let batteryUsedPercent: Int

    var kmPerPercent: Double? {
        batteryUsedPercent >= ConsumptionModel.minimumDropPercent ? distanceKm / Double(batteryUsedPercent) : nil
    }
}

struct ConsumptionModel: Equatable {
    static let minimumDropPercent = 5
    static let minimumPooledPercent = 20

    let kmPerPercent: Double?

    // Pooled as total km over total percent: short trips carry 1 % rounding noise, so they're skipped and weighted by size.
    init(samples: [ScooterTripSample]) {
        let usable = samples.filter { $0.batteryUsedPercent >= Self.minimumDropPercent && $0.distanceKm > 0 }
        let percent = usable.reduce(0) { $0 + $1.batteryUsedPercent }
        let distance = usable.reduce(0) { $0 + $1.distanceKm }
        kmPerPercent = percent >= Self.minimumPooledPercent ? distance / Double(percent) : nil
    }

    var isLearned: Bool { kmPerPercent != nil }

    func rangeKm(for telemetry: ScooterTelemetry) -> Double {
        guard let kmPerPercent else { return telemetry.rangeKm }
        return Double(max(0, telemetry.batteryPercent)) * kmPerPercent
    }
}

enum RangeVerdict: Equatable {
    case fits(spareKm: Double)
    case tight(spareKm: Double)
    case short(missingKm: Double)

    static func judge(routeKm: Double, rangeKm: Double, marginPercent: Int) -> RangeVerdict {
        guard routeKm <= rangeKm else { return .short(missingKm: routeKm - rangeKm) }
        let spare = rangeKm - routeKm
        return routeKm > rangeKm * (1 - Double(marginPercent) / 100) ? .tight(spareKm: spare) : .fits(spareKm: spare)
    }
}

enum ReturnCheck {
    static func mustTurnBack(rangeKm: Double, returnKm: Double, marginPercent: Int) -> Bool {
        rangeKm < returnKm * (1 + Double(marginPercent) / 100)
    }
}
