@testable import Naviscoot
import XCTest

final class SettingsTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let name = "settings-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    func testAFreshInstallFollowsTheSystemAndKeepsVerifiedOnlyOff() {
        let settings = AppSettings(defaults: freshDefaults())
        XCTAssertEqual(settings.languageChoice, .system)
        XCTAssertFalse(settings.verifiedOnlyByDefault)
    }

    func testChangedSettingsAreReadBackByANewInstance() {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.languageChoice = .dutch
        settings.verifiedOnlyByDefault = true

        let reopened = AppSettings(defaults: defaults)
        XCTAssertEqual(reopened.languageChoice, .dutch)
        XCTAssertEqual(reopened.language, .dutch)
        XCTAssertTrue(reopened.verifiedOnlyByDefault)
    }

    func testSystemChoiceResolvesToTheFirstSupportedPreferredLanguage() {
        XCTAssertEqual(LanguageChoice.system.resolved(preferences: ["nl-NL"]), .dutch)
        XCTAssertEqual(LanguageChoice.system.resolved(preferences: ["nl-BE", "en-GB"]), .dutch)
        XCTAssertEqual(LanguageChoice.system.resolved(preferences: ["en-US", "nl-NL"]), .english)
        XCTAssertEqual(LanguageChoice.system.resolved(preferences: ["de-DE", "nl-NL"]), .dutch)
        XCTAssertEqual(LanguageChoice.system.resolved(preferences: ["fr-FR"]), .english)
        XCTAssertEqual(LanguageChoice.dutch.resolved(preferences: ["en-US"]), .dutch)
        XCTAssertEqual(LanguageChoice.english.resolved(preferences: ["nl-NL"]), .english)
    }

    func testStringsResolveAgainstTheChosenLanguageNotTheSystem() {
        XCTAssertEqual(Strings.tr("search.placeholder", language: .dutch), "Adres of plaats")
        XCTAssertEqual(Strings.tr("search.placeholder", language: .english), "Address or place")
        XCTAssertEqual(Strings.format("chip.withLimit", "Onbevestigd pad", 30, language: .dutch), "Onbevestigd pad, limiet 30")
        XCTAssertEqual(Strings.format("chip.withLimit", "Unverified path", 30, language: .english), "Unverified path, limit 30")
        XCTAssertEqual(Strings.format("error.http", 500, " (oops)", language: .english), "The route service answered 500 (oops).")
    }

    func testEveryCatalogEntryHasBothLanguagesWithMatchingPlaceholders() throws {
        func table(_ language: Language) throws -> [String: String] {
            let url = try XCTUnwrap(language.bundle.url(forResource: "Localizable", withExtension: "strings"), "\(language)")
            return try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String], "\(language)")
        }
        let english = try table(.english)
        let dutch = try table(.dutch)
        XCTAssertGreaterThan(english.count, 50)
        XCTAssertEqual(Set(english.keys), Set(dutch.keys))
        for (key, value) in english {
            let translated = try XCTUnwrap(dutch[key])
            XCTAssertFalse(value.isEmpty || value == key, key)
            XCTAssertFalse(translated.isEmpty || translated == key, key)
            XCTAssertEqual(Self.placeholders(value), Self.placeholders(translated), key)
        }
    }

    private static func placeholders(_ text: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: #"%(\d\$)?(@|lld|d|\.\df)"#)
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range, in: text).map { String(text[$0]) } }
            .sorted()
    }
}
