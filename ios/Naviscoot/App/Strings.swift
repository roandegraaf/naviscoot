import Foundation

enum Strings {
    static let searchPlaceholder = "Address or place"
    static let searchFailed = "Search is unavailable. Check your connection."
    static let lookupFailed = "Could not find that address."
    static let noResults = "No results"
    static let addressKind = "Address"
    static let placeKind = "Place"
    static let back = "Back"
    static let to = "To"
    static let waitingForLocation = "Waiting for your location…"
    static let locationDenied = "Location access is off. Allow it in Settings to plan a route."
    static let calculating = "Calculating a legal route…"
    static let retry = "Try again"
    static let carriageway = "Carriageway"
    static let mopedPath = "Moped path (G12a)"
    static let unverified = "Unverified cycle path"
    static let forbidden = "Closed to mopeds (data error)"
    static let verifiedOnly = "Verified roads only"
    static let verifiedOnlyNothingToSkip = "This route has no unverified stretches"
    static let verifiedOnlyActive = "Avoiding unverified cycle paths"
    static let start = "Start"
    static let showOnMap = "Shows these stretches on the map"
    static let apiNotConfigured = "The route service is not configured. Set it in ios/Config/Local.xcconfig."
    static let unauthorized = "The route service rejected the API key."
    static let noRoute = "No legal moped route found to this destination."
    static let serviceUnavailable = "The route service is unavailable. Try again shortly."
    static let classificationFailed = "The route could not be checked for moped access."
    static let routeParseFailed = "The route service sent a route the app cannot read."
    static let networkFailed = "Cannot reach the route service."

    static let end = "End"
    static let report = "Report wrong data here"
    static let reportSending = "Saving report…"
    static let reportSent = "Report saved with your position"
    static let reportRejected = "The route service refused this report."
    static let mute = "Mute voice"
    static let unmute = "Unmute voice"
    static let rerouting = "Off route. Finding a new legal route…"
    static let arrived = "You have arrived"
    static let kmh = "km/h"
    static let startingGuidance = "Starting guidance…"
    static let simulatedRide = "Simulated ride"
    static let simulateDetour = "Detour"
    static let chipCarriageway = "Carriageway"
    static let chipMopedPath = "Moped path"
    static let chipUnverified = "Unverified path"
    static let chipForbidden = "Closed to mopeds"

    static func reportQueued(_ pending: Int) -> String {
        "No connection. Report kept, retrying (\(pending) waiting)"
    }

    static func unverifiedAhead(_ distance: String, length: String) -> String { "Unverified path in \(distance), for \(length)" }
    static func unverifiedInside(_ remaining: String) -> String { "On unverified path, \(remaining) left" }
    static func speedLimit(_ kmh: Int) -> String { "Speed limit \(kmh)" }
    static func reroutes(_ count: Int) -> String { "reroutes \(count)" }

    static func chip(for stretchClass: StretchClass, limit: Int?) -> String {
        let label = switch stretchClass {
        case .carriageway: chipCarriageway
        case .mopedPath: chipMopedPath
        case .unverified: chipUnverified
        case .forbidden: chipForbidden
        }
        guard let limit else { return label }
        return "\(label), limit \(limit)"
    }

    static func skipsUnverified(_ distance: String) -> String { "Skips the unverified \(distance)" }
    static func stillUnverified(_ distance: String) -> String { "No alternative for \(distance) unverified" }
    static func arrive(_ time: String) -> String { "arrive \(time)" }

    static func label(for stretchClass: StretchClass) -> String {
        switch stretchClass {
        case .carriageway: carriageway
        case .mopedPath: mopedPath
        case .unverified: unverified
        case .forbidden: forbidden
        }
    }

    static func message(for error: Error) -> String {
        switch error {
        case let error as RouteRequestError:
            switch error {
            case .unauthorized: return unauthorized
            case .noRoute: return noRoute
            case .serviceUnavailable: return serviceUnavailable
            case .classificationFailed: return classificationFailed
            case let .http(status, code): return "The route service answered \(status)\(code.map { " (\($0))" } ?? "")."
            }
        case is RouteParseError, is DecodingError: return routeParseFailed
        case is URLError: return networkFailed
        default: return routeParseFailed
        }
    }
}
