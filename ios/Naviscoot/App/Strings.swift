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
