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

    struct Viewport: Equatable {
        var aheadPoints: Double
        var viewHeight: Double
    }

    struct FollowLayout: Equatable {
        let anchor: CGPoint
        let halfSize: CGSize
        let viewport: Viewport
    }

    static let fixedZoom = 16.5
    static let threeDPitch = 40.0
    static let minZoom = 14.5
    static let maxZoom = 17.5
    static let slowAheadM = 250.0
    static let fastAheadM = 400.0
    static let slowSpeedKmh = 15.0
    static let fastSpeedKmh = 45.0
    static let maneuverShare = 0.8
    static let courseUpAnchorShare = 0.82
    static let aheadMarginPoints = 12.0
    static let zoomTau = 0.8
    static let pitchTau = 0.3
    static let recenterS = 0.6

    static func follow(
        bearing: Double,
        options: FollowOptions,
        distanceToManeuverM: Double?,
        speedKmh: Double?,
        latitude: Double,
        viewport: Viewport?
    ) -> Follow {
        let pitch = options.threeD ? threeDPitch : 0
        var zoom = fixedZoom
        if options.autoZoom, let viewport {
            zoom = self.zoom(
                showingAheadM: aheadM(distanceToManeuverM: distanceToManeuverM, speedKmh: speedKmh),
                viewport: viewport,
                pitch: pitch,
                latitude: latitude
            )
        }
        return Follow(zoom: zoom, pitch: pitch, direction: options.northUp ? 0 : bearing)
    }

    // How far ahead of the rider the map should reach: further at speed, and never so short that a maneuver inside
    // that reach falls off the top of the map.
    static func aheadM(distanceToManeuverM: Double?, speedKmh: Double?) -> Double {
        let speedShare = min(max(((speedKmh ?? 0) - slowSpeedKmh) / (fastSpeedKmh - slowSpeedKmh), 0), 1)
        let cruise = slowAheadM + (fastAheadM - slowAheadM) * speedShare
        guard let distance = distanceToManeuverM else { return cruise }
        return min(cruise, max(0, distance) / maneuverShare)
    }

    // MapLibre's camera sits 1.5 view heights from the point it looks at; with pitch, a point higher on the screen is
    // further away on the ground than the same number of points would be when looking straight down.
    static func zoom(showingAheadM aheadM: Double, viewport: Viewport, pitch: Double, latitude: Double) -> Double {
        guard viewport.aheadPoints > 0, viewport.viewHeight > 0 else { return fixedZoom }
        let radians = pitch * .pi / 180
        let cameraDistance = 1.5 * viewport.viewHeight
        let foreshortening = max(0.2, cos(radians) - viewport.aheadPoints / cameraDistance * sin(radians))
        let groundPoints = viewport.aheadPoints / foreshortening
        let metersPerPoint = max(aheadM, 1) / groundPoints
        let zoom = log2(metersPerPointAtZoomZero * cos(latitude * .pi / 180) / metersPerPoint)
        return min(max(zoom, minZoom), maxZoom)
    }

    static let metersPerPointAtZoomZero = 2 * Double.pi * 6_378_137 / 512

    // Course-up keeps the rider low on the map so most of it shows what is ahead; north-up keeps them in the middle,
    // as the road ahead can lead any way.
    static func followLayout(area: CGRect, window: CGSize, northUp: Bool, landscape: Bool) -> FollowLayout? {
        guard !area.isEmpty, window.width > 0, window.height > 0 else { return nil }
        let x = landscape ? area.midX : window.width / 2
        let halfWidth = landscape ? area.width / 2 : window.width / 2
        let share = northUp ? 0.5 : courseUpAnchorShare
        let y = area.minY + area.height * share
        let reach = northUp ? min(area.height / 2, halfWidth) : y - area.minY
        return FollowLayout(
            anchor: CGPoint(x: x, y: y),
            halfSize: CGSize(width: halfWidth, height: area.maxY - y),
            viewport: Viewport(aheadPoints: max(1, reach - aheadMarginPoints), viewHeight: window.height)
        )
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
