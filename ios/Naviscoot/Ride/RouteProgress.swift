import FerrostarCoreFFI
import Foundation

enum Geo {
    static let earthRadiusM = 6_371_008.8

    static func distanceM(_ a: Coordinate, _ b: Coordinate) -> Double {
        let lat1 = a.lat * .pi / 180
        let lat2 = b.lat * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (b.lon - a.lon) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadiusM * asin(min(1, sqrt(h)))
    }

    static func bearing(_ a: Coordinate, _ b: Coordinate) -> Double {
        let lat1 = a.lat * .pi / 180
        let lat2 = b.lat * .pi / 180
        let dLon = (b.lon - a.lon) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }

    static func offset(_ origin: Coordinate, bearing: Double, distanceM: Double) -> Coordinate {
        let angular = distanceM / earthRadiusM
        let theta = bearing * .pi / 180
        let lat1 = origin.lat * .pi / 180
        let lon1 = origin.lon * .pi / 180
        let lat2 = asin(sin(lat1) * cos(angular) + cos(lat1) * sin(angular) * cos(theta))
        let lon2 = lon1 + atan2(sin(theta) * sin(angular) * cos(lat1), cos(angular) - sin(lat1) * sin(lat2))
        return Coordinate(lat: lat2 * 180 / .pi, lon: lon2 * 180 / .pi)
    }
}

struct RouteGeometry {
    let points: [Coordinate]
    let cumulativeM: [Double]
    let stepStartIndices: [Int]
    private let stepPointCounts: [Int]

    init(points: [Coordinate], stepPointCounts: [Int] = []) {
        self.points = points
        var cumulative = [0.0]
        cumulative.reserveCapacity(points.count)
        for index in points.indices.dropFirst() {
            cumulative.append(cumulative[index - 1] + Geo.distanceM(points[index - 1], points[index]))
        }
        cumulativeM = points.isEmpty ? [] : cumulative
        var starts: [Int] = []
        var next = 0
        for count in stepPointCounts {
            starts.append(next)
            next += max(0, count - 1)
        }
        stepStartIndices = starts
        self.stepPointCounts = stepPointCounts
    }

    init(route: Route) {
        self.init(points: route.geometry.map(Coordinate.init), stepPointCounts: route.steps.map(Self.spannedPointCount))
    }

    // An intermediate arrive step is [p, p] while the route geometry holds p once, so it must not advance later steps.
    private static func spannedPointCount(_ step: RouteStep) -> Int {
        guard let first = step.geometry.first else { return 0 }
        return step.geometry.allSatisfy { $0 == first } ? 1 : step.geometry.count
    }

    var lengthM: Double { cumulativeM.last ?? 0 }

    func distanceM(atShapeIndex index: Int) -> Double {
        guard !cumulativeM.isEmpty else { return 0 }
        return cumulativeM[min(max(0, index), cumulativeM.count - 1)]
    }

    func globalIndex(completedSteps: Int, stepGeometryIndex: Int) -> Int {
        guard !points.isEmpty, !stepStartIndices.isEmpty else { return 0 }
        let step = min(max(0, completedSteps), stepStartIndices.count - 1)
        let offset = min(max(0, stepGeometryIndex), max(0, stepPointCounts[step] - 1))
        return min(stepStartIndices[step] + offset, points.count - 1)
    }

    func progressM(near index: Int, snapped: Coordinate) -> Double {
        guard points.count >= 2 else { return 0 }
        let clamped = min(max(0, index), points.count - 1)
        var best: (distance: Double, along: Double)?
        for segment in max(0, clamped - 1) ... min(clamped, points.count - 2) {
            let projection = project(snapped, onSegment: segment)
            if best == nil || projection.distance < best!.distance {
                best = projection
            }
        }
        return best?.along ?? cumulativeM[clamped]
    }

    func position(atM distance: Double) -> (coordinate: Coordinate, bearing: Double) {
        guard points.count >= 2 else { return (points.first ?? Coordinate(lat: 0, lon: 0), 0) }
        let target = min(max(0, distance), lengthM)
        var low = 0
        var high = cumulativeM.count - 1
        while high - low > 1 {
            let mid = (low + high) / 2
            if cumulativeM[mid] <= target { low = mid } else { high = mid }
        }
        let a = points[low]
        let b = points[high]
        let span = cumulativeM[high] - cumulativeM[low]
        let t = span > 0 ? (target - cumulativeM[low]) / span : 0
        let coordinate = Coordinate(lat: a.lat + (b.lat - a.lat) * t, lon: a.lon + (b.lon - a.lon) * t)
        return (coordinate, Geo.bearing(a, b))
    }

    func heading(atM distance: Double, spanM: Double) -> Double {
        let from = position(atM: distance - spanM * 0.3)
        let to = position(atM: distance + spanM * 0.7)
        guard Geo.distanceM(from.coordinate, to.coordinate) > 0.5 else { return position(atM: distance).bearing }
        return Geo.bearing(from.coordinate, to.coordinate)
    }

    func maneuverM(afterCompletedSteps completed: Int) -> Double? {
        let next = completed + 1
        guard next >= 1, next < stepStartIndices.count else { return nil }
        return distanceM(atShapeIndex: stepStartIndices[next])
    }

    private func project(_ point: Coordinate, onSegment segment: Int) -> (distance: Double, along: Double) {
        let a = points[segment]
        let b = points[segment + 1]
        let metersPerDegreeLat = Geo.earthRadiusM * .pi / 180
        let metersPerDegreeLon = metersPerDegreeLat * cos(a.lat * .pi / 180)
        let bx = (b.lon - a.lon) * metersPerDegreeLon
        let by = (b.lat - a.lat) * metersPerDegreeLat
        let px = (point.lon - a.lon) * metersPerDegreeLon
        let py = (point.lat - a.lat) * metersPerDegreeLat
        let lengthSquared = bx * bx + by * by
        let t = lengthSquared > 0 ? min(1, max(0, (px * bx + py * by) / lengthSquared)) : 0
        let dx = px - t * bx
        let dy = py - t * by
        let segmentLength = cumulativeM[segment + 1] - cumulativeM[segment]
        return ((dx * dx + dy * dy).squareRoot(), cumulativeM[segment] + t * segmentLength)
    }
}

struct UnverifiedSpan: Equatable {
    let key: String
    let startM: Double
    let endM: Double
    let lengthM: Int
}

enum UnverifiedAlert: Equatable {
    case ahead(key: String, distanceM: Double, lengthM: Int)
    case inside(key: String, remainingM: Double)

    var key: String {
        switch self {
        case let .ahead(key, _, _), let .inside(key, _): key
        }
    }
}

enum UnverifiedWarnings {
    static let leadM: Double = 1000

    static func spans(stretches: [Stretch], geometry: RouteGeometry) -> [UnverifiedSpan] {
        stretches.filter { $0.stretchClass == .unverified }.map { stretch in
            UnverifiedSpan(
                key: stretch.wayIds.map(String.init).joined(separator: "-"),
                startM: geometry.distanceM(atShapeIndex: stretch.startShapeIndex),
                endM: geometry.distanceM(atShapeIndex: stretch.endShapeIndex),
                lengthM: stretch.lengthM
            )
        }
    }

    static func alert(progressM: Double, spans: [UnverifiedSpan], leadM: Double = leadM) -> UnverifiedAlert? {
        guard let next = spans.first(where: { $0.endM > progressM }) else { return nil }
        if progressM >= next.startM {
            return .inside(key: next.key, remainingM: next.endM - progressM)
        }
        let distance = next.startM - progressM
        return distance <= leadM ? .ahead(key: next.key, distanceM: distance, lengthM: next.lengthM) : nil
    }
}

struct WarningAnnouncer {
    private(set) var announced: Set<String> = []

    mutating func shouldAnnounce(_ alert: UnverifiedAlert?) -> Bool {
        guard let alert, !announced.contains(alert.key) else { return false }
        announced.insert(alert.key)
        return true
    }
}

enum RouteLookup {
    static let carriagewayLimitKmh = 45

    static func stretch(atShapeIndex index: Int, in stretches: [Stretch]) -> Stretch? {
        stretches.first { $0.startShapeIndex <= index && index < $0.endShapeIndex } ?? stretches.last
    }

    static func stretchClass(atM distance: Double, geometry: RouteGeometry, stretches: [Stretch]) -> StretchClass? {
        let found = stretches.first { geometry.distanceM(atShapeIndex: $0.endShapeIndex) > distance } ?? stretches.last
        return found?.stretchClass
    }

    static func limitKmh(atShapeIndex index: Int, meta: NaviscootMeta) -> Int? {
        if let runs = meta.speedLimits, !runs.isEmpty {
            return (runs.first { $0.startShapeIndex <= index && index < $0.endShapeIndex } ?? runs.last)?.kmh
        }
        return stretch(atShapeIndex: index, in: meta.stretches)?.stretchClass == .carriageway ? carriagewayLimitKmh : nil
    }
}

enum MopedPathEntry: Equatable {
    case left
    case right

    static let beforeM = 10.0
    static let afterM = [10.0, 40.0]
    static let straightDegrees = 3.0

    static func at(maneuverM: Double, modifier: ManeuverModifier?, geometry: RouteGeometry, stretches: [Stretch]) -> MopedPathEntry? {
        guard maneuverM > 0, maneuverM < geometry.lengthM else { return nil }
        func stretchClass(_ offset: Double) -> StretchClass? {
            RouteLookup.stretchClass(atM: min(max(0, maneuverM + offset), geometry.lengthM - 0.1), geometry: geometry, stretches: stretches)
        }
        guard stretchClass(-beforeM) == .carriageway, afterM.contains(where: { stretchClass($0) == .mopedPath }) else { return nil }
        switch modifier {
        case .slightLeft, .left, .sharpLeft: return .left
        case .slightRight, .right, .sharpRight: return .right
        case .straight, .uTurn, .none:
            return side(atM: maneuverM, geometry: geometry)
        }
    }

    static func side(atM distance: Double, geometry: RouteGeometry) -> MopedPathEntry {
        let into = geometry.heading(atM: distance - 15, spanM: 15)
        let out = geometry.heading(atM: distance + 5, spanM: 15)
        return RideCamera.screenAngle(course: out, bearing: into) < -straightDegrees ? .left : .right
    }
}

struct MopedPathMarker: Equatable {
    let coordinate: Coordinate
    let side: MopedPathEntry
    let alongM: Double

    static let minimumCarriagewayM = 25.0

    static func all(geometry: RouteGeometry, stretches: [Stretch]) -> [MopedPathMarker] {
        zip(stretches.indices, zip(stretches, stretches.dropFirst())).compactMap { index, pair in
            let (carriageway, path) = pair
            guard carriageway.stretchClass == .carriageway, path.stretchClass == .mopedPath,
                  path.startShapeIndex < geometry.points.count
            else { return nil }
            let startM = geometry.distanceM(atShapeIndex: carriageway.startShapeIndex)
            let alongM = geometry.distanceM(atShapeIndex: path.startShapeIndex)
            guard index == stretches.startIndex || alongM - startM >= minimumCarriagewayM else { return nil }
            return MopedPathMarker(
                coordinate: geometry.points[path.startShapeIndex],
                side: MopedPathEntry.side(atM: alongM, geometry: geometry),
                alongM: alongM
            )
        }
    }
}
