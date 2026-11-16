import SwiftUI
import UIKit

enum Theme {
    static let ink = Color(light: 0x111827, dark: 0xF3F4F6)
    static let muted = Color(light: 0x4B5563, dark: 0xA1A9B6)
    static let body = Color(light: 0x374151, dark: 0xD1D5DB)
    static let line = Color(light: 0xD1D5DB, dark: 0x3A4352)
    static let verified = Color(light: 0x0B5FD9, dark: 0x3B82F6)
    static let verifiedText = Color(light: 0x084AA8, dark: 0x8AB8FF)
    static let unverified = Color(light: 0xC2410C, dark: 0xF97316)
    static let unverifiedText = Color(light: 0x9A3412, dark: 0xFDBA74)
    static let danger = Color(light: 0xB42318, dark: 0xD92D20)
    static let dangerText = Color(light: 0xB42318, dark: 0xFF8A80)
    static let iconBackground = Color(light: 0xEEF2F7, dark: 0x2C3442)
    static let selectedBackground = Color(light: 0xE8F0FC, dark: 0x17305A)
    static let surface = Color(light: 0xFFFFFF, dark: 0x1B212B)
    static let screen = Color(light: 0xFFFFFF, dark: 0x0F141B)
    static let warningBackground = Color(light: 0xFFF1E7, dark: 0x3A2112)
    static let connected = Color(light: 0x15803D, dark: 0x22C55E)

    static let bannerFill = Color(hex: 0x111827)
    static let signInk = Color(hex: 0x111827)

    static let verifiedUI = UIColor(hex: 0x0B5FD9)
    static let unverifiedUI = UIColor(hex: 0xC2410C)
    static let dangerUI = UIColor(hex: 0xB42318)
    static let inkUI = UIColor(hex: 0x111827)
    static let otherRouteUI = UIColor(hex: 0x8A94A6)
    static let riddenUI = UIColor(hex: 0xA3ACB9)

    static func barColor(for stretchClass: StretchClass) -> Color {
        switch stretchClass {
        case .carriageway: ink
        case .mopedPath: verified
        case .unverified: unverified
        case .forbidden: danger
        }
    }

    static func labelColor(for stretchClass: StretchClass) -> Color {
        switch stretchClass {
        case .carriageway: ink
        case .mopedPath: verifiedText
        case .unverified: unverifiedText
        case .forbidden: dangerText
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
