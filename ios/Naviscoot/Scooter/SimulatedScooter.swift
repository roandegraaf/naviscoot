#if DEBUG
import Foundation

final class SimulatedScooter: NinebotTransport {
    let inbox = NinebotInbox()
    private(set) var actions: [(action: VehicleAction, ident: [UInt8])] = []
    private(set) var writes: [(register: NinebotRegister, value: Int)] = []
    var ignoresWrites = false
    var maxWordsPerReply: Int?
    private(set) var readRequests: [(board: UInt8, index: UInt8, words: Int)] = []
    var onAction: ((VehicleAction, SimulatedScooter) -> Void)?

    private var words: [UInt8: [UInt8: UInt16]] = [:]
    private let serial: [UInt8]
    private let password: [UInt8]
    private let auth: [UInt8] = Array(0xA0 ... 0xAF as ClosedRange<UInt8>)
    private var greeting: NinebotCrypto
    private var device: NinebotCrypto
    private var greeted = false

    init(serial: String, password: [UInt8]) {
        self.serial = Array(serial.utf8)
        self.password = password
        greeting = NinebotCrypto(key1: self.serial, key2: NinebotCrypto.firmwareKey)
        device = NinebotCrypto(key1: password, key2: auth)
        device.startCountedMode(auth: auth)
    }

    func set(_ register: NinebotRegister, _ value: Int) {
        set(board: register.board, index: register.index, words: [UInt16(truncatingIfNeeded: value)])
    }

    func set(board: UInt8, index: UInt8, words values: [UInt16]) {
        for (offset, value) in values.enumerated() {
            words[board, default: [:]][index + UInt8(offset)] = value
        }
    }

    func set(board: UInt8, index: UInt8, bytes: [UInt8]) {
        let padded = bytes.count.isMultiple(of: 2) ? bytes : bytes + [0]
        set(board: board, index: index, words: stride(from: 0, to: padded.count, by: 2).map { UInt16(padded[$0]) | UInt16(padded[$0 + 1]) << 8 })
    }

    func value(_ register: NinebotRegister) -> Int? {
        words[register.board]?[register.index].map(Int.init)
    }

    func send(_ wire: [UInt8]) async throws {
        guard greeted else {
            guard let plain = try? greeting.decrypt(wire), let frame = NinebotFrame(bytes: plain),
                  frame.command == NinebotFrame.Command.preCommunication.rawValue else { return }
            greeted = true
            reply(&greeting, command: frame.command, index: 1, payload: auth + serial)
            return
        }
        guard let plain = try? device.decrypt(wire), let frame = NinebotFrame(bytes: plain) else { return }
        switch frame.command {
        case NinebotFrame.Command.authenticate.rawValue:
            reply(&device, command: frame.command, index: 1, payload: [])
        case NinebotFrame.Command.read.rawValue:
            let count = Int(frame.payload.first ?? 2) / 2
            let board = words[frame.destination] ?? [:]
            let values = (0 ..< count).compactMap { board[frame.index &+ UInt8($0)] }
            readRequests.append((frame.destination, frame.index, count))
            guard values.count == count else { return }
            let chunk = maxWordsPerReply ?? count
            for start in stride(from: 0, to: count, by: chunk) {
                let payload = values[start ..< min(start + chunk, count)].flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }
                reply(&device, source: frame.destination, command: NinebotFrame.Command.readResponse.rawValue, index: frame.index &+ UInt8(start), payload: payload)
            }
        case NinebotFrame.Command.writeWithoutReply.rawValue:
            let value = Int(frame.payload[0]) | Int(frame.payload[1]) << 8
            writes.append((NinebotRegister(board: frame.destination, index: frame.index, length: 2), value))
            if !ignoresWrites { words[frame.destination, default: [:]][frame.index] = UInt16(value) }
        case NinebotFrame.Command.vehicleAction.rawValue:
            guard let action = VehicleAction(rawValue: frame.index) else { return }
            actions.append((action, frame.payload))
            onAction?(action, self)
        default:
            return
        }
    }

    private func reply(_ crypto: inout NinebotCrypto, source: UInt8 = NinebotFrame.bluetoothBoard, command: UInt8, index: UInt8, payload: [UInt8]) {
        let frame = NinebotFrame(source: source, destination: NinebotFrame.appAddress, command: command, index: index, payload: payload)
        inbox.push(crypto.encrypt(frame.bytes))
    }
}

// A DEBUG stand-in for the scooter: a real NinebotSession runs against this register map, so every screen reads it like hardware.
struct ScooterSimulation: Equatable {
    enum Profile: String, CaseIterable {
        case charging
        case riding
    }

    static let launchKey = "NaviscootSimScooter"
    static let serial = "NAVISIMSCOOTER"
    static let password: [UInt8] = Array(0x10 ... 0x1F as ClosedRange<UInt8>)
    static let ident: [UInt8] = Array(0x20 ... 0x2F as ClosedRange<UInt8>)
    static let mainPowerOn = 429
    static let mainPowerOff = 421

    let profile: Profile
    var batteryPercent = 64
    var rangeKm = 31.0
    var odometerKm = 1234.5
    var timeToFullMinutes = 95

    init(profile: Profile) {
        self.profile = profile
    }

    static func requested(defaults: UserDefaults = .standard) -> ScooterSimulation? {
        defaults.string(forKey: launchKey).flatMap(parse)
    }

    static func parse(_ text: String) -> ScooterSimulation? {
        Profile(rawValue: text.trimmingCharacters(in: .whitespaces).lowercased()).map(ScooterSimulation.init(profile:))
    }

    var speedKmh: Double { profile == .riding ? 24 : 0 }

    var packCurrentA: Double { profile == .charging ? -2.5 : 6.0 }

    func makeScooter() -> SimulatedScooter {
        let scooter = SimulatedScooter(serial: Self.serial, password: Self.password)
        let dashboard = NinebotFrame.dashboardBoard
        scooter.set(.battery, batteryPercent)
        scooter.set(.range, Int((rangeKm * 10).rounded()))
        scooter.set(.speed, Int((speedKmh * 10).rounded()))
        let odometerM = UInt32((odometerKm * 1000).rounded())
        scooter.set(board: dashboard, index: NinebotRegister.odometer.index, words: [UInt16(odometerM & 0xFFFF), UInt16(odometerM >> 16)])
        scooter.set(.timeToFull, profile == .charging ? timeToFullMinutes : 0)
        scooter.set(.ratedSpeed, 450)
        scooter.set(.speedLimit, 0)
        scooter.set(.controlFlags, 0)
        scooter.set(.featureFlags, 0x4000 | 0x0008)
        scooter.set(.timeZone, Int(UInt16(bitPattern: Int16(ScooterClock.offsetMinutes(.current, at: Date())))))
        scooter.set(.mainPower, Self.mainPowerOn)
        scooter.set(.topSpeed, TopSpeedControl.lockedRegister)
        let battery = NinebotFrame.batteryBoard
        scooter.set(board: battery, index: NinebotRegister.packInfo.index, bytes: packInfo)
        scooter.set(board: battery, index: NinebotRegister.packManufactureDate.index, words: [UInt16((23 << 9) | (4 << 5) | 12)])
        scooter.set(board: battery, index: NinebotRegister.packLive.index, words: packLive)
        scooter.set(board: battery, index: NinebotRegister.packCells.index, words: [3851, 3849, 3853, 3850, 3848, 3852, 3851, 3846, 3850, 3854, 3849, 3851, 3850])
        scooter.onAction = { action, scooter in
            switch action {
            case .powerOn: scooter.set(.mainPower, Self.mainPowerOn)
            case .powerOff: scooter.set(.mainPower, Self.mainPowerOff)
            case .openSeat: break
            }
        }
        return scooter
    }

    private static let fullCapacityCAh = 2790

    private var packInfo: [UInt8] {
        let words: [UInt16] = [0x0355, 3000, UInt16(Self.fullCapacityCAh), 0, 87, 112]
        return Array("NAVISIMPACK001".utf8) + words.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }
    }

    private var packLive: [UInt16] {
        let remaining = UInt16(Self.fullCapacityCAh * batteryPercent / 100)
        let current = UInt16(bitPattern: Int16((packCurrentA * 100).rounded()))
        let temperatures: [UInt8] = [22, 23, 22, 24].map { $0 + 20 }
        return [0x41, remaining, UInt16(batteryPercent * 10), current, 5005, 0,
                UInt16(temperatures[0]) | UInt16(temperatures[1]) << 8, UInt16(temperatures[2]) | UInt16(temperatures[3]) << 8]
    }
}
#endif
