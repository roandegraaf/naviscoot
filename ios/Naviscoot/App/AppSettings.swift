import Foundation
import Observation

enum Language: String, CaseIterable, Codable {
    case dutch = "nl"
    case english = "en"

    static var current: Language { AppSettings.shared.language }

    var locale: Locale {
        switch self {
        case .dutch: Locale(identifier: "nl_NL")
        case .english: Locale(identifier: "en_GB")
        }
    }

    var speechCode: String {
        switch self {
        case .dutch: "nl-NL"
        case .english: "en-GB"
        }
    }

    var bundle: Bundle { Self.bundles[self] ?? .main }

    private static let bundles: [Language: Bundle] = Dictionary(uniqueKeysWithValues: allCases.compactMap { language in
        let host = Bundle(for: AppSettings.self)
        guard let path = host.path(forResource: language.rawValue, ofType: "lproj"), let bundle = Bundle(path: path) else { return nil }
        return (language, bundle)
    })

    static func preferred(from preferences: [String]) -> Language {
        let codes = preferences.compactMap { Locale(identifier: $0).language.languageCode?.identifier }
        return codes.lazy.compactMap(Language.init(rawValue:)).first ?? .english
    }
}

enum LanguageChoice: String, CaseIterable, Identifiable {
    case system
    case dutch = "nl"
    case english = "en"

    var id: String { rawValue }

    func resolved(preferences: [String] = Locale.preferredLanguages) -> Language {
        switch self {
        case .system: Language.preferred(from: preferences)
        case .dutch: .dutch
        case .english: .english
        }
    }
}

@Observable
final class AppSettings {
    enum Key {
        static let language = "settings.language"
        static let verifiedOnlyByDefault = "settings.verifiedOnlyByDefault"
        static let avoidFerries = "settings.avoidFerries"
        static let avoidUnpaved = "settings.avoidUnpaved"
        static let avoidMainRoads = "settings.avoidMainRoads"
        static let appearance = "settings.appearance"
        static let mapStyle = "settings.mapStyle"
        static let darkMapAtNight = "settings.darkMapAtNight"
        static let northUp = "settings.northUp"
        static let threeD = "settings.threeD"
        static let autoZoom = "settings.autoZoom"
        static let guidanceMode = "settings.guidanceMode"
        static let voiceDutch = "settings.voice.nl"
        static let voiceEnglish = "settings.voice.en"
        static let speechRate = "settings.speechRate"
        static let speechVolume = "settings.speechVolume"
        static let speedingAlert = "settings.speedingAlert"
        static let speedingTolerance = "settings.speedingTolerance"
        static let scooterSerial = "settings.scooterSerial"
        static let scooterPeripheralID = "settings.scooterPeripheralID"
        static let rangeMargin = "settings.rangeMargin"
        static let turnBackWarning = "settings.turnBackWarning"
        static let scooterOriginalSpeedLimit = "settings.scooterOriginalSpeedLimit"
        static let scooterOriginalTopSpeed = "settings.scooterOriginalTopSpeed"
        static let chargeNotify = "settings.chargeNotify"
        static let chargeNotifyTarget = "settings.chargeNotifyTarget"
    }

    static let speedingToleranceRange = 0 ... 15
    static let rangeMarginRange = 0 ... 40
    static let chargeTargets = [80, 90, 100]

    static let shared = AppSettings(defaults: .standard)

    var languageChoice: LanguageChoice {
        didSet { defaults.set(languageChoice.rawValue, forKey: Key.language) }
    }

    var verifiedOnlyByDefault: Bool {
        didSet { defaults.set(verifiedOnlyByDefault, forKey: Key.verifiedOnlyByDefault) }
    }

    var avoidFerries: Bool {
        didSet { defaults.set(avoidFerries, forKey: Key.avoidFerries) }
    }

    var avoidUnpaved: Bool {
        didSet { defaults.set(avoidUnpaved, forKey: Key.avoidUnpaved) }
    }

    var avoidMainRoads: Bool {
        didSet { defaults.set(avoidMainRoads, forKey: Key.avoidMainRoads) }
    }

    var appearance: AppearanceChoice {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
    }

    var mapStyle: MapStyle {
        didSet { defaults.set(mapStyle.rawValue, forKey: Key.mapStyle) }
    }

    var darkMapAtNight: Bool {
        didSet { defaults.set(darkMapAtNight, forKey: Key.darkMapAtNight) }
    }

    var northUp: Bool {
        didSet { defaults.set(northUp, forKey: Key.northUp) }
    }

    var threeD: Bool {
        didSet { defaults.set(threeD, forKey: Key.threeD) }
    }

    var autoZoom: Bool {
        didSet { defaults.set(autoZoom, forKey: Key.autoZoom) }
    }

    var guidanceMode: GuidanceMode {
        didSet { defaults.set(guidanceMode.rawValue, forKey: Key.guidanceMode) }
    }

    var voiceDutch: String {
        didSet { defaults.set(voiceDutch, forKey: Key.voiceDutch) }
    }

    var voiceEnglish: String {
        didSet { defaults.set(voiceEnglish, forKey: Key.voiceEnglish) }
    }

    var speechRatePercent: Int {
        didSet { defaults.set(speechRatePercent, forKey: Key.speechRate) }
    }

    var speechVolumePercent: Int {
        didSet { defaults.set(speechVolumePercent, forKey: Key.speechVolume) }
    }

    var speedingAlert: Bool {
        didSet { defaults.set(speedingAlert, forKey: Key.speedingAlert) }
    }

    var speedingToleranceKmh: Int {
        didSet { defaults.set(speedingToleranceKmh, forKey: Key.speedingTolerance) }
    }

    var scooterSerial: String {
        didSet { defaults.set(scooterSerial, forKey: Key.scooterSerial) }
    }

    var scooterPeripheralID: String {
        didSet { defaults.set(scooterPeripheralID, forKey: Key.scooterPeripheralID) }
    }

    var rangeMarginPercent: Int {
        didSet { defaults.set(rangeMarginPercent, forKey: Key.rangeMargin) }
    }

    var turnBackWarning: Bool {
        didSet { defaults.set(turnBackWarning, forKey: Key.turnBackWarning) }
    }

    var scooterOriginalSpeedLimit: Int? {
        didSet { defaults.set(scooterOriginalSpeedLimit, forKey: Key.scooterOriginalSpeedLimit) }
    }

    var scooterOriginalTopSpeed: Int? {
        didSet { defaults.set(scooterOriginalTopSpeed, forKey: Key.scooterOriginalTopSpeed) }
    }

    var chargeNotify: Bool {
        didSet { defaults.set(chargeNotify, forKey: Key.chargeNotify) }
    }

    var chargeNotifyTarget: Int {
        didSet { defaults.set(chargeNotifyTarget, forKey: Key.chargeNotifyTarget) }
    }

    var language: Language { languageChoice.resolved() }

    func voiceIdentifier(for language: Language) -> String? {
        let identifier = switch language {
        case .dutch: voiceDutch
        case .english: voiceEnglish
        }
        return identifier.isEmpty ? nil : identifier
    }

    func setVoiceIdentifier(_ identifier: String?, for language: Language) {
        switch language {
        case .dutch: voiceDutch = identifier ?? ""
        case .english: voiceEnglish = identifier ?? ""
        }
    }

    func speechSettings(for language: Language) -> SpeechSettings {
        SpeechSettings(
            mode: guidanceMode,
            voiceIdentifier: voiceIdentifier(for: language),
            ratePercent: speechRatePercent,
            volumePercent: speechVolumePercent
        )
    }

    var followOptions: RideCamera.FollowOptions {
        RideCamera.FollowOptions(northUp: northUp, threeD: threeD, autoZoom: autoZoom)
    }

    var routeAvoid: RouteAvoid {
        RouteAvoid(ferries: avoidFerries, unpaved: avoidUnpaved, mainRoads: avoidMainRoads)
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        languageChoice = defaults.string(forKey: Key.language).flatMap(LanguageChoice.init(rawValue:)) ?? .system
        verifiedOnlyByDefault = defaults.bool(forKey: Key.verifiedOnlyByDefault)
        avoidFerries = defaults.bool(forKey: Key.avoidFerries)
        avoidUnpaved = defaults.bool(forKey: Key.avoidUnpaved)
        avoidMainRoads = defaults.bool(forKey: Key.avoidMainRoads)
        appearance = defaults.string(forKey: Key.appearance).flatMap(AppearanceChoice.init(rawValue:)) ?? .system
        mapStyle = defaults.string(forKey: Key.mapStyle).flatMap(MapStyle.init(rawValue:)) ?? .liberty
        darkMapAtNight = defaults.object(forKey: Key.darkMapAtNight) == nil || defaults.bool(forKey: Key.darkMapAtNight)
        northUp = defaults.bool(forKey: Key.northUp)
        threeD = defaults.object(forKey: Key.threeD) == nil || defaults.bool(forKey: Key.threeD)
        autoZoom = defaults.bool(forKey: Key.autoZoom)
        guidanceMode = defaults.string(forKey: Key.guidanceMode).flatMap(GuidanceMode.init(rawValue:)) ?? .all
        voiceDutch = defaults.string(forKey: Key.voiceDutch) ?? ""
        voiceEnglish = defaults.string(forKey: Key.voiceEnglish) ?? ""
        speechRatePercent = Self.integer(defaults, Key.speechRate, default: 100, in: SpeechSettings.ratePercentRange)
        speechVolumePercent = Self.integer(defaults, Key.speechVolume, default: 100, in: SpeechSettings.volumePercentRange)
        speedingAlert = defaults.bool(forKey: Key.speedingAlert)
        speedingToleranceKmh = Self.integer(defaults, Key.speedingTolerance, default: 5, in: Self.speedingToleranceRange)
        scooterSerial = defaults.string(forKey: Key.scooterSerial) ?? ""
        scooterPeripheralID = defaults.string(forKey: Key.scooterPeripheralID) ?? ""
        rangeMarginPercent = Self.integer(defaults, Key.rangeMargin, default: 15, in: Self.rangeMarginRange)
        turnBackWarning = defaults.object(forKey: Key.turnBackWarning) == nil || defaults.bool(forKey: Key.turnBackWarning)
        scooterOriginalSpeedLimit = defaults.object(forKey: Key.scooterOriginalSpeedLimit) as? Int
        scooterOriginalTopSpeed = defaults.object(forKey: Key.scooterOriginalTopSpeed) as? Int
        chargeNotify = defaults.bool(forKey: Key.chargeNotify)
        let target = defaults.integer(forKey: Key.chargeNotifyTarget)
        chargeNotifyTarget = Self.chargeTargets.contains(target) ? target : 100
    }

    private static func integer(_ defaults: UserDefaults, _ key: String, default value: Int, in range: ClosedRange<Int>) -> Int {
        guard defaults.object(forKey: key) != nil else { return value }
        return min(max(defaults.integer(forKey: key), range.lowerBound), range.upperBound)
    }
}
