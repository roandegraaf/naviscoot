import Foundation

struct RideCamera: Equatable {
    enum Mode: String, Equatable {
        case following
        case free
        case overview
    }

    struct Bounds: Equatable {
        let southWest: Coordinate
        let northEast: Coordinate
    }

    private(set) var mode: Mode = .following

    var follows: Bool { mode == .following }
    var offersRecenter: Bool { mode != .following }
    var holdsStill: Bool { mode == .free }

    mutating func userMovedMap() {
        mode = .free
    }

    mutating func recenter() {
        mode = .following
    }

    mutating func showOverview() {
        mode = .overview
    }

    struct FollowOptions: Equatable {
        var northUp = false
        var threeD = true
        var autoZoom = false
    }

    struct Follow: Equatable {
        let zoom: Double
        let pitch: Double
        let direction: Double
    }

    static let fixedZoom = 16.5
    static let threeDPitch = 40.0
    static let approachZoom = 17.5
    static let approachDistanceM = 100.0
    static let straightDistanceM = 500.0
    static let slowSpeedKmh = 15.0
    static let fastSpeedKmh = 45.0
    static let straightZoomOutAtSpeed = 1.0

    static func follow(course: Double, options: FollowOptions, distanceToManeuverM: Double?, speedKmh: Double?) -> Follow {
        Follow(
            zoom: options.autoZoom ? autoZoom(distanceToManeuverM: distanceToManeuverM, speedKmh: speedKmh) : fixedZoom,
            pitch: options.threeD ? threeDPitch : 0,
            direction: options.northUp ? 0 : course
        )
    }

    static func autoZoom(distanceToManeuverM: Double?, speedKmh: Double?) -> Double {
        let speedShare = min(max(((speedKmh ?? 0) - slowSpeedKmh) / (fastSpeedKmh - slowSpeedKmh), 0), 1)
        let straightZoom = fixedZoom - straightZoomOutAtSpeed * speedShare
        guard let distance = distanceToManeuverM else { return quantized(straightZoom) }
        let approach = min(max((straightDistanceM - distance) / (straightDistanceM - approachDistanceM), 0), 1)
        return quantized(straightZoom + (approachZoom - straightZoom) * approach)
    }

    // Quarter steps keep the 1 Hz camera updates from wobbling the zoom by hundredths.
    private static func quantized(_ zoom: Double) -> Double {
        (zoom * 4).rounded() / 4
    }

    static func remainingRoute(points: [Coordinate], from index: Int, user: Coordinate?) -> [Coordinate] {
        let ahead = points.isEmpty ? [] : Array(points[min(max(0, index), points.count - 1)...])
        return (user.map { [$0] } ?? []) + ahead
    }

    static func screenAngle(course: Double, bearing: Double) -> Double {
        let angle = (course - bearing).truncatingRemainder(dividingBy: 360)
        if angle > 180 { return angle - 360 }
        if angle <= -180 { return angle + 360 }
        return angle
    }

    static func bounds(of points: [Coordinate]) -> Bounds? {
        guard let first = points.first else { return nil }
        var south = first.lat, north = first.lat, west = first.lon, east = first.lon
        for point in points.dropFirst() {
            south = min(south, point.lat)
            north = max(north, point.lat)
            west = min(west, point.lon)
            east = max(east, point.lon)
        }
        return Bounds(southWest: Coordinate(lat: south, lon: west), northEast: Coordinate(lat: north, lon: east))
    }
}
