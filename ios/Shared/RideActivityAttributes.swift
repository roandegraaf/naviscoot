import ActivityKit
import Foundation

// The app resolves every text in its chosen language, so the extension needs no string catalog or shared settings.
struct RideActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var symbol: String
        var distance: String
        var street: String
        var destination: String
        var arrivalLabel: String
        var arrival: String
        var remaining: String
        var warning: String?
        var arrived: Bool
        var battery: String? = nil
    }
}
