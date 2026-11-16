@testable import Naviscoot
import XCTest

final class ScooterPrefillTests: XCTestCase {
    private let passwordHex = "101112131415161718191a1b1c1d1e1f"
    private let identHex = "a0a1a2a3a4a5a6a7a8a9aaabacadaeaf"

    private func fresh() -> (AppSettings, ScooterKeychain) {
        let name = "prefill-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let keychain = ScooterKeychain(service: name)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: name)
            keychain.remove(.password)
            keychain.remove(.ident)
        }
        return (AppSettings(defaults: defaults), keychain)
    }

    func testBuildTimeValuesFillAnEmptySetup() {
        let (settings, keychain) = fresh()
        ScooterPrefill.apply(
            info: ["NaviscootScooterSerial": "S1TEST0000", "NaviscootScooterPassword": passwordHex, "NaviscootScooterIdent": identHex],
            settings: settings, keychain: keychain
        )
        XCTAssertEqual(settings.scooterSerial, "S1TEST0000")
        XCTAssertEqual(keychain.value(.password), ScooterPassword.parse(passwordHex))
        XCTAssertEqual(keychain.value(.ident), ScooterPassword.parse(identHex))
    }

    func testValuesSetInTheAppAreKept() {
        let (settings, keychain) = fresh()
        settings.scooterSerial = "S1MINE0000"
        let mine = Array(repeating: UInt8(7), count: 16)
        keychain.save(mine, as: .password)

        ScooterPrefill.apply(
            info: ["NaviscootScooterSerial": "S1TEST0000", "NaviscootScooterPassword": passwordHex],
            settings: settings, keychain: keychain
        )
        XCTAssertEqual(settings.scooterSerial, "S1MINE0000")
        XCTAssertEqual(keychain.value(.password), mine)
    }

    func testEmptyOrMalformedValuesAreIgnored() {
        let (settings, keychain) = fresh()
        ScooterPrefill.apply(
            info: ["NaviscootScooterSerial": " ", "NaviscootScooterPassword": "", "NaviscootScooterIdent": "not-hex"],
            settings: settings, keychain: keychain
        )
        XCTAssertEqual(settings.scooterSerial, "")
        XCTAssertNil(keychain.value(.password))
        XCTAssertNil(keychain.value(.ident))
    }
}
