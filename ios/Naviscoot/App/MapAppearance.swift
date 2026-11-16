import Foundation
import UIKit

enum AppearanceChoice: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }
}

enum MapStyle: String, CaseIterable, Identifiable {
    case liberty
    case bright
    case positron
    case dark
    case fiord

    static let night = MapStyle.dark

    var id: String { rawValue }

    var isDark: Bool { self == .dark || self == .fiord }

    static let nightStyleURL = Bundle.main.url(forResource: "liberty-night", withExtension: "json")!

    var url: URL {
        self == .dark ? Self.nightStyleURL : URL(string: "https://tiles.openfreemap.org/styles/\(rawValue)")!
    }

    static func resolve(choice: MapStyle, darkAppearance: Bool, darkAtNight: Bool, isNight: Bool) -> MapStyle {
        if choice.isDark { return choice }
        if darkAppearance || (darkAtNight && isNight) { return night }
        return choice
    }
}

struct MapPalette: Equatable {
    let casing: UIColor
    let verified: UIColor
    let unverified: UIColor
    let forbidden: UIColor
    let forbiddenCasing: UIColor
    let otherRoute: UIColor
    let ridden: UIColor
    let endpointFill: UIColor
    let endpointStroke: UIColor
    let stopFill: UIColor
    let stopStroke: UIColor
    let stopText: UIColor
    let halo: UIColor

    static let light = MapPalette(
        casing: .white,
        verified: Theme.verifiedUI,
        unverified: Theme.unverifiedUI,
        forbidden: Theme.dangerUI,
        forbiddenCasing: .clear,
        otherRoute: Theme.otherRouteUI,
        ridden: Theme.riddenUI,
        endpointFill: .white,
        endpointStroke: Theme.inkUI,
        stopFill: Theme.inkUI,
        stopStroke: .white,
        stopText: .white,
        halo: Theme.verifiedUI.withAlphaComponent(0.18)
    )

    static let dark = MapPalette(
        casing: UIColor(hex: 0x0B1220),
        verified: UIColor(hex: 0x4C8DFF),
        unverified: UIColor(hex: 0xFF9A3D),
        forbidden: UIColor(hex: 0xFF4D5E),
        forbiddenCasing: UIColor(hex: 0x0B1220),
        otherRoute: UIColor(hex: 0x7C8798),
        ridden: UIColor(hex: 0x5E6673),
        endpointFill: UIColor(hex: 0x111827),
        endpointStroke: .white,
        stopFill: UIColor(hex: 0xF3F4F6),
        stopStroke: UIColor(hex: 0x111827),
        stopText: UIColor(hex: 0x111827),
        halo: UIColor(hex: 0x4C8DFF).withAlphaComponent(0.28)
    )

    static func palette(for style: MapStyle) -> MapPalette {
        style.isDark ? dark : light
    }
}

struct AppClock {
    static let simulatedClockKey = "NaviscootSimClock"
    static let shared = AppClock(defaults: .standard)

    let simulatedStart: Date?
    private let launch: Date

    init(defaults: UserDefaults, launch: Date = Date()) {
        simulatedStart = defaults.string(forKey: Self.simulatedClockKey).flatMap { ISO8601DateFormatter().date(from: $0) }
        self.launch = launch
    }

    func now(current: Date = Date()) -> Date {
        guard let simulatedStart else { return current }
        return simulatedStart.addingTimeInterval(current.timeIntervalSince(launch))
    }
}
