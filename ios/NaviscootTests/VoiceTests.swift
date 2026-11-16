import AVFoundation
import FerrostarCore
@testable import Naviscoot
import XCTest

final class VoiceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        suiteName = "VoiceTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testDefaultsKeepTodaysSpeechAndLeaveTheSpokenSpeedingAlertOff() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.guidanceMode, .all)
        XCTAssertNil(settings.voiceIdentifier(for: .dutch))
        XCTAssertNil(settings.voiceIdentifier(for: .english))
        XCTAssertEqual(settings.speechRatePercent, 100)
        XCTAssertEqual(settings.speechVolumePercent, 100)
        XCTAssertFalse(settings.speedingAlert)
        XCTAssertEqual(settings.speedingToleranceKmh, 5)

        let speech = settings.speechSettings(for: .english)
        XCTAssertEqual(speech, SpeechSettings())
        XCTAssertEqual(speech.rate, AVSpeechUtteranceDefaultSpeechRate)
        XCTAssertEqual(speech.volume, 1)
        XCTAssertEqual(AVSpeechUtterance(string: "x").rate, AVSpeechUtteranceDefaultSpeechRate)
        XCTAssertEqual(AVSpeechUtterance(string: "x").volume, 1)
    }

    func testVoiceSettingsPersistPerLanguage() {
        let settings = AppSettings(defaults: defaults)
        settings.guidanceMode = .alertsOnly
        settings.setVoiceIdentifier("voice.nl", for: .dutch)
        settings.setVoiceIdentifier("voice.en", for: .english)
        settings.speechRatePercent = 120
        settings.speechVolumePercent = 70
        settings.speedingAlert = true
        settings.speedingToleranceKmh = 8

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.guidanceMode, .alertsOnly)
        XCTAssertEqual(reloaded.voiceIdentifier(for: .dutch), "voice.nl")
        XCTAssertEqual(reloaded.voiceIdentifier(for: .english), "voice.en")
        XCTAssertEqual(reloaded.speechRatePercent, 120)
        XCTAssertEqual(reloaded.speechVolumePercent, 70)
        XCTAssertTrue(reloaded.speedingAlert)
        XCTAssertEqual(reloaded.speedingToleranceKmh, 8)
        XCTAssertEqual(
            reloaded.speechSettings(for: .dutch),
            SpeechSettings(mode: .alertsOnly, voiceIdentifier: "voice.nl", ratePercent: 120, volumePercent: 70)
        )

        reloaded.setVoiceIdentifier(nil, for: .dutch)
        XCTAssertNil(AppSettings(defaults: defaults).voiceIdentifier(for: .dutch))
    }

    func testLaunchArgumentStringsAreReadAndOutOfRangeValuesAreClamped() {
        defaults.set("off", forKey: AppSettings.Key.guidanceMode)
        defaults.set("130", forKey: AppSettings.Key.speechRate)
        defaults.set("5", forKey: AppSettings.Key.speechVolume)
        defaults.set("YES", forKey: AppSettings.Key.speedingAlert)
        defaults.set("40", forKey: AppSettings.Key.speedingTolerance)
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.guidanceMode, .off)
        XCTAssertEqual(settings.speechRatePercent, 130)
        XCTAssertEqual(settings.speechVolumePercent, 20)
        XCTAssertTrue(settings.speedingAlert)
        XCTAssertEqual(settings.speedingToleranceKmh, 15)
    }

    func testTheModeFilterSeparatesInstructionsFromWarningsAndSpeeding() {
        XCTAssertEqual(SpeechKind.allCases.filter(GuidanceMode.all.allows), [.instruction, .warning, .speeding])
        XCTAssertEqual(SpeechKind.allCases.filter(GuidanceMode.alertsOnly.allows), [.warning, .speeding])
        XCTAssertEqual(SpeechKind.allCases.filter(GuidanceMode.off.allows), [])
    }

    func testMuteSwitchesToOffAndBackToTheLastAudibleMode() {
        XCTAssertEqual(GuidanceMode.all.toggledMute(lastAudible: .all), .off)
        XCTAssertEqual(GuidanceMode.alertsOnly.toggledMute(lastAudible: .alertsOnly), .off)
        XCTAssertEqual(GuidanceMode.off.toggledMute(lastAudible: .alertsOnly), .alertsOnly)
        XCTAssertEqual(GuidanceMode.off.toggledMute(lastAudible: .all), .all)
        XCTAssertEqual(GuidanceMode.off.toggledMute(lastAudible: .off), .all)
    }

    func testSettingsRememberTheLastAudibleModeSoUnmuteRestoresIt() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.lastAudibleGuidanceMode, .all)
        settings.guidanceMode = .alertsOnly
        settings.guidanceMode = .off
        XCTAssertEqual(settings.lastAudibleGuidanceMode, .alertsOnly)
        XCTAssertEqual(settings.guidanceMode.toggledMute(lastAudible: settings.lastAudibleGuidanceMode), .alertsOnly)

        let reopened = AppSettings(defaults: defaults)
        XCTAssertEqual(reopened.guidanceMode, .off)
        XCTAssertEqual(reopened.lastAudibleGuidanceMode, .all)

        settings.guidanceMode = .alertsOnly
        XCTAssertEqual(AppSettings(defaults: defaults).lastAudibleGuidanceMode, .alertsOnly)
    }

    func testAlertsOnlySpeaksWarningsAndSpeedingButNotTurnInstructions() {
        let recorder = Recorder()
        var settings = SpeechSettings(mode: .alertsOnly)
        var decisions: [SpeechDecision] = []
        let speech = GuidanceSpeechSynthesizer(synthesizer: recorder, language: .english, settings: { settings }, audio: audio()) {
            decisions.append($0)
        }

        speech.speak(AVSpeechUtterance(string: "Turn right onto Holkerpad."))
        speech.announce("Caution: in 800 metres, an unverified cycle path of 500 metres.", kind: .warning)
        speech.announce("Slow down: the speed limit is 30.", kind: .speeding)
        speech.speak(AVSpeechUtterance(string: "Turn left."))

        XCTAssertEqual(recorder.utterances.map(\.speechString), [
            "Caution: in 800 metres, an unverified cycle path of 500 metres.",
            "Slow down: the speed limit is 30.",
        ])
        XCTAssertEqual(decisions.map(\.spoken), [false, true, true, false])
        XCTAssertEqual(decisions.map(\.line.kind), [.instruction, .warning, .speeding, .instruction])
        XCTAssertTrue(decisions.allSatisfy { $0.mode == .alertsOnly })

        settings.mode = .off
        speech.announce("Caution", kind: .warning)
        speech.announce("Slow down", kind: .speeding)
        speech.speak(AVSpeechUtterance(string: "Turn left."))
        XCTAssertEqual(recorder.utterances.count, 2)
        XCTAssertEqual(decisions.suffix(3).map(\.spoken), [false, false, false])

        settings.mode = .all
        speech.speak(AVSpeechUtterance(string: "Turn left."))
        XCTAssertEqual(recorder.utterances.last?.speechString, "Turn left.")
    }

    func testEachUtteranceTakesVoiceRateAndVolumeFromTheSettingsAtSpeakTime() throws {
        let recorder = Recorder()
        let other = try XCTUnwrap(
            GuidanceVoices.installed(for: .english).first { $0.identifier != GuidanceVoices.defaultVoice(for: .english)?.identifier },
            "this simulator has only one English voice"
        )
        var settings = SpeechSettings()
        var lines: [SpokenLine] = []
        let speech = GuidanceSpeechSynthesizer(synthesizer: recorder, language: .english, settings: { settings }, audio: audio()) {
            lines.append($0.line)
        }

        speech.speak(AVSpeechUtterance(string: "Turn right."))
        settings = SpeechSettings(mode: .all, voiceIdentifier: other.identifier, ratePercent: 120, volumePercent: 70)
        speech.announce("Caution.", kind: .warning)

        let first = try XCTUnwrap(recorder.utterances.first)
        XCTAssertEqual(first.voice?.identifier, GuidanceVoices.defaultVoice(for: .english)?.identifier)
        XCTAssertEqual(first.rate, AVSpeechUtteranceDefaultSpeechRate)
        XCTAssertEqual(first.volume, 1)

        let second = try XCTUnwrap(recorder.utterances.last)
        XCTAssertEqual(second.voice?.identifier, other.identifier)
        XCTAssertEqual(second.rate, AVSpeechUtteranceDefaultSpeechRate * 1.2, accuracy: 0.0001)
        XCTAssertEqual(second.volume, 0.7, accuracy: 0.0001)
        XCTAssertEqual(lines.last?.voiceIdentifier, other.identifier)
        XCTAssertEqual(lines.last?.language, other.language)
        XCTAssertEqual(lines.last?.rate ?? 0, 0.6, accuracy: 0.0001)
        XCTAssertEqual(lines.last?.volume ?? 0, 0.7, accuracy: 0.0001)
    }

    func testAVoiceOfAnotherLanguageOrAMissingVoiceFallsBackToTheDefault() throws {
        let dutch = try XCTUnwrap(GuidanceVoices.installed(for: .dutch).first)
        XCTAssertEqual(GuidanceVoices.voice(identifier: dutch.identifier, language: .english)?.language, "en-GB")
        XCTAssertEqual(GuidanceVoices.voice(identifier: "com.example.gone", language: .dutch)?.language, "nl-NL")
        XCTAssertEqual(GuidanceVoices.voice(identifier: nil, language: .dutch)?.language, "nl-NL")
        XCTAssertEqual(GuidanceVoices.voice(identifier: dutch.identifier, language: .dutch)?.identifier, dutch.identifier)
    }

    func testOfferedVoicesMatchTheLanguageAndSkipNoveltyVoices() {
        for language in Language.allCases {
            let voices = GuidanceVoices.installed(for: language)
            XCTAssertFalse(voices.isEmpty, "\(language)")
            XCTAssertTrue(voices.allSatisfy { $0.language.hasPrefix(language.rawValue + "-") }, "\(language)")
            XCTAssertTrue(voices.allSatisfy { !$0.voiceTraits.contains(.isNoveltyVoice) }, "\(language)")
        }
    }

    func testTheAudioSessionDucksForPromptsAndReleasesOnlyAfterTheLastOneFinished() {
        let session = FakeSession()
        let prompts = PromptAudio(session: session, schedule: { _, _ in XCTFail("no retry expected") })
        let speech = GuidanceSpeechSynthesizer(synthesizer: Recorder(), language: .english, settings: { SpeechSettings() }, audio: prompts)
        let synth = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: "x")

        speech.speak(AVSpeechUtterance(string: "Turn right."))
        speech.announce("Caution.", kind: .warning)
        XCTAssertEqual(session.calls, [.configure, .activate])
        XCTAssertTrue(prompts.isActive)

        speech.speechSynthesizer(synth, didFinish: utterance)
        XCTAssertEqual(session.calls, [.configure, .activate], "released between two queued prompts")
        speech.speechSynthesizer(synth, didFinish: utterance)
        XCTAssertEqual(session.calls, [.configure, .activate, .deactivate])
        XCTAssertFalse(prompts.isActive)

        speech.speak(AVSpeechUtterance(string: "Turn left."))
        XCTAssertEqual(session.calls.suffix(1), [.activate], "the category is configured once")
        speech.speechSynthesizer(synth, didCancel: utterance)
        XCTAssertEqual(session.calls.suffix(2), [.activate, .deactivate])

        speech.speak(AVSpeechUtterance(string: "Turn left."))
        speech.stopSpeaking(at: .immediate)
        XCTAssertEqual(session.calls.suffix(2), [.activate, .deactivate])

        speech.speak(AVSpeechUtterance(string: "Turn left."))
        speech.release()
        XCTAssertEqual(session.calls.suffix(2), [.activate, .deactivate])
        speech.release()
        speech.speechSynthesizer(synth, didFinish: utterance)
        XCTAssertEqual(session.calls.filter { $0 == .deactivate }.count, 4, "nothing extra once released")
        XCTAssertEqual(session.calls.filter { $0 == .configure }.count, 1)
    }

    func testASuppressedLineNeverTouchesTheAudioSession() {
        let session = FakeSession()
        let speech = GuidanceSpeechSynthesizer(
            synthesizer: Recorder(),
            language: .english,
            settings: { SpeechSettings(mode: .alertsOnly) },
            audio: PromptAudio(session: session)
        )
        speech.speak(AVSpeechUtterance(string: "Turn right."))
        XCTAssertEqual(session.calls, [])
    }

    func testAFailedReleaseIsRetriedUnlessANewPromptStarted() {
        let session = FakeSession()
        var scheduled: [() -> Void] = []
        let prompts = PromptAudio(session: session, schedule: { _, work in scheduled.append(work) })

        prompts.promptStarting()
        session.deactivateFailures = 1
        prompts.promptEnded()
        XCTAssertTrue(prompts.isActive)
        XCTAssertEqual(scheduled.count, 1)
        scheduled.removeFirst()()
        XCTAssertFalse(prompts.isActive)
        XCTAssertEqual(session.calls, [.configure, .activate, .deactivate, .deactivate])

        prompts.promptStarting()
        session.deactivateFailures = 1
        prompts.promptEnded()
        prompts.promptStarting()
        scheduled.removeFirst()()
        XCTAssertTrue(prompts.isActive, "a retry must not cut off a prompt that started after it was scheduled")

        session.deactivateFailures = 10
        prompts.promptEnded()
        for _ in 0 ..< 10 where !scheduled.isEmpty {
            scheduled.removeFirst()()
        }
        XCTAssertEqual(session.calls.suffix(1 + PromptAudio.releaseRetries), Array(repeating: .deactivate, count: 1 + PromptAudio.releaseRetries))
        XCTAssertTrue(scheduled.isEmpty, "retries are capped")
    }

    func testSpeedingAlertsOncePerEpisodeAboveLimitPlusTolerance() {
        var monitor = SpeedingMonitor(toleranceKmh: 5)

        XCTAssertFalse(monitor.update(speedKmh: 34, limitKmh: 30))
        XCTAssertFalse(monitor.isOver)
        XCTAssertFalse(monitor.update(speedKmh: 35, limitKmh: 30))
        XCTAssertFalse(monitor.isOver, "the threshold itself is not over")

        XCTAssertTrue(monitor.update(speedKmh: 37, limitKmh: 30))
        XCTAssertTrue(monitor.isOver)
        XCTAssertFalse(monitor.update(speedKmh: 37, limitKmh: 30))
        XCTAssertFalse(monitor.update(speedKmh: 40, limitKmh: 30))
        XCTAssertTrue(monitor.isOver, "the colour stays while over")

        XCTAssertFalse(monitor.update(speedKmh: 32, limitKmh: 30))
        XCTAssertFalse(monitor.isOver)
        XCTAssertFalse(monitor.update(speedKmh: 30, limitKmh: 30))
        XCTAssertFalse(monitor.update(speedKmh: 37, limitKmh: 30), "re-arms only below the limit")
        XCTAssertTrue(monitor.isOver)

        XCTAssertFalse(monitor.update(speedKmh: 29, limitKmh: 30))
        XCTAssertTrue(monitor.update(speedKmh: 37, limitKmh: 30))
    }

    func testSpeedingWithoutALimitShowsNothingAndDoesNotReArm() {
        var monitor = SpeedingMonitor(toleranceKmh: 5)
        XCTAssertTrue(monitor.update(speedKmh: 37, limitKmh: 30))
        XCTAssertFalse(monitor.update(speedKmh: 37, limitKmh: nil))
        XCTAssertFalse(monitor.isOver)
        XCTAssertFalse(monitor.update(speedKmh: nil, limitKmh: 30))
        XCTAssertFalse(monitor.update(speedKmh: 37, limitKmh: 30))

        XCTAssertFalse(monitor.update(speedKmh: 37, limitKmh: 45), "a higher limit is below the limit, so it re-arms")
        XCTAssertTrue(monitor.update(speedKmh: 37, limitKmh: 30))

        monitor.toleranceKmh = 0
        XCTAssertFalse(monitor.update(speedKmh: 20, limitKmh: 30))
        XCTAssertTrue(monitor.update(speedKmh: 31, limitKmh: 30))
    }

    func testTheSpeedingAlertTextExistsInBothLanguages() {
        XCTAssertEqual(SpokenPhrases.speeding(limitKmh: 30, language: .english), "Slow down: the speed limit is 30.")
        XCTAssertEqual(SpokenPhrases.speeding(limitKmh: 30, language: .dutch), "Let op: je rijdt te hard, de limiet is 30.")
        XCTAssertEqual(Strings.format("settings.speechRate", 120, language: .english), "Speaking rate 120%")
        XCTAssertEqual(Strings.tr("ride.voice.alerts", language: .dutch), "Meldingen")
        XCTAssertEqual(Strings.format("settings.speeding.tolerance", 5, language: .dutch), "Marge 5 km/u")
    }

    private func audio() -> PromptAudio {
        PromptAudio(session: FakeSession())
    }

    private final class Recorder: SpeechSynthesizer {
        var utterances: [AVSpeechUtterance] = []
        var isSpeaking = false
        func speak(_ utterance: AVSpeechUtterance) { utterances.append(utterance) }
        func stopSpeaking(at _: AVSpeechBoundary) -> Bool { true }
    }

    private final class FakeSession: AudioSessionControlling {
        enum Call: Equatable {
            case configure
            case activate
            case deactivate
        }

        var calls: [Call] = []
        var deactivateFailures = 0

        func configureForPrompts() throws { calls.append(.configure) }
        func activate() throws { calls.append(.activate) }

        func deactivate() throws {
            calls.append(.deactivate)
            if deactivateFailures > 0 {
                deactivateFailures -= 1
                throw NSError(domain: NSOSStatusErrorDomain, code: 560_030_580)
            }
        }
    }
}
