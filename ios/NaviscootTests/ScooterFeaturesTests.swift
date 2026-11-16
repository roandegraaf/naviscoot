@testable import Naviscoot
import XCTest

final class ScooterFeaturesTests: XCTestCase {
    private let serial = "TESTDEVICE0001"
    private let password = Array(0x10 ... 0x1F as ClosedRange<UInt8>)
    private let segwayAppFlags = 0x5CAE
    private let segwayAppControlFlags = 0x000C

    private func connected(_ configure: (SimulatedScooter) -> Void = { _ in }) async throws -> (SimulatedScooter, NinebotSession) {
        let scooter = SimulatedScooter(serial: serial, password: password)
        configure(scooter)
        let session = NinebotSession(transport: scooter, serial: serial, password: password, handshakeTimeout: .milliseconds(200), readTimeout: .milliseconds(100), listenWindow: .milliseconds(20))
        try await session.authenticate()
        return (scooter, session)
    }

    func testFlagsReadFromARealE110SMatchTheSegwayAppSwitches() async throws {
        let (_, session) = try await connected {
            $0.set(.featureFlags, self.segwayAppFlags)
            $0.set(.controlFlags, self.segwayAppControlFlags)
        }
        let states = await ScooterFeatureControl.read(from: session)
        XCTAssertEqual(states, [
            .seatDetection: true, .parkingDetection: true, .assistMode: true, .reverse: false, .showRange: true,
            .extendedRange: true, .streamlineTaillight: true, .indicatorAutoOff: true, .indicatorSound: false,
        ])
    }

    func testTogglingAFeatureChangesOnlyItsBitAndReadsItBack() async throws {
        let (scooter, session) = try await connected { $0.set(.featureFlags, self.segwayAppFlags) }

        let off = try await ScooterFeatureControl.apply(.feature(.seatDetection), on: false, session: session, rideActive: false, speedKmh: 0, settle: .zero)
        XCTAssertEqual(off, .confirmed(false))
        XCTAssertEqual(scooter.value(.featureFlags), segwayAppFlags | 0x0200)

        let on = try await ScooterFeatureControl.apply(.feature(.reverse), on: true, session: session, rideActive: false, speedKmh: nil, settle: .zero)
        XCTAssertEqual(on, .confirmed(true))
        XCTAssertEqual(scooter.writes.map(\.value), [segwayAppFlags | 0x0200, segwayAppFlags | 0x0200 | 0x2000])
    }

    func testIndicatorSoundLivesInTheControlFlagsAndIsInverted() async throws {
        let (scooter, session) = try await connected { $0.set(.controlFlags, self.segwayAppControlFlags) }
        let result = try await ScooterFeatureControl.apply(.feature(.indicatorSound), on: true, session: session, rideActive: false, speedKmh: 0, settle: .zero)
        XCTAssertEqual(result, .confirmed(true))
        XCTAssertEqual(scooter.value(.controlFlags), 0x0004)
    }

    func testAFlagTheScooterIgnoresIsReportedAsAMismatch() async throws {
        let (scooter, session) = try await connected { $0.set(.featureFlags, self.segwayAppFlags) }
        scooter.ignoresWrites = true
        let result = try await ScooterFeatureControl.apply(.feature(.showRange), on: false, session: session, rideActive: false, speedKmh: 0, settle: .zero)
        XCTAssertEqual(result, .mismatch(true))
    }

    func testFeaturesCannotChangeWhileRidingOrMoving() async throws {
        let (scooter, session) = try await connected { $0.set(.featureFlags, self.segwayAppFlags) }
        for (rideActive, speed) in [(true, 0.0), (false, 4.5)] {
            do {
                _ = try await ScooterFeatureControl.apply(.feature(.seatDetection), on: false, session: session, rideActive: rideActive, speedKmh: speed, settle: .zero)
                XCTFail("a change while riding must be refused")
            } catch {
                XCTAssertEqual(error as? ScooterControlError, .settingWhileRiding)
            }
        }
        XCTAssertTrue(scooter.writes.isEmpty)
    }

    func testTheTimeZoneIsWrittenOnlyWhenItDiffersFromThePhone() async throws {
        let amsterdam = TimeZone(identifier: "Europe/Amsterdam")!
        let winter = Date(timeIntervalSince1970: 1_794_700_000)
        let summer = Date(timeIntervalSince1970: 1_783_000_000)
        let (scooter, session) = try await connected { $0.set(.timeZone, 60) }

        let unchanged = try await ScooterClock.sync(session: session, zone: amsterdam, now: winter, settle: .zero)
        XCTAssertEqual(unchanged, .alreadySet(minutes: 60))
        XCTAssertTrue(scooter.writes.isEmpty)

        let updated = try await ScooterClock.sync(session: session, zone: amsterdam, now: summer, settle: .zero)
        XCTAssertEqual(updated, .updated(from: 60, to: 120))
        XCTAssertEqual(scooter.value(.timeZone), 120)
    }

    func testEnergyRecoveryLevelsMatchTheSegwayApp() {
        XCTAssertEqual(EnergyRecovery(registerValue: 0x5CA6), .off)
        XCTAssertEqual(EnergyRecovery(registerValue: 0x5CAE), .weak)
        XCTAssertEqual(EnergyRecovery(registerValue: 0x5CB6), .strong)
        XCTAssertNil(EnergyRecovery(registerValue: 0x5CBE))
    }

    func testChangingEnergyRecoveryLeavesTheOtherFlagsAlone() async throws {
        let (scooter, session) = try await connected { $0.set(.featureFlags, self.segwayAppFlags) }

        let strong = try await ScooterFeatureControl.apply(.strong, session: session, rideActive: false, speedKmh: 0, settle: .zero)
        XCTAssertEqual(strong, .confirmed(.strong))
        XCTAssertEqual(scooter.value(.featureFlags), 0x5CB6)

        let off = try await ScooterFeatureControl.apply(.off, session: session, rideActive: false, speedKmh: 0, settle: .zero)
        XCTAssertEqual(off, .confirmed(.off))
        XCTAssertEqual(scooter.value(.featureFlags), 0x5CA6)
        let level = await ScooterFeatureControl.readRecovery(from: session)
        XCTAssertEqual(level, .off)
    }

    func testEnergyRecoveryCannotChangeWhileRiding() async throws {
        let (scooter, session) = try await connected { $0.set(.featureFlags, self.segwayAppFlags) }
        do {
            _ = try await ScooterFeatureControl.apply(.strong, session: session, rideActive: true, speedKmh: 0, settle: .zero)
            XCTFail("a change while riding must be refused")
        } catch {
            XCTAssertEqual(error as? ScooterControlError, .settingWhileRiding)
        }
        XCTAssertTrue(scooter.writes.isEmpty)
    }

    func testNegativeOffsetsRoundTripThroughTheRegister() {
        XCTAssertEqual(ScooterClock.registerValue(minutes: -300), 0xFED4)
        XCTAssertEqual(ScooterClock.minutes(fromRegister: 0xFED4), -300)
        XCTAssertEqual(Strings.utcOffset(60), "UTC+1:00")
        XCTAssertEqual(Strings.utcOffset(-210), "UTC−3:30")
    }
}
