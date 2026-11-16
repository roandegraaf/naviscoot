@testable import Naviscoot
import XCTest

final class ScooterControlsTests: XCTestCase {
    private let serial = "TESTDEVICE0001"
    private let password = Array(0x10 ... 0x1F as ClosedRange<UInt8>)
    private let ident = Array(0x20 ... 0x2F as ClosedRange<UInt8>)
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func connected(_ configure: (SimulatedScooter) -> Void = { _ in }) async throws -> (SimulatedScooter, NinebotSession) {
        let scooter = SimulatedScooter(serial: serial, password: password)
        configure(scooter)
        let session = NinebotSession(transport: scooter, serial: serial, password: password, handshakeTimeout: .milliseconds(200), readTimeout: .milliseconds(100), listenWindow: .milliseconds(20))
        try await session.authenticate()
        return (scooter, session)
    }

    private static let packInfo: [UInt8] = Array("TESTPACK000001".utf8) + [0x55, 0x03, 0xB8, 0x0B, 0xA4, 0x0B, 0x00, 0x00, 0x05, 0x00, 0x09, 0x00]
    private static let packLive: [UInt8] = [0x41, 0x00, 0x54, 0x06, 0x14, 0x02, 0x14, 0xFF, 0xDF, 0x12, 0x00, 0x00, 0x2A, 0x2B, 0x2A, 0x2C]
    private static let packCells: [UInt8] = (0 ..< 13).flatMap { cell -> [UInt8] in
        let millivolts = 3700 + cell
        return [UInt8(millivolts & 0xFF), UInt8(millivolts >> 8)]
    }

    func testABatteryDumpIsDecoded() {
        let report = BatteryReport.parse(info: Self.packInfo, date: [0x87, 0x29], live: Self.packLive, cells: Self.packCells)

        XCTAssertEqual(report.serial, "TESTPACK000001")
        XCTAssertEqual(report.firmware, "3.5.5")
        XCTAssertEqual(report.designCapacityAh, 30)
        XCTAssertEqual(report.fullCapacityAh, 29.8)
        XCTAssertEqual(report.healthPercent ?? 0, 29.8 / 30 * 100, accuracy: 1e-9)
        XCTAssertEqual(report.cycles, 5)
        XCTAssertEqual(report.chargeCount, 9)
        XCTAssertEqual(report.manufactured, DateComponents(year: 2020, month: 12, day: 7))
        XCTAssertEqual(report.statusFlags, 0x41)
        XCTAssertEqual(report.remainingAh, 16.2)
        XCTAssertEqual(report.chargePercent, 53.2)
        XCTAssertEqual(report.currentA, -2.36)
        XCTAssertEqual(report.voltage, 48.31)
        XCTAssertEqual(report.temperaturesC, [22, 23, 22, 24])
        XCTAssertEqual(report.cellsMv.count, 13)
        XCTAssertEqual(report.cellSpreadMv, 12)
        XCTAssertEqual(report.isCharging, true)
    }

    func testTheChargeTimeComesFromTheCurrentAndTheMissingCapacity() {
        let report = BatteryReport.parse(info: Self.packInfo, date: nil, live: Self.packLive, cells: nil)
        let eta = report.estimatedTime(reaching: 80, from: start)
        XCTAssertEqual(eta?.timeIntervalSince(start) ?? 0, (29.8 * 0.8 - 16.2) / 2.36 * 3600, accuracy: 1)
        XCTAssertEqual(report.estimatedTime(reaching: 50, from: start), start)

        var discharging = report
        discharging.currentA = 1.5
        XCTAssertEqual(discharging.isCharging, false)
        XCTAssertNil(discharging.estimatedTime(reaching: 80, from: start))
    }

    func testMissingBlocksLeaveFieldsEmpty() {
        let report = BatteryReport.parse(info: nil, date: [0x00, 0x00], live: nil, cells: nil)
        XCTAssertEqual(report, BatteryReport())
        XCTAssertNil(report.isCharging)
    }

    func testTheBatteryIsReadInBlocksFromTheBatteryBoard() async throws {
        let (_, session) = try await connected { scooter in
            scooter.set(board: 0x07, index: 0x10, bytes: Self.packInfo)
            scooter.set(board: 0x07, index: 0x30, bytes: Self.packLive)
            scooter.set(board: 0x07, index: 0x40, bytes: Self.packCells)
        }
        let report = await BatteryReport.read(from: session)
        XCTAssertEqual(report.serial, "TESTPACK000001")
        XCTAssertEqual(report.voltage, 48.31)
        XCTAssertEqual(report.cellsMv.first, 3700)
        XCTAssertNil(report.manufactured)
    }

    func testTheBatteryIsReadFromABoardThatSplitsLongReplies() async throws {
        let (scooter, session) = try await connected { scooter in
            scooter.maxWordsPerReply = 4
            scooter.set(board: 0x07, index: 0x10, bytes: Self.packInfo)
            scooter.set(board: 0x07, index: 0x30, bytes: Self.packLive)
            scooter.set(board: 0x07, index: 0x40, bytes: Self.packCells)
        }
        let report = await BatteryReport.read(from: session)
        XCTAssertEqual(report.serial, "TESTPACK000001")
        XCTAssertEqual(report.voltage, 48.31)
        XCTAssertEqual(report.cellsMv, (0 ..< 13).map { 3700 + $0 })
        XCTAssertTrue(scooter.readRequests.allSatisfy { $0.words <= 4 })
        XCTAssertEqual(scooter.readRequests.filter { $0.index >= 0x40 && $0.index <= 0x4C }.map(\.index), [0x40, 0x44, 0x48, 0x4C])
    }

    func testChargingIsInferredFromARisingChargeLevel() {
        var tracker = ChargeTracker()
        tracker.record(53.2, at: start)
        tracker.record(53.3, at: start.addingTimeInterval(60))
        XCTAssertFalse(tracker.isCharging)

        tracker.record(53.4, at: start.addingTimeInterval(120))
        XCTAssertTrue(tracker.isCharging)
        XCTAssertEqual(tracker.ratePerHour ?? 0, 6, accuracy: 1e-6)
        XCTAssertEqual(tracker.estimatedTime(reaching: 54.4)?.timeIntervalSince(start) ?? 0, 120 + 600, accuracy: 1)

        tracker.record(53.0, at: start.addingTimeInterval(180))
        XCTAssertFalse(tracker.isCharging)
        XCTAssertEqual(tracker.samples.count, 1)
    }

    func testOldChargeSamplesFallOutOfTheWindow() {
        var tracker = ChargeTracker()
        tracker.record(50, at: start)
        tracker.record(50.1, at: start.addingTimeInterval(ChargeTracker.window + 60))
        XCTAssertEqual(tracker.samples.count, 1)
        XCTAssertFalse(tracker.isCharging)
    }

    func testTheChargedAlertFiresOnceWhenTheTargetIsCrossed() {
        var alert = ChargeAlert(target: 80)
        XCTAssertFalse(alert.observe(90))
        XCTAssertFalse(alert.observe(79))
        XCTAssertTrue(alert.observe(80))
        XCTAssertFalse(alert.observe(81))
        XCTAssertFalse(alert.observe(78))
        XCTAssertTrue(alert.observe(80))
    }

    func testASpeedLimitIsWrittenReadBackAndTheOriginalKept() async throws {
        let (scooter, session) = try await connected { $0.set(.speedLimit, 0) }

        let first = try await SpeedLimitControl.apply(25, ratedKmh: 45, original: nil, session: session, settle: .zero)
        XCTAssertEqual(first.result, .confirmed(25))
        XCTAssertEqual(first.original, 0)

        let second = try await SpeedLimitControl.apply(30, ratedKmh: 45, original: first.original, session: session, settle: .zero)
        XCTAssertEqual(second.result, .confirmed(30))
        XCTAssertEqual(second.original, 0)
        XCTAssertEqual(scooter.writes.map(\.value), [25, 30])
    }

    func testASpeedLimitTheScooterIgnoresIsReportedAsAMismatch() async throws {
        let (scooter, session) = try await connected { $0.set(.speedLimit, 0) }
        scooter.ignoresWrites = true
        let outcome = try await SpeedLimitControl.apply(25, ratedKmh: 45, original: nil, session: session, settle: .zero)
        XCTAssertEqual(outcome.result, .mismatch(0))
    }

    func testUnlockingTopSpeedWritesFiveHundredKeepsTheOriginalAndTogglesBack() async throws {
        let (scooter, session) = try await connected { $0.set(.topSpeed, 450) }

        let unlock = try await TopSpeedControl.apply(unlocked: true, original: nil, session: session, settle: .zero)
        XCTAssertEqual(unlock.result, .confirmed(.unlocked))
        XCTAssertEqual(unlock.original, 450)

        let relock = try await TopSpeedControl.apply(unlocked: false, original: unlock.original, session: session, settle: .zero)
        XCTAssertEqual(relock.result, .confirmed(.locked))
        XCTAssertEqual(relock.original, 450)
        XCTAssertEqual(scooter.writes.map(\.value), [500, 450])
        XCTAssertEqual(scooter.writes.map(\.register.index), [0xE3, 0xE3])
    }

    func testTopSpeedTheScooterIgnoresIsReportedAsAMismatch() async throws {
        let (scooter, session) = try await connected { $0.set(.topSpeed, 450) }
        scooter.ignoresWrites = true
        let outcome = try await TopSpeedControl.apply(unlocked: true, original: nil, session: session, settle: .zero)
        XCTAssertEqual(outcome.result, .mismatch(.locked))
    }

    func testTopSpeedStateReadsTheRegister() {
        XCTAssertEqual(TopSpeedState(register: 450), .locked)
        XCTAssertEqual(TopSpeedState(register: 500), .unlocked)
        XCTAssertEqual(TopSpeedState(register: 480), .other(480))
        XCTAssertEqual(TopSpeedState(register: 500).kmh, 50)
        XCTAssertEqual(TopSpeedState(register: 450).kmh, 45)
    }

    func testSpeedLimitsOutsideTheRatedRangeAreRefusedBeforeSending() async throws {
        let (scooter, session) = try await connected { $0.set(.speedLimit, 0) }
        for limit in [10, 46, 60] {
            do {
                _ = try await SpeedLimitControl.apply(limit, ratedKmh: 45, original: nil, session: session, settle: .zero)
                XCTFail("\(limit) should be refused")
            } catch {
                XCTAssertEqual(error as? ScooterControlError, .limitOutOfRange)
            }
        }
        XCTAssertTrue(scooter.writes.isEmpty)
        XCTAssertEqual(SpeedLimitControl.choices(ratedKmh: 45).first, 0)
        XCTAssertEqual(SpeedLimitControl.choices(ratedKmh: 45).last, 45)
        XCTAssertEqual(SpeedLimitControl.ratedKmh(fromRegister: 450), 45)
    }

    func testPowerOffIsBlockedWhileRidingOrMoving() async throws {
        XCTAssertTrue(VehicleControl.powerOffAllowed(rideActive: false, speedKmh: 0))
        XCTAssertTrue(VehicleControl.powerOffAllowed(rideActive: false, speedKmh: nil))
        XCTAssertFalse(VehicleControl.powerOffAllowed(rideActive: true, speedKmh: 0))
        XCTAssertFalse(VehicleControl.powerOffAllowed(rideActive: false, speedKmh: 3.2))

        let (scooter, session) = try await connected { $0.set(.mainPower, 429) }
        do {
            _ = try await VehicleControl.perform(.powerOff, ident: ident, session: session, rideActive: false, speedKmh: 12, settle: .zero)
            XCTFail("power off while moving must be refused")
        } catch {
            XCTAssertEqual(error as? ScooterControlError, .powerOffWhileRiding)
        }
        XCTAssertTrue(scooter.actions.isEmpty)
    }

    func testPowerActionsReportWhetherThePowerStateChanged() async throws {
        let (scooter, session) = try await connected { $0.set(.mainPower, 421) }
        scooter.onAction = { action, scooter in
            if action == .powerOn { scooter.set(.mainPower, 429) }
        }

        let on = try await VehicleControl.perform(.powerOn, ident: ident, session: session, rideActive: false, speedKmh: 0, settle: .zero)
        XCTAssertEqual(on, .stateChanged(from: 421, to: 429))

        let off = try await VehicleControl.perform(.powerOff, ident: ident, session: session, rideActive: false, speedKmh: 0, settle: .zero)
        XCTAssertEqual(off, .stateUnchanged(429))

        let seat = try await VehicleControl.perform(.openSeat, ident: ident, session: session, rideActive: true, speedKmh: 20, settle: .zero)
        XCTAssertEqual(seat, .sent)
        XCTAssertEqual(scooter.actions.map(\.action), [.powerOn, .powerOff, .openSeat])
        XCTAssertTrue(scooter.actions.allSatisfy { $0.ident == ident })
    }

    func testScooterSettingsDefaultAndPersist() {
        let name = "scooter-controls-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(85, forKey: AppSettings.Key.chargeNotifyTarget)

        let settings = AppSettings(defaults: defaults)
        XCTAssertNil(settings.scooterOriginalSpeedLimit)
        XCTAssertFalse(settings.chargeNotify)
        XCTAssertEqual(settings.chargeNotifyTarget, 100)

        settings.scooterOriginalSpeedLimit = 0
        settings.chargeNotifyTarget = 80
        let reopened = AppSettings(defaults: defaults)
        XCTAssertEqual(reopened.scooterOriginalSpeedLimit, 0)
        XCTAssertEqual(reopened.chargeNotifyTarget, 80)
    }
}
