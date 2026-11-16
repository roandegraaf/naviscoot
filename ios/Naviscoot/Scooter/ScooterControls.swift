import Foundation
import UserNotifications

// Layout decoded from a register dump of an E110S pack (board 0x07); the manufacture date encoding is an educated guess.
struct BatteryReport: Equatable {
    var serial: String?
    var firmware: String?
    var designCapacityAh: Double?
    var fullCapacityAh: Double?
    var cycles: Int?
    var chargeCount: Int?
    var manufactured: DateComponents?
    var statusFlags: Int?
    var remainingAh: Double?
    var chargePercent: Double?
    var currentA: Double?
    var voltage: Double?
    var temperaturesC: [Int] = []
    var cellsMv: [Int] = []

    static let chargingCurrentA = -0.05

    var healthPercent: Double? {
        guard let fullCapacityAh, let designCapacityAh, designCapacityAh > 0 else { return nil }
        return fullCapacityAh / designCapacityAh * 100
    }

    var isCharging: Bool? {
        currentA.map { $0 <= Self.chargingCurrentA }
    }

    var cellSpreadMv: Int? {
        guard let low = cellsMv.min(), let high = cellsMv.max() else { return nil }
        return high - low
    }

    func estimatedTime(reaching targetPercent: Int, from now: Date) -> Date? {
        guard let currentA, currentA <= Self.chargingCurrentA, let fullCapacityAh, let remainingAh else { return nil }
        let missingAh = fullCapacityAh * Double(targetPercent) / 100 - remainingAh
        guard missingAh > 0 else { return now }
        return now.addingTimeInterval(missingAh / -currentA * 3600)
    }

    static func read(from session: NinebotSession) async -> BatteryReport {
        let info = try? await session.read(.packInfo)
        let date = try? await session.read(.packManufactureDate)
        let live = try? await session.read(.packLive)
        let cells = try? await session.read(.packCells)
        return parse(info: info, date: date, live: live, cells: cells)
    }

    static func parse(info: [UInt8]?, date: [UInt8]?, live: [UInt8]?, cells: [UInt8]?) -> BatteryReport {
        var report = BatteryReport()
        if let info, info.count >= 26 {
            let serial = String(decoding: info[0 ..< 14].filter { $0 >= 0x20 && $0 < 0x7F }, as: UTF8.self)
            report.serial = serial.isEmpty ? nil : serial
            let version = word(info, 7)
            report.firmware = "\(version >> 8).\((version >> 4) & 0xF).\(version & 0xF)"
            report.designCapacityAh = Double(word(info, 8)) / 100
            report.fullCapacityAh = Double(word(info, 9)) / 100
            report.cycles = word(info, 11)
            report.chargeCount = word(info, 12)
        }
        if let date, date.count >= 2 {
            let value = word(date, 0)
            let components = DateComponents(year: 2000 + (value >> 9), month: (value >> 5) & 0xF, day: value & 0x1F)
            if (1 ... 12).contains(components.month ?? 0), (1 ... 31).contains(components.day ?? 0) { report.manufactured = components }
        }
        if let live, live.count >= 16 {
            report.statusFlags = word(live, 0)
            report.remainingAh = Double(word(live, 1)) / 100
            report.chargePercent = Double(word(live, 2)) / 10
            report.currentA = Double(Int16(truncatingIfNeeded: word(live, 3))) / 100
            report.voltage = Double(word(live, 4)) / 100
            report.temperaturesC = live[12 ..< 16].map { Int($0) - 20 }
        }
        if let cells, cells.count >= 26 {
            report.cellsMv = (0 ..< 13).map { word(cells, $0) }.filter { $0 > 0 }
        }
        return report
    }

    private static func word(_ bytes: [UInt8], _ index: Int) -> Int {
        Int(bytes[index * 2]) | Int(bytes[index * 2 + 1]) << 8
    }
}

// The E110S reports 65535 for "time to full" even while charging; this is the fallback for when the pack current doesn't answer.
struct ChargeTracker: Equatable {
    struct Sample: Equatable {
        let at: Date
        let percent: Double
    }

    static let window: TimeInterval = 600
    static let minimumRise = 0.2

    private(set) var samples: [Sample] = []

    mutating func record(_ percent: Double, at date: Date) {
        if let last = samples.last, percent < last.percent - 0.1 { samples = [] }
        samples.append(Sample(at: date, percent: percent))
        samples.removeAll { date.timeIntervalSince($0.at) > Self.window }
    }

    var isCharging: Bool {
        guard let first = samples.first, let last = samples.last else { return false }
        return last.percent - first.percent >= Self.minimumRise - 1e-9
    }

    var ratePerHour: Double? {
        guard isCharging, let first = samples.first, let last = samples.last else { return nil }
        let hours = last.at.timeIntervalSince(first.at) / 3600
        return hours > 0 ? (last.percent - first.percent) / hours : nil
    }

    func estimatedTime(reaching target: Double) -> Date? {
        guard let rate = ratePerHour, rate > 0, let last = samples.last else { return nil }
        guard last.percent < target else { return last.at }
        return last.at.addingTimeInterval((target - last.percent) / rate * 3600)
    }
}

struct ChargeAlert: Equatable {
    var target: Int
    private var armed = false

    init(target: Int) {
        self.target = target
    }

    // Only a crossing counts, so opening the app on an already full scooter doesn't notify.
    mutating func observe(_ percent: Int) -> Bool {
        if percent < target {
            armed = true
            return false
        }
        guard armed else { return false }
        armed = false
        return true
    }
}

@MainActor
final class ChargeNotifier {
    static let shared = ChargeNotifier(settings: .shared)

    private let settings: AppSettings
    private var alert: ChargeAlert

    init(settings: AppSettings) {
        self.settings = settings
        alert = ChargeAlert(target: settings.chargeNotifyTarget)
    }

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func observe(_ percent: Int) {
        if alert.target != settings.chargeNotifyTarget { alert = ChargeAlert(target: settings.chargeNotifyTarget) }
        guard alert.observe(percent), settings.chargeNotify else { return }
        let content = UNMutableNotificationContent()
        content.title = Strings.scooterChargedTitle
        content.body = Strings.scooterChargedBody(percent)
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "scooter.charged", content: content, trigger: nil))
    }
}

enum ScooterControlError: Error, Equatable {
    case limitOutOfRange
    case powerOffWhileRiding
    case settingWhileRiding
}

enum SpeedLimitWrite: Equatable {
    case confirmed(Int)
    case mismatch(Int)
    case unreadable
}

enum SpeedLimitControl {
    static let lowestLimit = 15

    static func ratedKmh(fromRegister value: Int) -> Int { value / 10 }

    static func choices(ratedKmh: Int) -> [Int] {
        [0] + Array(lowestLimit ... max(lowestLimit, ratedKmh))
    }

    static func isAllowed(_ limit: Int, ratedKmh: Int) -> Bool {
        limit == 0 || (lowestLimit ... max(lowestLimit, ratedKmh)).contains(limit)
    }

    // Returns the value to keep as "original": the first value read before Naviscoot ever wrote the limit.
    static func apply(
        _ limit: Int, ratedKmh: Int, original: Int?, session: NinebotSession, settle: Duration = .milliseconds(500)
    ) async throws -> (result: SpeedLimitWrite, original: Int?) {
        guard isAllowed(limit, ratedKmh: ratedKmh) else { throw ScooterControlError.limitOutOfRange }
        let kept: Int?
        if let original {
            kept = original
        } else {
            kept = try? await session.value(.speedLimit)
        }
        try await session.write(.speedLimit, UInt16(limit))
        try await Task.sleep(for: settle)
        guard let readBack = try? await session.value(.speedLimit) else { return (.unreadable, kept) }
        return (readBack == limit ? .confirmed(readBack) : .mismatch(readBack), kept)
    }
}

// Vehicle-controller register 0xE3 reads 450 on a rated-45 scooter and 500 after a dealer unlock; the dashboard still clamps its display at the rated speed.
enum TopSpeedState: Equatable {
    case locked
    case unlocked
    case other(Int)

    init(register value: Int) {
        switch value {
        case TopSpeedControl.lockedRegister: self = .locked
        case TopSpeedControl.unlockedRegister: self = .unlocked
        default: self = .other(value)
        }
    }

    var kmh: Double {
        switch self {
        case .locked: Double(TopSpeedControl.lockedRegister) / 10
        case .unlocked: Double(TopSpeedControl.unlockedRegister) / 10
        case let .other(value): Double(value) / 10
        }
    }
}

enum TopSpeedWrite: Equatable {
    case confirmed(TopSpeedState)
    case mismatch(TopSpeedState)
    case unreadable
}

enum TopSpeedControl {
    static let lockedRegister = 450
    static let unlockedRegister = 500

    static func target(unlocked: Bool) -> Int {
        unlocked ? unlockedRegister : lockedRegister
    }

    // Writes 0xE3 and reads it back, since the controller never acknowledges; keeps the first value seen so it can be restored.
    static func apply(
        unlocked: Bool, original: Int?, session: NinebotSession, settle: Duration = .milliseconds(500)
    ) async throws -> (result: TopSpeedWrite, original: Int?) {
        let kept: Int?
        if let original {
            kept = original
        } else {
            kept = try? await session.value(.topSpeed)
        }
        try await session.write(.topSpeed, UInt16(target(unlocked: unlocked)))
        try await Task.sleep(for: settle)
        guard let readBack = try? await session.value(.topSpeed) else { return (.unreadable, kept) }
        let state = TopSpeedState(register: readBack)
        let matched = readBack == target(unlocked: unlocked)
        return (matched ? .confirmed(state) : .mismatch(state), kept)
    }
}

enum VehicleActionOutcome: Equatable {
    case sent
    case stateChanged(from: Int, to: Int)
    case stateUnchanged(Int)
}

enum VehicleControl {
    static func powerOffAllowed(rideActive: Bool, speedKmh: Double?) -> Bool {
        !rideActive && (speedKmh ?? 0) <= 0
    }

    static func perform(
        _ action: VehicleAction, ident: [UInt8], session: NinebotSession, rideActive: Bool, speedKmh: Double?, settle: Duration = .milliseconds(1500)
    ) async throws -> VehicleActionOutcome {
        if action == .powerOff, !powerOffAllowed(rideActive: rideActive, speedKmh: speedKmh) {
            throw ScooterControlError.powerOffWhileRiding
        }
        guard action != .openSeat else {
            try await session.perform(action, ident: ident)
            return .sent
        }
        let before = try? await session.value(.mainPower)
        try await session.perform(action, ident: ident)
        try await Task.sleep(for: settle)
        let after = try? await session.value(.mainPower)
        guard let before, let after else { return .sent }
        return before == after ? .stateUnchanged(after) : .stateChanged(from: before, to: after)
    }
}
