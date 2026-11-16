import Foundation

struct RangeCheck: Equatable {
    static let staleAfterS: TimeInterval = 10 * 60

    let batteryPercent: Int
    let rangeKm: Double
    let learned: Bool
    let oneWay: RangeVerdict
    let roundTrip: RangeVerdict
    let readAgoS: TimeInterval?

    init?(routeM: Int, telemetry: ScooterTelemetry?, readAt: Date?, now: Date, model: ConsumptionModel, marginPercent: Int) {
        guard let telemetry else { return nil }
        let routeKm = Double(routeM) / 1000
        batteryPercent = telemetry.batteryPercent
        rangeKm = model.rangeKm(for: telemetry)
        learned = model.isLearned
        oneWay = RangeVerdict.judge(routeKm: routeKm, rangeKm: rangeKm, marginPercent: marginPercent)
        roundTrip = RangeVerdict.judge(routeKm: routeKm * 2, rangeKm: rangeKm, marginPercent: marginPercent)
        let age = readAt.map { now.timeIntervalSince($0) } ?? 0
        readAgoS = age >= Self.staleAfterS ? age : nil
    }

    var headline: String {
        switch oneWay {
        case let .fits(spareKm): Strings.rangeFits(Self.distance(spareKm))
        case let .tight(spareKm): Strings.rangeTight(Self.distance(spareKm))
        case let .short(missingKm): Strings.rangeShort(Self.distance(missingKm))
        }
    }

    var roundTripText: String {
        switch roundTrip {
        case .fits: Strings.rangeRoundTripFits
        case .tight: Strings.rangeRoundTripTight
        case .short: Strings.rangeRoundTripShort
        }
    }

    var detail: String {
        let source = learned ? Strings.rangeSourceLearned : Strings.rangeSourceSegway
        let parts = [Strings.rangeBattery(batteryPercent, Self.distance(rangeKm), source)] + (readAgoS.map { [Strings.rangeReadAgo(Format.duration(seconds: $0))] } ?? [])
        return parts.joined(separator: " · ")
    }

    private static func distance(_ km: Double) -> String {
        Format.approximateDistance(meters: max(0, km) * 1000)
    }
}
