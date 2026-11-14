import AVFoundation
import FerrostarCore
import Foundation

struct SpokenLine: Equatable {
    let text: String
    let language: String?
}

final class DutchSpeechSynthesizer: SpeechSynthesizer {
    static let language = "nl-NL"

    private let synthesizer: SpeechSynthesizer
    private let voice: AVSpeechSynthesisVoice?
    private let onSpeak: (SpokenLine) -> Void

    init(
        synthesizer: SpeechSynthesizer = AVSpeechSynthesizer(),
        voice: AVSpeechSynthesisVoice? = AVSpeechSynthesisVoice(language: DutchSpeechSynthesizer.language),
        onSpeak: @escaping (SpokenLine) -> Void = { _ in }
    ) {
        self.synthesizer = synthesizer
        self.voice = voice
        self.onSpeak = onSpeak
    }

    var isSpeaking: Bool { synthesizer.isSpeaking }

    func speak(_ utterance: AVSpeechUtterance) {
        let dutch = Self.dutchUtterance(from: utterance, voice: voice)
        onSpeak(SpokenLine(text: dutch.speechString, language: dutch.voice?.language))
        synthesizer.speak(dutch)
    }

    @discardableResult
    func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool {
        synthesizer.stopSpeaking(at: boundary)
    }

    static func dutchUtterance(from utterance: AVSpeechUtterance, voice: AVSpeechSynthesisVoice?) -> AVSpeechUtterance {
        let dutch = AVSpeechUtterance(string: plainText(utterance.speechString))
        dutch.voice = voice
        return dutch
    }

    static func plainText(_ text: String) -> String {
        guard text.contains("<") else { return text }
        return text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum Dutch {
    static func distance(_ meters: Double) -> String {
        let step: Double = meters < 100 ? 10 : 50
        let roundedMeters = max(Int(step), Int((meters / step).rounded() * step))
        if roundedMeters < 1000 {
            return "\(roundedMeters) meter"
        }
        let tenths = Int((meters / 100).rounded())
        if tenths % 10 == 0 {
            return "\(tenths / 10) kilometer"
        }
        return "\(tenths / 10),\(tenths % 10) kilometer"
    }

    static func announcement(for alert: UnverifiedAlert) -> String {
        switch alert {
        case let .ahead(_, distanceM, lengthM):
            "Let op: over \(distance(distanceM)) een onbevestigd fietspad van \(distance(Double(lengthM)))."
        case let .inside(_, remainingM):
            "Let op: u rijdt op een onbevestigd fietspad, nog \(distance(remainingM))."
        }
    }
}
