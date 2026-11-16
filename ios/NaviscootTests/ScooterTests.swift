@testable import Naviscoot
import XCTest

// Expected bytes come from the reference Python client (segway-ninebot-ble-cli), run with a made-up serial and password.
final class ScooterTests: XCTestCase {
    private let serial = "TESTDEVICE0001"
    private let password = Array(0x10 ... 0x1F as ClosedRange<UInt8>)
    private let auth = bytes("00112233445566778899aabbccddeeff")

    private enum Wire {
        static let preCommunication = bytes("5aa500e1748ab4000062ff0000")
        static let greeting = bytes("5aa51edb4e8ab5805d65442362f76fc6e842e913ad3f4bd40914232372c7510d34d862ef410000b8f30000")
        static let authenticate = bytes("5aa50ec07a156128780012efd720ade50454589bcaa546477a0002")
        static let accepted = bytes("5aa500fa40156094fa3dd70002")
        static let rejected = bytes("5aa500fa401561032aa0860002")
        static let readBattery = bytes("5aa501010e7574e153855c400003")
        static let battery = bytes("5aa5023e317074cc6613d703e90003")
        static let readRange = bytes("5aa501d529db83c721b6f1ab0004")
        static let range = bytes("5aa502ea16de832f174a2d48e90004")
        static let readOdometer = bytes("5aa50169027272c58c73097e0005")
        static let odometer = bytes("5aa504563d777222be83b0928136980005")
        static let readSpeed = bytes("5aa5017def5d081b4b3312180006")
        static let speed = bytes("5aa50242d05808194717e07cc30006")
        static let writeSpeedLimit = bytes("5aa502010e7752fa6616cb8e0d0003")
        static let openSeat = bytes("5aa510d521bed5e5364fe527d501146f662892e5e6823d3f549d0e0004")
        static let readPackVoltage = bytes("5aa501690472dfc333d72c390005")
        static let packVoltage = bytes("5aa502383170dbdb7345d45f2a0003")
    }

    private final class ScriptedScooter: NinebotTransport {
        let inbox = NinebotInbox()
        private(set) var sent: [[UInt8]] = []
        private var replies: [[[UInt8]]]

        init(replies: [[[UInt8]]]) {
            self.replies = replies
        }

        func send(_ frame: [UInt8]) async throws {
            sent.append(frame)
            guard !replies.isEmpty else { return }
            replies.removeFirst().forEach(inbox.push)
        }
    }

    private func session(_ scooter: ScriptedScooter) -> NinebotSession {
        NinebotSession(transport: scooter, serial: serial, password: password, handshakeTimeout: .milliseconds(200), readTimeout: .milliseconds(200), listenWindow: .milliseconds(20))
    }

    func testKeysDeriveLikeTheReferenceClient() {
        XCTAssertEqual(NinebotCrypto.deriveKey(Array(serial.utf8), NinebotCrypto.firmwareKey), bytes("cefa338b052ba289c68a9bb59aa4f0da"))
        XCTAssertEqual(NinebotCrypto.deriveKey(Array(serial.utf8), nil), bytes("4d631a0ea0d182f78b084f5d2d062ab3"))
        XCTAssertEqual(NinebotCrypto.deriveKey(password, auth), bytes("3afab2e13921ae44e2968ebbdd1a5425"))
    }

    func testHandshakeAndReadsMatchTheReferenceClientByteForByte() async throws {
        let scooter = ScriptedScooter(replies: [[Wire.greeting], [Wire.accepted], [Wire.battery], [Wire.range], [Wire.odometer], [Wire.speed]])
        let session = session(scooter)

        try await session.authenticate()
        let telemetry = try await session.readTelemetry()

        XCTAssertEqual(scooter.sent, [Wire.preCommunication, Wire.authenticate, Wire.readBattery, Wire.readRange, Wire.readOdometer, Wire.readSpeed])
        XCTAssertEqual(telemetry, ScooterTelemetry(batteryPercent: 47, rangeKm: 23.4, odometerKm: 15366.115, speedKmh: 0))
    }

    func testWritesActionsAndBatteryBoardReadsMatchTheReferenceClient() async throws {
        let scooter = ScriptedScooter(replies: [[Wire.greeting], [Wire.accepted], [], [], [Wire.packVoltage]])
        let session = session(scooter)
        try await session.authenticate()

        try await session.write(.speedLimit, 25)
        try await session.perform(.openSeat, ident: Array(0x20 ... 0x2F as ClosedRange<UInt8>))
        let voltage = try await session.value(NinebotRegister(board: NinebotFrame.batteryBoard, index: 0x1A, length: 2))

        XCTAssertEqual(Array(scooter.sent.dropFirst(2)), [Wire.writeSpeedLimit, Wire.openSeat, Wire.readPackVoltage])
        XCTAssertEqual(voltage, 5432)
    }

    func testAnEchoedGreetingMeansTheSerialIsWrong() async {
        let scooter = ScriptedScooter(replies: [[Wire.preCommunication]])
        await assertThrows(.serialRejected) { try await self.session(scooter).authenticate() }
        XCTAssertEqual(scooter.sent.count, 1)
    }

    func testAnotherAppsSessionTrafficStopsTheHandshakeBeforeAnythingIsSent() async {
        let scooter = ScriptedScooter(replies: [[Wire.greeting], [Wire.accepted]])
        scooter.inbox.push(Wire.battery)
        await assertThrows(.heldByOtherApp) { try await self.session(scooter).authenticate() }
        XCTAssertEqual(scooter.sent, [])
    }

    func testSessionTrafficInsteadOfAGreetingMeansAnotherAppHoldsTheScooter() async {
        let scooter = ScriptedScooter(replies: [[Wire.accepted, Wire.greeting]])
        await assertThrows(.heldByOtherApp) { try await self.session(scooter).authenticate() }
        XCTAssertEqual(scooter.sent, [Wire.preCommunication])
    }

    func testARefusedAuthenticationMeansTheWrongPasswordAndNothingElseIsSent() async {
        let scooter = ScriptedScooter(replies: [[Wire.greeting], [Wire.rejected]])
        await assertThrows(.passwordRejected) { try await self.session(scooter).authenticate() }
        XCTAssertEqual(scooter.sent, [Wire.preCommunication, Wire.authenticate])
    }

    func testAReplyThatFailsTheIntegrityCheckIsTreatedAsTheWrongPassword() async {
        var tampered = Wire.accepted
        tampered[tampered.count - 3] ^= 0x01
        let scooter = ScriptedScooter(replies: [[Wire.greeting], [tampered]])
        await assertThrows(.passwordRejected) { try await self.session(scooter).authenticate() }
    }

    func testATamperedFrameFailsDecryption() {
        var crypto = NinebotCrypto(key1: password, key2: auth)
        crypto.startCountedMode(auth: auth)
        XCTAssertEqual(try crypto.decrypt(Wire.accepted), [0x5A, 0xA5, 0x00, 0x04, 0x3E, 0x5D, 0x01])
        var tampered = Wire.accepted
        tampered[5] ^= 0x80
        XCTAssertThrowsError(try crypto.decrypt(tampered))
    }

    func testAReadSkipsALateReplyForAnotherRegister() async throws {
        let scooter = ScriptedScooter(replies: [[Wire.greeting], [Wire.accepted], [Wire.range, Wire.battery]])
        let session = session(scooter)
        try await session.authenticate()
        let battery = try await session.read(.battery)
        XCTAssertEqual(battery, [47, 0])
    }

    func testAReadWithoutAnAnswerTimesOut() async throws {
        let scooter = ScriptedScooter(replies: [[Wire.greeting], [Wire.accepted]])
        let session = session(scooter)
        try await session.authenticate()
        await assertThrows(.timeout) { _ = try await session.read(.battery) }
    }

    func testTheAssemblerRebuildsFramesFromNotificationChunks() {
        var assembler = NinebotFrameAssembler()
        let stream = [0x00, 0x13] + Wire.greeting + Wire.accepted
        var frames: [[UInt8]] = []
        for start in stride(from: 0, to: stream.count, by: 20) {
            frames += assembler.append(Array(stream[start ..< min(start + 20, stream.count)]))
        }
        XCTAssertEqual(frames, [Wire.greeting, Wire.accepted])
    }

    func testConsumptionIsPooledFromTripsThatDrainedEnough() {
        XCTAssertNil(ConsumptionModel(samples: [ScooterTripSample(distanceKm: 40, batteryUsedPercent: 19)]).kmPerPercent)
        let model = ConsumptionModel(samples: [
            ScooterTripSample(distanceKm: 10, batteryUsedPercent: 20),
            ScooterTripSample(distanceKm: 3, batteryUsedPercent: 4),
            ScooterTripSample(distanceKm: 20, batteryUsedPercent: 30),
        ])
        XCTAssertEqual(model.kmPerPercent ?? 0, 0.6, accuracy: 1e-9)
        let telemetry = ScooterTelemetry(batteryPercent: 50, rangeKm: 23.4, odometerKm: 0, speedKmh: 0)
        XCTAssertEqual(model.rangeKm(for: telemetry), 30, accuracy: 1e-9)
        XCTAssertEqual(ConsumptionModel(samples: []).rangeKm(for: telemetry), 23.4)
    }

    func testRangeVerdictsUseTheMargin() {
        XCTAssertEqual(RangeVerdict.judge(routeKm: 10, rangeKm: 20, marginPercent: 15), .fits(spareKm: 10))
        XCTAssertEqual(RangeVerdict.judge(routeKm: 18, rangeKm: 20, marginPercent: 15), .tight(spareKm: 2))
        XCTAssertEqual(RangeVerdict.judge(routeKm: 25, rangeKm: 20, marginPercent: 15), .short(missingKm: 5))
        XCTAssertFalse(ReturnCheck.mustTurnBack(rangeKm: 12, returnKm: 10, marginPercent: 15))
        XCTAssertTrue(ReturnCheck.mustTurnBack(rangeKm: 11, returnKm: 10, marginPercent: 15))
    }

    func testPasswordsAreThirtyTwoHexCharacters() {
        XCTAssertEqual(ScooterPassword.parse("10111213 14151617 18191a1b 1c1d1e1f"), password)
        XCTAssertEqual(ScooterPassword.parse("101112131415161718191A1B1C1D1E1F"), password)
        XCTAssertNil(ScooterPassword.parse("1011121314151617"))
        XCTAssertNil(ScooterPassword.parse("+0111213141516171819101b1c1d1e1f"))
        XCTAssertNil(ScooterPassword.parse("zz111213141516171819101b1c1d1e1f"))
    }

    private func assertThrows(_ expected: ScooterError, _ body: @escaping () async throws -> Void, line: UInt = #line) async {
        do {
            try await body()
            XCTFail("expected \(expected)", line: line)
        } catch {
            XCTAssertEqual(error as? ScooterError, expected, line: line)
        }
    }
}

private func bytes(_ hex: String) -> [UInt8] {
    stride(from: 0, to: hex.count, by: 2).map {
        let start = hex.index(hex.startIndex, offsetBy: $0)
        return UInt8(hex[start ..< hex.index(start, offsetBy: 2)], radix: 16)!
    }
}
