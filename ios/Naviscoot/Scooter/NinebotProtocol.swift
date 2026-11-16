import Foundation

struct NinebotFrame: Equatable {
    static let appAddress: UInt8 = 0x3E
    static let bluetoothBoard: UInt8 = 0x04
    static let dashboardBoard: UInt8 = 0x01

    static let motorBoard: UInt8 = 0x02
    static let batteryBoard: UInt8 = 0x07
    static let vehicleBoard: UInt8 = 0x09

    enum Command: UInt8 {
        case read = 0x01
        case writeWithoutReply = 0x03
        case readResponse = 0x04
        case preCommunication = 0x5B
        case authenticate = 0x5D
        case vehicleAction = 0x64
    }

    var source: UInt8
    var destination: UInt8
    var command: UInt8
    var index: UInt8
    var payload: [UInt8]

    static func request(to board: UInt8, _ command: Command, index: UInt8 = 0, payload: [UInt8] = []) -> NinebotFrame {
        NinebotFrame(source: appAddress, destination: board, command: command.rawValue, index: index, payload: payload)
    }

    var bytes: [UInt8] {
        [0x5A, 0xA5, UInt8(payload.count), source, destination, command, index] + payload
    }

    init(source: UInt8, destination: UInt8, command: UInt8, index: UInt8, payload: [UInt8]) {
        self.source = source
        self.destination = destination
        self.command = command
        self.index = index
        self.payload = payload
    }

    init?(bytes: [UInt8]) {
        guard bytes.count >= 7, bytes[0] == 0x5A, bytes[1] == 0xA5 || bytes[1] == 0xB5 else { return nil }
        let length = Int(bytes[2])
        guard bytes.count >= 7 + length else { return nil }
        self.init(source: bytes[3], destination: bytes[4], command: bytes[5], index: bytes[6], payload: Array(bytes[7 ..< 7 + length]))
    }
}

struct NinebotFrameAssembler {
    private var buffer: [UInt8] = []

    // A wire frame is the 3-byte header, LEN + 4 bytes of addressing and payload, and the 6-byte tail.
    mutating func append(_ bytes: [UInt8]) -> [[UInt8]] {
        buffer += bytes
        var frames: [[UInt8]] = []
        while true {
            guard let start = buffer.indices.dropLast().first(where: { buffer[$0] == 0x5A && (buffer[$0 + 1] == 0xA5 || buffer[$0 + 1] == 0xB5) }) else {
                buffer = buffer.last == 0x5A ? [0x5A] : []
                return frames
            }
            buffer.removeFirst(start)
            guard buffer.count >= 3 else { return frames }
            let total = Int(buffer[2]) + 13
            guard buffer.count >= total else { return frames }
            frames.append(Array(buffer.prefix(total)))
            buffer.removeFirst(total)
        }
    }
}

final class NinebotInbox: @unchecked Sendable {
    private let lock = NSLock()
    private var frames: [[UInt8]] = []
    private var waiter: (token: UUID, continuation: CheckedContinuation<[UInt8], Error>)?
    private var closure: Error?

    func push(_ frame: [UInt8]) {
        lock.lock()
        guard let waiter else {
            frames.append(frame)
            lock.unlock()
            return
        }
        self.waiter = nil
        lock.unlock()
        waiter.continuation.resume(returning: frame)
    }

    func close(_ error: Error) {
        lock.lock()
        closure = error
        let waiter = self.waiter
        self.waiter = nil
        lock.unlock()
        waiter?.continuation.resume(throwing: error)
    }

    func next(timeout: Duration) async throws -> [UInt8] {
        let token = UUID()
        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if !frames.isEmpty {
                let frame = frames.removeFirst()
                lock.unlock()
                continuation.resume(returning: frame)
                return
            }
            if let closure {
                lock.unlock()
                continuation.resume(throwing: closure)
                return
            }
            waiter = (token, continuation)
            lock.unlock()
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                self?.expire(token)
            }
        }
    }

    private func expire(_ token: UUID) {
        lock.lock()
        guard let waiter, waiter.token == token else {
            lock.unlock()
            return
        }
        self.waiter = nil
        lock.unlock()
        waiter.continuation.resume(throwing: ScooterError.timeout)
    }
}

protocol NinebotTransport: AnyObject {
    var inbox: NinebotInbox { get }
    func send(_ frame: [UInt8]) async throws
}

enum ScooterError: Error, Equatable {
    case bluetoothOff
    case bluetoothDenied
    case notFound
    case connectionFailed
    case noCompatibleService
    case disconnected
    case timeout
    case serialRejected
    case passwordRejected
    case heldByOtherApp
    case unexpectedResponse
}

struct ScooterTelemetry: Equatable {
    var batteryPercent: Int
    var rangeKm: Double
    var odometerKm: Double
    var speedKmh: Double
}

// Board addresses follow the E-series layout ("Segway eScooter E"): the Python reference client defaults to E125S-era boards 0x20 and 0x22.
struct NinebotRegister: Equatable {
    let board: UInt8
    let index: UInt8
    let length: UInt8

    static let battery = NinebotRegister(board: NinebotFrame.dashboardBoard, index: 0xB5, length: 2)
    static let range = NinebotRegister(board: NinebotFrame.dashboardBoard, index: 0x25, length: 2)
    static let speed = NinebotRegister(board: NinebotFrame.dashboardBoard, index: 0x26, length: 2)
    static let odometer = NinebotRegister(board: NinebotFrame.dashboardBoard, index: 0xB7, length: 4)
    static let timeToFull = NinebotRegister(board: NinebotFrame.dashboardBoard, index: 0x39, length: 2)
    static let ratedSpeed = NinebotRegister(board: NinebotFrame.dashboardBoard, index: 0x48, length: 2)
    static let speedLimit = NinebotRegister(board: NinebotFrame.dashboardBoard, index: 0x93, length: 2)
    static let controlFlags = NinebotRegister(board: NinebotFrame.dashboardBoard, index: 0x7C, length: 2)
    static let featureFlags = NinebotRegister(board: NinebotFrame.dashboardBoard, index: 0x7D, length: 2)
    static let timeZone = NinebotRegister(board: NinebotFrame.dashboardBoard, index: 0x86, length: 2)
    static let packInfo = NinebotRegister(board: NinebotFrame.batteryBoard, index: 0x10, length: 26)
    static let packManufactureDate = NinebotRegister(board: NinebotFrame.batteryBoard, index: 0x20, length: 2)
    static let packLive = NinebotRegister(board: NinebotFrame.batteryBoard, index: 0x30, length: 16)
    static let packCells = NinebotRegister(board: NinebotFrame.batteryBoard, index: 0x40, length: 26)
    static let packCharge = NinebotRegister(board: NinebotFrame.batteryBoard, index: 0x32, length: 2)
    static let packVoltage = NinebotRegister(board: NinebotFrame.batteryBoard, index: 0x34, length: 2)
    static let motorMaxSpeed = NinebotRegister(board: NinebotFrame.motorBoard, index: 0x09, length: 2)
    static let gearTopSpeed = NinebotRegister(board: NinebotFrame.motorBoard, index: 0x31, length: 2)
    static let mainPower = NinebotRegister(board: NinebotFrame.vehicleBoard, index: 0x03, length: 2)
    static let topSpeed = NinebotRegister(board: NinebotFrame.vehicleBoard, index: 0xE3, length: 2)
}

enum VehicleAction: UInt8 {
    case powerOn = 0x4E
    case powerOff = 0x46
    case openSeat = 0x73
}

final class NinebotSession {
    private let transport: NinebotTransport
    private let serial: [UInt8]
    private let password: [UInt8]
    private let handshakeTimeout: Duration
    private let readTimeout: Duration
    private let listenWindow: Duration
    private var crypto: NinebotCrypto

    init(
        transport: NinebotTransport, serial: String, password: [UInt8],
        handshakeTimeout: Duration = .seconds(5), readTimeout: Duration = .seconds(2), listenWindow: Duration = .milliseconds(500)
    ) {
        self.transport = transport
        self.serial = Array(serial.utf8)
        self.password = password
        self.handshakeTimeout = handshakeTimeout
        self.readTimeout = readTimeout
        self.listenWindow = listenWindow
        crypto = NinebotCrypto(key1: self.serial, key2: NinebotCrypto.firmwareKey)
    }

    // Only ever authenticates with the password the scooter already holds. Setting a new one would unbind the Segway app.
    func authenticate() async throws {
        try await listenForOtherClient()
        let preCommunication = NinebotFrame.request(to: NinebotFrame.bluetoothBoard, .preCommunication)
        try await transport.send(crypto.encrypt(preCommunication.bytes))
        let wire = try await transport.inbox.next(timeout: handshakeTimeout)
        guard !Self.isSessionTraffic(wire) else { throw ScooterError.heldByOtherApp }
        let greeting = try frame(wire, failure: .serialRejected)
        guard greeting.bytes != preCommunication.bytes else { throw ScooterError.serialRejected }
        guard greeting.command == NinebotFrame.Command.preCommunication.rawValue, greeting.payload.count >= 30 else {
            throw ScooterError.unexpectedResponse
        }
        let auth = Array(greeting.payload[0 ..< 16])
        let scooterSerial = Array(greeting.payload[16 ..< 30])

        crypto.startCountedMode(auth: auth)
        crypto.rekey(key1: password, key2: auth)
        let authenticate = NinebotFrame.request(to: NinebotFrame.bluetoothBoard, .authenticate, payload: scooterSerial)
        try await transport.send(crypto.encrypt(authenticate.bytes))
        let verdict = try await reply(timeout: handshakeTimeout, failure: .passwordRejected)
        guard verdict.command == NinebotFrame.Command.authenticate.rawValue, verdict.index == 1 else {
            throw ScooterError.passwordRejected
        }
    }

    static let maxBytesPerRead: UInt8 = 8

    // The battery board answers a read longer than four words with several separately indexed frames, so long reads go out four words at a time.
    func read(_ register: NinebotRegister) async throws -> [UInt8] {
        guard register.length > Self.maxBytesPerRead else { return try await readBlock(register) }
        var bytes: [UInt8] = []
        var index = register.index
        var remaining = register.length
        while remaining > 0 {
            let length = min(remaining, Self.maxBytesPerRead)
            bytes += try await readBlock(NinebotRegister(board: register.board, index: index, length: length))
            index &+= length / 2
            remaining -= length
        }
        return bytes
    }

    private func readBlock(_ register: NinebotRegister) async throws -> [UInt8] {
        let request = NinebotFrame.request(to: register.board, .read, index: register.index, payload: [register.length])
        try await transport.send(crypto.encrypt(request.bytes))
        let deadline = ContinuousClock.now + readTimeout
        while true {
            let remaining = deadline - ContinuousClock.now
            guard remaining > .zero else { throw ScooterError.timeout }
            let wire = try await transport.inbox.next(timeout: remaining)
            guard let plaintext = try? crypto.decrypt(wire), let frame = NinebotFrame(bytes: plaintext) else { continue }
            if frame.command == NinebotFrame.Command.readResponse.rawValue, frame.index == register.index, frame.source == register.board,
               frame.payload.count >= Int(register.length) {
                return Array(frame.payload.prefix(Int(register.length)))
            }
        }
    }

    func value(_ register: NinebotRegister) async throws -> Int {
        Int(Self.littleEndian(try await read(register)))
    }

    func readTelemetry() async throws -> ScooterTelemetry {
        let battery = try await value(.battery)
        let range = try await value(.range)
        let odometer = try await value(.odometer)
        let speed = try await value(.speed)
        return ScooterTelemetry(batteryPercent: battery, rangeKm: Double(range) / 10, odometerKm: Double(odometer) / 1000, speedKmh: Double(speed) / 10)
    }

    // The scooter never acknowledges these writes, so callers read the register back to confirm.
    func write(_ register: NinebotRegister, _ value: UInt16) async throws {
        let request = NinebotFrame.request(to: register.board, .writeWithoutReply, index: register.index, payload: [UInt8(value & 0xFF), UInt8(value >> 8)])
        try await transport.send(crypto.encrypt(request.bytes))
    }

    // A wrong ident is ignored silently by the scooter, so there is no failure to report here either.
    func perform(_ action: VehicleAction, ident: [UInt8]) async throws {
        let request = NinebotFrame.request(to: NinebotFrame.vehicleBoard, .vehicleAction, index: action.rawValue, payload: ident)
        try await transport.send(crypto.encrypt(request.bytes))
    }

    // iOS shares one Bluetooth link between apps, so while the Segway app is connected its counted session frames reach us too.
    // Starting our own handshake over it would re-key the scooter and knock that app off, so we back off without writing.
    private func listenForOtherClient() async throws {
        let deadline = ContinuousClock.now + listenWindow
        while true {
            let remaining = deadline - ContinuousClock.now
            guard remaining > .zero, let wire = try? await transport.inbox.next(timeout: remaining) else { return }
            if Self.isSessionTraffic(wire) { throw ScooterError.heldByOtherApp }
        }
    }

    private static func isSessionTraffic(_ wire: [UInt8]) -> Bool {
        (NinebotCrypto.counter(of: wire) ?? 0) != 0
    }

    private func reply(timeout: Duration, failure: ScooterError) async throws -> NinebotFrame {
        try frame(try await transport.inbox.next(timeout: timeout), failure: failure)
    }

    private func frame(_ wire: [UInt8], failure: ScooterError) throws -> NinebotFrame {
        guard let plaintext = try? crypto.decrypt(wire) else { throw failure }
        guard let frame = NinebotFrame(bytes: plaintext) else { throw ScooterError.unexpectedResponse }
        return frame
    }

    private static func littleEndian(_ bytes: [UInt8]) -> UInt32 {
        bytes.enumerated().reduce(0) { $0 | UInt32($1.element) << (8 * UInt32($1.offset)) }
    }
}

enum ScooterPassword {
    static func parse(_ text: String) -> [UInt8]? {
        let hex = text.filter { !$0.isWhitespace }
        guard hex.count == 32, hex.allSatisfy(\.isHexDigit) else { return nil }
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index ..< next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return bytes
    }
}
