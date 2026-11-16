import CoreBluetooth
import Foundation

// All mutable state is only touched on `queue`, which is also the CoreBluetooth delegate queue.
final class ScooterBluetoothLink: NSObject, NinebotTransport, @unchecked Sendable {
    private struct Channel {
        let service: CBUUID
        let write: CBUUID
        let notify: CBUUID
    }

    private static let channels = [
        Channel(
            service: CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"),
            write: CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"),
            notify: CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")
        ),
        Channel(
            service: CBUUID(string: "6E400001-0000-0000-006E-696E65626F74"),
            write: CBUUID(string: "6E400002-0000-0000-006E-696E65626F74"),
            notify: CBUUID(string: "6E400004-0000-0000-006E-696E65626F74")
        ),
    ]

    let inbox = NinebotInbox()
    private let serial: String
    private let knownPeripheral: UUID?
    private let queue = DispatchQueue(label: "nl.naviscoot.scooter.bluetooth")
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var assembler = NinebotFrameAssembler()
    private var connecting: CheckedContinuation<Void, Error>?
    private var outgoing: [[UInt8]] = []
    private var sending: CheckedContinuation<Void, Error>?

    // iOS only allows filtered scans in the background, so a scooter seen before is reconnected to by its identifier instead.
    init(serial: String, knownPeripheral: UUID? = nil) {
        self.serial = serial
        self.knownPeripheral = knownPeripheral
    }

    var peripheralIdentifier: UUID? {
        queue.sync { peripheral?.identifier }
    }

    // The central manager is created here rather than at launch, so the Bluetooth permission prompt only appears once the rider asks for it.
    func connect(timeout: Duration = .seconds(15)) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                connecting = continuation
                central = CBCentralManager(delegate: self, queue: queue)
                queue.asyncAfter(deadline: .now() + Self.seconds(timeout)) { [self] in
                    finishConnecting(throwing: peripheral == nil ? .notFound : .connectionFailed)
                }
            }
        }
    }

    func send(_ frame: [UInt8]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                guard let peripheral, let writeCharacteristic, peripheral.state == .connected, sending == nil else {
                    continuation.resume(throwing: ScooterError.disconnected)
                    return
                }
                let size = max(20, peripheral.maximumWriteValueLength(for: writeType(writeCharacteristic)))
                outgoing = stride(from: 0, to: frame.count, by: size).map { Array(frame[$0 ..< min($0 + size, frame.count)]) }
                sending = continuation
                pumpWrites()
            }
        }
    }

    func disconnect() {
        queue.async { [self] in
            central?.stopScan()
            if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        }
    }

    private func writeType(_ characteristic: CBCharacteristic) -> CBCharacteristicWriteType {
        characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
    }

    private func pumpWrites() {
        guard let peripheral, let writeCharacteristic else { return }
        let type = writeType(writeCharacteristic)
        while let chunk = outgoing.first {
            if type == .withoutResponse, !peripheral.canSendWriteWithoutResponse { return }
            outgoing.removeFirst()
            peripheral.writeValue(Data(chunk), for: writeCharacteristic, type: type)
        }
        let continuation = sending
        sending = nil
        continuation?.resume()
    }

    private func finishConnecting(throwing error: ScooterError? = nil) {
        guard let continuation = connecting else { return }
        connecting = nil
        guard let error else {
            continuation.resume()
            return
        }
        central?.stopScan()
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        continuation.resume(throwing: error)
    }

    private func dropConnection() {
        let continuation = sending
        sending = nil
        outgoing = []
        continuation?.resume(throwing: ScooterError.disconnected)
        inbox.close(ScooterError.disconnected)
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}

extension ScooterBluetoothLink: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            guard peripheral == nil else { break }
            if let knownPeripheral, let known = central.retrievePeripherals(withIdentifiers: [knownPeripheral]).first {
                peripheral = known
                known.delegate = self
                central.connect(known)
            } else {
                central.scanForPeripherals(withServices: nil)
            }
        case .poweredOff, .unsupported:
            finishConnecting(throwing: .bluetoothOff)
            dropConnection()
        case .unauthorized:
            finishConnecting(throwing: .bluetoothDenied)
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name
        guard self.peripheral == nil, name == serial else { return }
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices(Self.channels.map(\.service))
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        finishConnecting(throwing: .connectionFailed)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        finishConnecting(throwing: .connectionFailed)
        dropConnection()
    }
}

extension ScooterBluetoothLink: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let services = peripheral.services ?? []
        guard let service = Self.channels.lazy.compactMap({ channel in services.first { $0.uuid == channel.service } }).first else {
            finishConnecting(throwing: .noCompatibleService)
            return
        }
        peripheral.discoverCharacteristics(nil, for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        let characteristics = service.characteristics ?? []
        guard let channel = Self.channels.first(where: { $0.service == service.uuid }),
              let write = characteristics.first(where: { $0.uuid == channel.write }),
              let notify = characteristics.first(where: { $0.uuid == channel.notify }) else {
            finishConnecting(throwing: .noCompatibleService)
            return
        }
        writeCharacteristic = write
        peripheral.setNotifyValue(true, for: notify)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, characteristic.isNotifying else {
            finishConnecting(throwing: .connectionFailed)
            return
        }
        finishConnecting()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let value = characteristic.value else { return }
        for frame in assembler.append(Array(value)) {
            inbox.push(frame)
        }
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        pumpWrites()
    }
}
