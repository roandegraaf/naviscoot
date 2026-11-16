import CoreLocation
import FerrostarCoreFFI
import Foundation

struct TrackPoint: Codable, Equatable {
    let lat: Double
    let lon: Double
    let time: Date

    var coordinate: Coordinate { Coordinate(lat: lat, lon: lon) }
}

struct TrackFix: Equatable {
    let coordinate: Coordinate
    let time: Date
    var courseDegrees: Double?
    var horizontalAccuracyM: Double = 5

    init(coordinate: Coordinate, time: Date, courseDegrees: Double? = nil, horizontalAccuracyM: Double = 5) {
        self.coordinate = coordinate
        self.time = time
        self.courseDegrees = courseDegrees
        self.horizontalAccuracyM = horizontalAccuracyM
    }

    init(_ location: UserLocation) {
        self.init(
            coordinate: Coordinate(location.coordinates),
            time: location.timestamp,
            courseDegrees: location.courseOverGround.map { Double($0.degrees) },
            horizontalAccuracyM: location.horizontalAccuracy
        )
    }
}

struct ScooterReading: Codable, Equatable {
    let batteryPercent: Int
    let odometerKm: Double
}

struct TripDraft: Codable, Equatable {
    static let minimumDistanceM = 100.0
    static let minimumDurationS = 30.0
    static let spacingM = 15.0
    static let turnSpacingM = 5.0
    static let turnDegrees = 30.0
    static let maximumAccuracyM = 50.0
    static let batterySwapRisePercent = 3

    let startedAt: Date
    var destination: String
    var stops: [String] = []
    private(set) var scooterStart: ScooterReading?
    private(set) var scooterEnd: ScooterReading?
    private(set) var segments: [[TrackPoint]] = [[]]
    private var tail: TrackPoint?
    private var lastKeptCourse: Double?

    init(startedAt: Date, destination: String) {
        self.startedAt = startedAt
        self.destination = destination
    }

    @discardableResult
    mutating func add(_ fix: TrackFix) -> Bool {
        guard fix.horizontalAccuracyM >= 0, fix.horizontalAccuracyM <= Self.maximumAccuracyM else { return false }
        let point = TrackPoint(lat: fix.coordinate.lat, lon: fix.coordinate.lon, time: fix.time)
        guard let last = segments[segments.count - 1].last else {
            keep(point, course: fix.courseDegrees)
            return true
        }
        let moved = Self.distanceM(last, point)
        let turned = Self.turnDegrees(from: lastKeptCourse, to: fix.courseDegrees)
        if moved >= Self.spacingM || (moved >= Self.turnSpacingM && turned >= Self.turnDegrees) {
            keep(point, course: fix.courseDegrees)
            return true
        }
        tail = point
        return false
    }

    // A clear rise means the pack was charged or swapped mid-trip, so consumption is measured from there on.
    mutating func recordScooter(_ telemetry: ScooterTelemetry) {
        let reading = ScooterReading(batteryPercent: telemetry.batteryPercent, odometerKm: telemetry.odometerKm)
        if scooterStart == nil || reading.batteryPercent >= (scooterEnd?.batteryPercent ?? 0) + Self.batterySwapRisePercent {
            scooterStart = reading
        }
        scooterEnd = reading
    }

    mutating func beginSegment() {
        close()
        if !segments[segments.count - 1].isEmpty {
            segments.append([])
        }
        lastKeptCourse = nil
    }

    mutating func close() {
        if let tail {
            segments[segments.count - 1].append(tail)
        }
        tail = nil
    }

    var track: [[Coordinate]] {
        closedSegments.filter { !$0.isEmpty }.map { $0.map(\.coordinate) }
    }

    var distanceM: Double {
        closedSegments.reduce(0) { total, points in
            total + zip(points, points.dropFirst()).reduce(0) { $0 + Self.distanceM($1.0, $1.1) }
        }
    }

    var durationS: Double {
        closedSegments.reduce(0) { total, points in
            guard let first = points.first, let last = points.last else { return total }
            return total + last.time.timeIntervalSince(first.time)
        }
    }

    var averageKmh: Double { TripMath.averageKmh(distanceM: distanceM, durationS: durationS) }

    var scooterSample: ScooterTripSample? {
        ScooterTripSample.between(scooterStart, scooterEnd)
    }

    var isWorthKeeping: Bool { distanceM >= Self.minimumDistanceM && durationS >= Self.minimumDurationS }

    private var closedSegments: [[TrackPoint]] {
        var closed = segments
        if let tail { closed[closed.count - 1].append(tail) }
        return closed
    }

    private mutating func keep(_ point: TrackPoint, course: Double?) {
        segments[segments.count - 1].append(point)
        tail = nil
        if let course { lastKeptCourse = course }
    }

    private static func distanceM(_ a: TrackPoint, _ b: TrackPoint) -> Double {
        CLLocation(latitude: a.lat, longitude: a.lon).distance(from: CLLocation(latitude: b.lat, longitude: b.lon))
    }

    private static func turnDegrees(from a: Double?, to b: Double?) -> Double {
        guard let a, let b else { return 0 }
        let difference = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(difference, 360 - difference)
    }
}

extension ScooterTripSample {
    static func between(_ start: ScooterReading?, _ end: ScooterReading?) -> ScooterTripSample? {
        guard let start, let end else { return nil }
        let used = start.batteryPercent - end.batteryPercent
        let distance = end.odometerKm - start.odometerKm
        guard used > 0, distance > 0 else { return nil }
        return ScooterTripSample(distanceKm: distance, batteryUsedPercent: used)
    }
}

enum TripMath {
    static func averageKmh(distanceM: Double, durationS: Double) -> Double {
        durationS > 0 ? distanceM / durationS * 3.6 : 0
    }
}

final class TripDraftStore {
    private let url: URL?

    init(url: URL?) {
        self.url = url
    }

    static var defaultURL: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "active-trip.json")
    }

    func load() -> TripDraft? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(TripDraft.self, from: data)
    }

    func save(_ draft: TripDraft) {
        guard let url, let data = try? JSONEncoder().encode(draft) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func clear() {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

@MainActor
final class TripRecorder {
    static let saveInterval: TimeInterval = 5

    private(set) var draft: TripDraft
    private(set) var isFinished = false
    private let drafts: TripDraftStore?
    private let onFinish: (TripDraft) -> Void
    private var lastSave: Date?

    init(draft: TripDraft, drafts: TripDraftStore?, onFinish: @escaping (TripDraft) -> Void) {
        self.draft = draft
        self.drafts = drafts
        self.onFinish = onFinish
    }

    static func resuming(_ draft: TripDraft, drafts: TripDraftStore?, onFinish: @escaping (TripDraft) -> Void) -> TripRecorder {
        var continued = draft
        continued.beginSegment()
        return TripRecorder(draft: continued, drafts: drafts, onFinish: onFinish)
    }

    func begin() {
        save()
    }

    func observe(_ fix: TrackFix) {
        guard !isFinished, draft.add(fix) else { return }
        if let lastSave, fix.time.timeIntervalSince(lastSave) < Self.saveInterval { return }
        lastSave = fix.time
        save()
    }

    func reachedStop(_ name: String) {
        guard !isFinished else { return }
        draft.stops.append(name)
        save()
    }

    func scooterSample(_ telemetry: ScooterTelemetry) {
        guard !isFinished else { return }
        draft.recordScooter(telemetry)
        save()
    }

    func destinationChanged(to name: String) {
        guard !isFinished else { return }
        draft.destination = name
        save()
    }

    func finish() {
        guard !isFinished else { return }
        isFinished = true
        draft.close()
        drafts?.clear()
        onFinish(draft)
    }

    private func save() {
        drafts?.save(draft)
    }
}
