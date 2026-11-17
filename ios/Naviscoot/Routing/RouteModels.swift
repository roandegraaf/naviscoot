import CoreLocation
import FerrostarCoreFFI
import Foundation

struct Coordinate: Hashable, Codable {
    let lat: Double
    let lon: Double

    init(lat: Double, lon: Double) {
        self.lat = lat
        self.lon = lon
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(lat: coordinate.latitude, lon: coordinate.longitude)
    }

    init(_ coordinate: GeographicCoordinate) {
        self.init(lat: coordinate.lat, lon: coordinate.lng)
    }

    var clLocation: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

enum StretchClass: String, Codable, CaseIterable {
    case carriageway
    case mopedPath = "moped_path"
    case unverified
    case forbidden
}

struct Stretch: Codable, Equatable {
    let stretchClass: StretchClass
    let startShapeIndex: Int
    let endShapeIndex: Int
    let lengthM: Int
    let wayIds: [Int64]
    let unavoidable: String?

    enum CodingKeys: String, CodingKey {
        case stretchClass = "class"
        case startShapeIndex = "start_shape_index"
        case endShapeIndex = "end_shape_index"
        case lengthM = "length_m"
        case wayIds = "way_ids"
        case unavoidable
    }
}

struct RouteTotals: Codable, Equatable {
    let carriageway: Int
    let mopedPath: Int
    let unverified: Int
    let forbidden: Int

    enum CodingKeys: String, CodingKey {
        case carriageway
        case mopedPath = "moped_path"
        case unverified
        case forbidden
    }

    subscript(stretchClass: StretchClass) -> Int {
        switch stretchClass {
        case .carriageway: carriageway
        case .mopedPath: mopedPath
        case .unverified: unverified
        case .forbidden: forbidden
        }
    }

    var sum: Int { carriageway + mopedPath + unverified + forbidden }
}

struct VerifiedOnlyInfo: Codable, Equatable {
    let requests: Int
    let excludedPoints: Int
    let converged: Bool
    let stoppedBecause: String?

    enum CodingKeys: String, CodingKey {
        case requests
        case excludedPoints = "excluded_points"
        case converged
        case stoppedBecause = "stopped_because"
    }
}

struct SpeedLimitRun: Codable, Equatable {
    let startShapeIndex: Int
    let endShapeIndex: Int
    let kmh: Int

    enum CodingKeys: String, CodingKey {
        case startShapeIndex = "start_shape_index"
        case endShapeIndex = "end_shape_index"
        case kmh
    }
}

struct AvoidUnpavedInfo: Codable, Equatable {
    let converged: Bool
    let remainingM: Int

    enum CodingKeys: String, CodingKey {
        case converged
        case remainingM = "remaining_m"
    }
}

struct RouteLeg: Codable, Equatable {
    let startShapeIndex: Int
    let endShapeIndex: Int
    let firstEdge: Int
    let lastEdge: Int

    enum CodingKeys: String, CodingKey {
        case startShapeIndex = "start_shape_index"
        case endShapeIndex = "end_shape_index"
        case firstEdge = "first_edge"
        case lastEdge = "last_edge"
    }
}

enum RouteProfile: String, Codable {
    case fastest
    case quiet
}

struct NaviscootMeta: Codable, Equatable {
    let routeId: String
    var profile: RouteProfile? = nil
    let lengthM: Int
    let totalsM: RouteTotals
    var mainRoadM: Int? = nil
    let stretches: [Stretch]
    let speedLimits: [SpeedLimitRun]?
    let warnings: [String]
    let verifiedOnly: VerifiedOnlyInfo?
    let avoidUnpaved: AvoidUnpavedInfo?
    let legs: [RouteLeg]?
    let alternates: [NaviscootMeta]?

    enum CodingKeys: String, CodingKey {
        case routeId = "route_id"
        case profile
        case lengthM = "length_m"
        case totalsM = "totals_m"
        case mainRoadM = "main_road_m"
        case stretches
        case speedLimits = "speed_limits"
        case warnings
        case verifiedOnly = "verified_only"
        case avoidUnpaved = "avoid_unpaved"
        case legs
        case alternates
    }
}

struct RouteSegment: Equatable {
    let stretchClass: StretchClass
    let coordinates: [Coordinate]
}

struct RoutePlan {
    let route: Route
    let durationS: Double
    let meta: NaviscootMeta
    let segments: [RouteSegment]
    let mopedPathMarkers: [MopedPathMarker]

    var unverifiedStretches: [Stretch] {
        meta.stretches.filter { $0.stretchClass == .unverified }
    }

    var mainRoadPercent: Int? {
        guard let mainRoadM = meta.mainRoadM, meta.lengthM > 0 else { return nil }
        return Int((Double(mainRoadM) / Double(meta.lengthM) * 100).rounded())
    }
}
