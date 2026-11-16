import AVFoundation
import FerrostarCore
import Foundation

enum GuidanceMode: String, CaseIterable, Identifiable {
    case all
    case alertsOnly = "alerts"
    case off

    var id: String { rawValue }

    func allows(_ kind: SpeechKind) -> Bool {
        switch self {
        case .all: true
        case .alertsOnly: kind != .instruction
        case .off: false
        }
    }
}

enum SpeechKind: String, CaseIterable {
    case instruction
    case warning
    case speeding
}

struct SpeechSettings: Equatable {
    static let ratePercentRange = 60 ... 140
    static let volumePercentRange = 20 ... 100
    static let percentStep = 10

    var mode: GuidanceMode = .all
    var voiceIdentifier: String?
    var ratePercent = 100
    var volumePercent = 100

    var rate: Float { AVSpeechUtteranceDefaultSpeechRate * Float(ratePercent) / 100 }
    var volume: Float { Float(volumePercent) / 100 }
}

struct SpokenLine: Equatable {
    let text: String
    let language: String?
    var kind: SpeechKind = .instruction
    var voiceIdentifier: String?
    var rate: Float = AVSpeechUtteranceDefaultSpeechRate
    var volume: Float = 1
}

struct SpeechDecision: Equatable {
    let line: SpokenLine
    let mode: GuidanceMode
    let spoken: Bool
}

enum GuidanceVoices {
    static func installed(for language: Language) -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { matches($0, language) && $0.voiceTraits.isDisjoint(with: [.isNoveltyVoice, .isPersonalVoice]) }
            .sorted { ($0.name, $0.language, $0.identifier) < ($1.name, $1.language, $1.identifier) }
    }

    static func defaultVoice(for language: Language) -> AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice(language: language.speechCode)
    }

    static func voice(identifier: String?, language: Language) -> AVSpeechSynthesisVoice? {
        if let identifier, let voice = AVSpeechSynthesisVoice(identifier: identifier), matches(voice, language) {
            return voice
        }
        return defaultVoice(for: language)
    }

    static func matches(_ voice: AVSpeechSynthesisVoice, _ language: Language) -> Bool {
        voice.language.hasPrefix(language.rawValue + "-")
    }
}

protocol AudioSessionControlling: AnyObject {
    func configureForPrompts() throws
    func activate() throws
    func deactivate() throws
}

final class SystemAudioSession: AudioSessionControlling {
    private let session = AVAudioSession.sharedInstance()

    func configureForPrompts() throws {
        try session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
    }

    func activate() throws {
        try session.setActive(true)
    }

    func deactivate() throws {
        try session.setActive(false, options: .notifyOthersOnDeactivation)
    }
}

final class PromptAudio {
    static let releaseRetries = 3
    static let releaseRetryDelay: TimeInterval = 0.5

    private let session: AudioSessionControlling
    private let schedule: (TimeInterval, @escaping () -> Void) -> Void
    private var configured = false
    private var active = false
    private var pending = 0
    private var promptsStarted = 0

    init(
        session: AudioSessionControlling = SystemAudioSession(),
        schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void = { delay, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    ) {
        self.session = session
        self.schedule = schedule
    }

    var isActive: Bool { active }

    func promptStarting() {
        pending += 1
        promptsStarted += 1
        guard !active else { return }
        do {
            if !configured {
                try session.configureForPrompts()
                configured = true
            }
            try session.activate()
            active = true
        } catch {}
    }

    func promptEnded() {
        pending = max(0, pending - 1)
        if pending == 0 { release(retriesLeft: Self.releaseRetries) }
    }

    func releaseAll() {
        pending = 0
        release(retriesLeft: Self.releaseRetries)
    }

    // setActive(false) fails while the synthesizer's audio is still winding down; retry so other apps don't stay ducked.
    private func release(retriesLeft: Int) {
        guard active else { return }
        do {
            try session.deactivate()
            active = false
        } catch {
            guard retriesLeft > 0 else { return }
            let started = promptsStarted
            schedule(Self.releaseRetryDelay) { [weak self] in
                guard let self, self.promptsStarted == started, self.pending == 0 else { return }
                self.release(retriesLeft: retriesLeft - 1)
            }
        }
    }
}

final class GuidanceSpeechSynthesizer: NSObject, SpeechSynthesizer, AVSpeechSynthesizerDelegate {
    private let synthesizer: SpeechSynthesizer
    private let language: Language
    private let settings: () -> SpeechSettings
    private let audio: PromptAudio
    private let onDecision: (SpeechDecision) -> Void

    init(
        synthesizer: SpeechSynthesizer = AVSpeechSynthesizer(),
        language: Language,
        settings: @escaping () -> SpeechSettings,
        audio: PromptAudio = PromptAudio(),
        onDecision: @escaping (SpeechDecision) -> Void = { _ in }
    ) {
        self.synthesizer = synthesizer
        self.language = language
        self.settings = settings
        self.audio = audio
        self.onDecision = onDecision
        super.init()
        (synthesizer as? AVSpeechSynthesizer)?.delegate = self
    }

    var isSpeaking: Bool { synthesizer.isSpeaking }

    func speak(_ utterance: AVSpeechUtterance) {
        let text = Self.plainText(utterance.speechString)
        onMain { self.say(text, kind: .instruction) }
    }

    func announce(_ text: String, kind: SpeechKind) {
        onMain { self.say(text, kind: kind) }
    }

    @discardableResult
    func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool {
        let stopped = synthesizer.stopSpeaking(at: boundary)
        onMain { self.audio.releaseAll() }
        return stopped
    }

    func release() {
        onMain { self.audio.releaseAll() }
    }

    func speechSynthesizer(_: AVSpeechSynthesizer, didFinish _: AVSpeechUtterance) {
        onMain { self.audio.promptEnded() }
    }

    func speechSynthesizer(_: AVSpeechSynthesizer, didCancel _: AVSpeechUtterance) {
        onMain { self.audio.promptEnded() }
    }

    private func say(_ text: String, kind: SpeechKind) {
        let current = settings()
        let utterance = Self.utterance(
            text,
            voice: GuidanceVoices.voice(identifier: current.voiceIdentifier, language: language),
            settings: current
        )
        let allowed = current.mode.allows(kind)
        let line = SpokenLine(
            text: text,
            language: utterance.voice?.language,
            kind: kind,
            voiceIdentifier: utterance.voice?.identifier,
            rate: utterance.rate,
            volume: utterance.volume
        )
        onDecision(SpeechDecision(line: line, mode: current.mode, spoken: allowed))
        guard allowed else { return }
        audio.promptStarting()
        synthesizer.speak(utterance)
    }

    private func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    static func utterance(_ text: String, voice: AVSpeechSynthesisVoice?, settings: SpeechSettings) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = settings.rate
        utterance.volume = settings.volume
        return utterance
    }

    static func plainText(_ text: String) -> String {
        guard text.contains("<") else { return text }
        return text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct SpeedingMonitor: Equatable {
    var toleranceKmh: Int
    private(set) var isOver = false
    private var armed = true

    init(toleranceKmh: Int) {
        self.toleranceKmh = toleranceKmh
    }

    mutating func update(speedKmh: Int?, limitKmh: Int?) -> Bool {
        guard let speedKmh, let limitKmh else {
            isOver = false
            return false
        }
        if speedKmh < limitKmh { armed = true }
        isOver = speedKmh > limitKmh + toleranceKmh
        guard isOver, armed else { return false }
        armed = false
        return true
    }
}

enum SpokenPhrases {
    static func distance(_ meters: Double, language: Language) -> String {
        let step: Double = meters < 100 ? 10 : 50
        let roundedMeters = max(Int(step), Int((meters / step).rounded() * step))
        if roundedMeters < 1000 {
            return Strings.format("speech.metres", roundedMeters, language: language)
        }
        let tenths = Int((meters / 100).rounded())
        if tenths % 10 == 0 {
            return Strings.format(tenths == 10 ? "speech.kilometre" : "speech.kilometres", "\(tenths / 10)", language: language)
        }
        let value = String(format: "%.1f", locale: language.locale, Double(tenths) / 10)
        return Strings.format("speech.kilometres", value, language: language)
    }

    static func announcement(for alert: UnverifiedAlert, language: Language) -> String {
        switch alert {
        case let .ahead(_, distanceM, lengthM):
            Strings.format(
                "speech.unverifiedAhead",
                distance(distanceM, language: language),
                distance(Double(lengthM), language: language),
                language: language
            )
        case let .inside(_, remainingM):
            Strings.format("speech.unverifiedInside", distance(remainingM, language: language), language: language)
        }
    }

    static func stopReached(_ stop: Destination, next: Destination?, destination: Destination, language: Language) -> String {
        if let next {
            return Strings.format("speech.stopReached.nextStop", stop.title, next.title, language: language)
        }
        return Strings.format("speech.stopReached.destination", stop.title, destination.title, language: language)
    }

    static func speeding(limitKmh: Int, language: Language) -> String {
        Strings.format("speech.speeding", limitKmh, language: language)
    }
}
