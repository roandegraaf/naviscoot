import SwiftUI
import UIKit

enum Theme {
    static let mapStyleURL = URL(string: "https://tiles.openfreemap.org/styles/liberty")!

    static let ink = Color(hex: 0x111827)
    static let muted = Color(hex: 0x4B5563)
    static let line = Color(hex: 0xD1D5DB)
    static let verified = Color(hex: 0x0B5FD9)
    static let verifiedText = Color(hex: 0x084AA8)
    static let unverified = Color(hex: 0xC2410C)
    static let unverifiedText = Color(hex: 0x9A3412)
    static let danger = Color(hex: 0xB42318)
    static let iconBackground = Color(hex: 0xEEF2F7)

    static let verifiedUI = UIColor(hex: 0x0B5FD9)
    static let unverifiedUI = UIColor(hex: 0xC2410C)
    static let dangerUI = UIColor(hex: 0xB42318)
    static let inkUI = UIColor(hex: 0x111827)

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
        case .forbidden: danger
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
