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

    mutating func moveStopUp(at index: Int) {
        guard index > 0, stops.indices.contains(index) else { return }
        stops.swapAt(index, index - 1)
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
