import CoreGraphics
import Foundation

enum TripStart: Equatable {
    case currentLocation
    case place(Destination)
}

struct TripRequest: Equatable {
    let origin: Coordinate
    let destination: Coordinate
    let options: RouteOptions
}

struct TripSchedule: Equatable {
    let departure: Date
    let arrival: Date
}

struct TripPlan: Equatable {
    static let maxStops = 8
    static let alternatives = 2
    static let sameSpotM: Double = 25

    var start: TripStart = .currentLocation
    private(set) var stops: [Destination] = []
    var destination: Destination
    var time: RouteTime?

    init(destination: Destination) {
        self.destination = destination
    }

    var startsFromCurrentLocation: Bool { start == .currentLocation }
    var canAddStop: Bool { stops.count < Self.maxStops }

    mutating func addStop(_ stop: Destination) {
        guard canAddStop else { return }
        stops.append(stop)
    }

    mutating func removeStop(at index: Int) {
        guard stops.indices.contains(index) else { return }
        stops.remove(at: index)
    }

    mutating func moveStop(from source: Int, to destination: Int) {
        guard source != destination, stops.indices.contains(source), stops.indices.contains(destination) else { return }
        stops.insert(stops.remove(at: source), at: destination)
    }

    static let stopDragPrefix = "naviscoot-stop:"

    static func stopDragPayload(_ index: Int) -> String { "\(stopDragPrefix)\(index)" }

    static func stopIndex(fromDragPayload payload: String) -> Int? {
        guard payload.hasPrefix(stopDragPrefix) else { return nil }
        return Int(payload.dropFirst(stopDragPrefix.count))
    }

    func origin(currentLocation: Coordinate?) -> Coordinate? {
        switch start {
        case .currentLocation: currentLocation
        case let .place(place): place.coordinate
        }
    }

    func routableStops(currentLocation: Coordinate?) -> [Destination] {
        guard let origin = origin(currentLocation: currentLocation) else { return [] }
        return Self.routableIndices(stops.map(\.coordinate), origin: origin, destination: destination.coordinate).map { stops[$0] }
    }

    func request(currentLocation: Coordinate?, avoid: RouteAvoid) -> TripRequest? {
        guard let origin = origin(currentLocation: currentLocation) else { return nil }
        let stops = routableStops(currentLocation: currentLocation).map(\.coordinate)
        let options = RouteOptions(
            stops: stops,
            alternatives: stops.isEmpty ? Self.alternatives : 0,
            time: time,
            avoid: avoid
        )
        return TripRequest(origin: origin, destination: destination.coordinate, options: options)
    }

    static func routableStops(_ stops: [Coordinate], origin: Coordinate, destination: Coordinate) -> [Coordinate] {
        routableIndices(stops, origin: origin, destination: destination).map { stops[$0] }
    }

    private static func routableIndices(_ stops: [Coordinate], origin: Coordinate, destination: Coordinate) -> [Int] {
        var kept: [Int] = []
        for (index, stop) in stops.enumerated() {
            let previous = kept.last.map { stops[$0] } ?? origin
            if Geo.distanceM(previous, stop) >= sameSpotM {
                kept.append(index)
            }
        }
        while let last = kept.last, Geo.distanceM(stops[last], destination) < sameSpotM {
            kept.removeLast()
        }
        return kept
    }

    static func schedule(for time: RouteTime?, durationS: Double, now: Date) -> TripSchedule {
        switch time {
        case nil:
            TripSchedule(departure: now, arrival: now.addingTimeInterval(durationS))
        case let .departAt(departure):
            TripSchedule(departure: departure, arrival: departure.addingTimeInterval(durationS))
        case let .arriveBy(arrival):
            TripSchedule(departure: arrival.addingTimeInterval(-durationS), arrival: arrival)
        }
    }
}

enum UnverifiedStatus: Equatable {
    case none
    case unavoidable(Int)
    case remaining(Int)

    init(meta: NaviscootMeta) {
        let stretches = meta.stretches.filter { $0.stretchClass == .unverified }
        let total = meta.totalsM.unverified
        if total == 0 || stretches.isEmpty {
            self = .none
        } else if stretches.allSatisfy({ $0.unavoidable != nil }) {
            self = .unavoidable(total)
        } else {
            self = .remaining(total)
        }
    }
}

extension RouteTotals {
    var presentClasses: [StretchClass] {
        StretchClass.allCases.filter { self[$0] > 0 }
    }
}

enum VerifiedOnlyToggleRule {
    static func isShown(verifiedOnly: Bool, touched: Bool, plans: [NaviscootMeta]) -> Bool {
        verifiedOnly || touched || plans.contains { UnverifiedStatus(meta: $0) != .none }
    }
}

enum RouteBubbles {
    static let candidateSamples = 120
    static let referenceSamples = 400

    // The point on each route furthest from every other route, so a bubble never lands on a shared stretch.
    static func anchors(for routes: [[Coordinate]]) -> [Coordinate] {
        let references = routes.map { sample($0, count: referenceSamples) }
        return routes.enumerated().compactMap { index, route in
            guard !route.isEmpty else { return nil }
            let middle = route[route.count / 2]
            let others = references.enumerated().filter { $0.offset != index }.map(\.element)
            guard !others.isEmpty else { return middle }
            let trimmed = Array(route[(route.count / 10) ..< max(route.count / 10 + 1, route.count - route.count / 10)])
            var best = middle
            var bestGap = 0.0
            for candidate in sample(trimmed, count: candidateSamples) {
                let gap = others.map { nearestSquaredM(from: candidate, to: $0) }.min() ?? 0
                if gap > bestGap {
                    bestGap = gap
                    best = candidate
                }
            }
            return best
        }
    }

    static func nearestRoute(to point: CGPoint, routes: [(index: Int, points: [CGPoint])], tolerance: CGFloat) -> Int? {
        var best: (index: Int, distance: CGFloat)?
        for route in routes {
            let distance = distance(from: point, toPolyline: route.points)
            if distance <= tolerance, distance < best?.distance ?? .infinity {
                best = (route.index, distance)
            }
        }
        return best?.index
    }

    static func distance(from point: CGPoint, toPolyline points: [CGPoint]) -> CGFloat {
        guard let first = points.first else { return .infinity }
        guard points.count > 1 else { return hypot(point.x - first.x, point.y - first.y) }
        return zip(points, points.dropFirst()).map { distance(from: point, segment: $0, $1) }.min() ?? .infinity
    }

    private static func distance(from p: CGPoint, segment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        let t = lengthSquared == 0 ? 0 : max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    private static func sample(_ points: [Coordinate], count: Int) -> [Coordinate] {
        guard points.count > count, count > 1 else { return points }
        return (0 ..< count).map { points[$0 * (points.count - 1) / (count - 1)] }
    }

    private static func nearestSquaredM(from point: Coordinate, to route: [Coordinate]) -> Double {
        let metresPerLon = 111_320 * cos(point.lat * .pi / 180)
        return route.map { other in
            let dx = (other.lon - point.lon) * metresPerLon
            let dy = (other.lat - point.lat) * 110_540
            return dx * dx + dy * dy
        }.min() ?? 0
    }
}
