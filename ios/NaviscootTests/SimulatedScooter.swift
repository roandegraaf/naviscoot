@testable import Naviscoot
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
