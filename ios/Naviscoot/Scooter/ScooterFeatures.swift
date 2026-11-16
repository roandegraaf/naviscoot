import Foundation

// Bit polarity was matched against the Segway app's own switches on an E110S: detection and indicator sound store "on" as a cleared bit.
struct ScooterFeature: Equatable, Identifiable {
    enum ID: String, CaseIterable {
        case seatDetection
        case parkingDetection
        case assistMode
        case reverse
        case showRange
        case extendedRange
        case streamlineTaillight
        case indicatorAutoOff
        case indicatorSound
    }

    let id: ID
    let register: NinebotRegister
    let mask: Int
    let inverted: Bool

    func isOn(_ registerValue: Int) -> Bool {
        (registerValue & mask != 0) != inverted
    }

    func registerValue(_ current: Int, on: Bool) -> Int {
        on != inverted ? current | mask : current & ~mask
    }

    static let all: [ScooterFeature] = [
        ScooterFeature(id: .seatDetection, register: .featureFlags, mask: 0x0200, inverted: true),
        ScooterFeature(id: .parkingDetection, register: .featureFlags, mask: 0x0100, inverted: true),
        ScooterFeature(id: .assistMode, register: .featureFlags, mask: 0x0002, inverted: false),
        ScooterFeature(id: .reverse, register: .featureFlags, mask: 0x2000, inverted: false),
        ScooterFeature(id: .showRange, register: .featureFlags, mask: 0x4000, inverted: false),
        ScooterFeature(id: .extendedRange, register: .featureFlags, mask: 0x0080, inverted: false),
        ScooterFeature(id: .streamlineTaillight, register: .featureFlags, mask: 0x0400, inverted: false),
        ScooterFeature(id: .indicatorAutoOff, register: .featureFlags, mask: 0x0800, inverted: false),
        ScooterFeature(id: .indicatorSound, register: .controlFlags, mask: 0x0008, inverted: true),
    ]

    static func feature(_ id: ID) -> ScooterFeature {
        all.first { $0.id == id }!
    }
}

// The Segway app's None / Weak / Strong map to 0x00 / 0x08 / 0x10 in the feature flags; 0x18 was never observed.
enum EnergyRecovery: Equatable, CaseIterable, Hashable {
    case off
    case weak
    case strong

    static let mask = 0x0018

    init?(registerValue: Int) {
        switch registerValue & Self.mask {
        case 0x00: self = .off
        case 0x08: self = .weak
        case 0x10: self = .strong
        default: return nil
        }
    }

    var bits: Int {
        switch self {
        case .off: 0x00
        case .weak: 0x08
        case .strong: 0x10
        }
    }

    func registerValue(_ current: Int) -> Int {
        current & ~Self.mask | bits
    }
}

enum RecoveryWrite: Equatable {
    case confirmed(EnergyRecovery)
    case mismatch(EnergyRecovery?)
    case unreadable
}

enum FeatureWrite: Equatable {
    case confirmed(Bool)
    case mismatch(Bool)
    case unreadable
}

enum ScooterFeatureControl {
    static func changeAllowed(rideActive: Bool, speedKmh: Double?) -> Bool {
        !rideActive && (speedKmh ?? 0) <= 0
    }

    static func read(from session: NinebotSession) async -> [ScooterFeature.ID: Bool] {
        var states: [ScooterFeature.ID: Bool] = [:]
        for register in [NinebotRegister.featureFlags, .controlFlags] {
            guard let value = try? await session.value(register) else { continue }
            for feature in ScooterFeature.all where feature.register == register {
                states[feature.id] = feature.isOn(value)
            }
        }
        return states
    }

    // Reads the whole flag word right before writing it, so only the one bit changes even if the Segway app changed others meanwhile.
    static func apply(
        _ feature: ScooterFeature, on: Bool, session: NinebotSession, rideActive: Bool, speedKmh: Double?, settle: Duration = .milliseconds(500)
    ) async throws -> FeatureWrite {
        guard changeAllowed(rideActive: rideActive, speedKmh: speedKmh) else { throw ScooterControlError.settingWhileRiding }
        let current = try await session.value(feature.register)
        try await session.write(feature.register, UInt16(truncatingIfNeeded: feature.registerValue(current, on: on)))
        try await Task.sleep(for: settle)
        guard let readBack = try? await session.value(feature.register) else { return .unreadable }
        let state = feature.isOn(readBack)
        return state == on ? .confirmed(state) : .mismatch(state)
    }

    static func readRecovery(from session: NinebotSession) async -> EnergyRecovery? {
        guard let value = try? await session.value(.featureFlags) else { return nil }
        return EnergyRecovery(registerValue: value)
    }

    static func apply(
        _ level: EnergyRecovery, session: NinebotSession, rideActive: Bool, speedKmh: Double?, settle: Duration = .milliseconds(500)
    ) async throws -> RecoveryWrite {
        guard changeAllowed(rideActive: rideActive, speedKmh: speedKmh) else { throw ScooterControlError.settingWhileRiding }
        let current = try await session.value(.featureFlags)
        try await session.write(.featureFlags, UInt16(truncatingIfNeeded: level.registerValue(current)))
        try await Task.sleep(for: settle)
        guard let readBack = try? await session.value(.featureFlags) else { return .unreadable }
        let state = EnergyRecovery(registerValue: readBack)
        return state == level ? .confirmed(level) : .mismatch(state)
    }
}

enum TimeZoneSync: Equatable {
    case alreadySet(minutes: Int)
    case updated(from: Int, to: Int)
    case mismatch(Int)
    case unreadable
}

// The dashboard stores its UTC offset in minutes (60 for CET); negative offsets are assumed to be two's complement, which is untested.
enum ScooterClock {
    static func offsetMinutes(_ zone: TimeZone, at date: Date) -> Int {
        zone.secondsFromGMT(for: date) / 60
    }

    static func minutes(fromRegister value: Int) -> Int {
        Int(Int16(truncatingIfNeeded: value))
    }

    static func registerValue(minutes: Int) -> UInt16 {
        UInt16(bitPattern: Int16(minutes))
    }

    static func sync(session: NinebotSession, zone: TimeZone = .current, now: Date = Date(), settle: Duration = .milliseconds(500)) async throws -> TimeZoneSync {
        let target = offsetMinutes(zone, at: now)
        guard let stored = try? await session.value(.timeZone) else { return .unreadable }
        let current = minutes(fromRegister: stored)
        guard current != target else { return .alreadySet(minutes: target) }
        try await session.write(.timeZone, registerValue(minutes: target))
        try await Task.sleep(for: settle)
        guard let readBack = try? await session.value(.timeZone) else { return .unreadable }
        let result = minutes(fromRegister: readBack)
        return result == target ? .updated(from: current, to: target) : .mismatch(result)
    }
}
