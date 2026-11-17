import Foundation

struct RideFix: Equatable {
    var time: TimeInterval
    var coordinate: Coordinate
    var alongM: Double?
    var speedMps: Double?
    var course: Double?
    var maneuverAlongM: Double?
}

struct CompassReading: Equatable {
    var degrees: Double
    var accuracy: Double

    var isUsable: Bool { accuracy >= 0 && accuracy <= RideMotion.compassMaxErrorDegrees }
}

// GPS fixes arrive once a second. This turns them into a position for every frame: it moves on at the last known speed
// between fixes and eases out the difference when the next fix lands, so the marker glides instead of stepping.
struct RideMotion {
    struct Frame: Equatable {
        let coordinate: Coordinate
        let bearing: Double
        let cameraBearing: Double
        let speedMps: Double
        let distanceToManeuverM: Double?
        let usesCompass: Bool
    }

    static let maxExtrapolationS = 1.5
    static let positionTau = 0.9
    static let speedTau = 0.25
    static let residualTau = 0.4
    static let stationarySpeedMps = 0.8
    static let holdRadiusM = 6.0
    static let settledM = 0.5
    static let reverseM = 12.0
    static let snapM = 60.0
    static let staleS = 1.0
    static let headingSpanM = 10.0
    static let bearingTau = 0.2
    static let cameraBearingTau = 0.6
    static let compassBearingTau = 0.3
    static let compassEnterMps = 1.2
    static let compassExitMps = 2.5
    static let compassMaxErrorDegrees = 40.0

    private enum Track {
        case route(alongM: Double)
        case free(Coordinate)
    }

    private(set) var geometry: RouteGeometry
    private var fix: RideFix?
    private var track: Track?
    private var velocity = 0.0
    private var braking = 0.0
    private var settling = false
    private var residual = (east: 0.0, north: 0.0)
    private var bearing: Double?
    private var cameraBearing: Double?
    private var compass: CompassReading?
    private(set) var usesCompass = false
    private var lastTime: TimeInterval?

    init(geometry: RouteGeometry = RouteGeometry(points: [])) {
        self.geometry = geometry
    }

    mutating func setRoute(_ geometry: RouteGeometry) {
        let shown = shownCoordinate
        self.geometry = geometry
        fix = nil
        residual = (0, 0)
        track = shown.map { .free($0) }
    }

    mutating func observe(_ new: RideFix) {
        var new = new
        if new.speedMps == nil, let fix, new.time > fix.time {
            new.speedMps = Geo.distanceM(fix.coordinate, new.coordinate) / (new.time - fix.time)
        }
        braking = 0
        if let fix, let before = fix.speedMps, let now = new.speedMps, new.time - fix.time > 0.2, new.time - fix.time < 2.5 {
            braking = max(0, (before - now) / (new.time - fix.time))
        }
        fix = new
        switch (track, new.alongM) {
        case (.route, .some):
            break
        case let (_, .some(along)):
            retarget(.route(alongM: min(max(0, along), geometry.lengthM)))
        case (.route, nil):
            retarget(.free(shownCoordinate ?? new.coordinate))
        case (.free, nil):
            break
        case (nil, nil):
            track = .free(new.coordinate)
        }
    }

    mutating func observe(compass reading: CompassReading?) {
        compass = reading
    }

    mutating func frame(at time: TimeInterval) -> Frame? {
        guard track != nil else { return nil }
        let elapsed = lastTime.map { time - $0 }
        let stale = elapsed.map { $0 > Self.staleS || $0 < 0 } ?? true
        let dt = stale ? 0 : min(max(elapsed ?? 0, 0), 0.25)
        lastTime = time

        advance(to: time, dt: dt, stale: stale)
        let decay = exp(-dt / Self.residualTau)
        residual = stale ? (0, 0) : (residual.east * decay, residual.north * decay)
        turn(dt: dt, stale: stale)

        guard let coordinate = shownCoordinate, let bearing, let cameraBearing else { return nil }
        var toManeuver: Double?
        if case let .route(along) = track, let maneuver = fix?.maneuverAlongM {
            toManeuver = max(0, maneuver - along)
        }
        return Frame(
            coordinate: coordinate,
            bearing: bearing,
            cameraBearing: cameraBearing,
            speedMps: velocity,
            distanceToManeuverM: toManeuver,
            usesCompass: usesCompass
        )
    }

    private mutating func advance(to time: TimeInterval, dt: Double, stale: Bool) {
        guard let fix, let track else {
            velocity = 0
            return
        }
        let speed = max(0, fix.speedMps ?? 0)
        let moving = speed >= Self.stationarySpeedMps
        let age = max(time - fix.time, 0)
        // A scooter that was slowing down at the last fix is assumed to keep slowing down, so the marker does not run on
        // at the old speed and overshoot the place where it stops.
        let coast = min(age, Self.maxExtrapolationS, braking > 0 ? speed / braking : .infinity)
        let ahead = moving ? speed * coast - braking * coast * coast / 2 : 0
        let cruise = moving && age <= Self.maxExtrapolationS ? max(0, speed - braking * age) : 0
        velocity = stale ? cruise : velocity + (cruise - velocity) * Self.blend(dt, tau: Self.speedTau)

        switch track {
        case let .route(along):
            guard let fixAlong = fix.alongM else { return }
            let target = min(fixAlong + ahead, geometry.lengthM)
            let error = target - along
            if stale || abs(error) > Self.snapM {
                self.track = .route(alongM: target)
            } else if moving || settles(abs(error)) {
                var step = velocity * dt + error * Self.blend(dt, tau: Self.positionTau)
                if error > -Self.reverseM { step = max(0, step) }
                self.track = .route(alongM: min(max(0, along + step), geometry.lengthM))
            }
        case let .free(position):
            let target = moving && fix.course != nil
                ? Geo.offset(fix.coordinate, bearing: fix.course ?? 0, distanceM: ahead)
                : fix.coordinate
            let error = Self.delta(from: position, to: target)
            let distance = (error.east * error.east + error.north * error.north).squareRoot()
            if stale || distance > Self.snapM {
                self.track = .free(target)
            } else if moving || settles(distance) {
                let pull = Self.blend(dt, tau: Self.positionTau)
                let heading = (fix.course ?? 0) * .pi / 180
                let forward = fix.course == nil ? 0 : velocity * dt
                self.track = .free(Self.moved(
                    position,
                    east: error.east * pull + sin(heading) * forward,
                    north: error.north * pull + cos(heading) * forward
                ))
            }
        }
    }

    // Standing still, GPS wanders a few metres. The marker stays put until the fix has really moved away, and then goes
    // all the way to it.
    private mutating func settles(_ distance: Double) -> Bool {
        if distance >= Self.holdRadiusM { settling = true }
        if distance < Self.settledM { settling = false }
        return settling
    }

    private mutating func turn(dt: Double, stale: Bool) {
        if usesCompass {
            if velocity > Self.compassExitMps || compass?.isUsable != true { usesCompass = false }
        } else if velocity < Self.compassEnterMps, compass?.isUsable == true {
            usesCompass = true
        }

        var travel: Double?
        switch track {
        case let .route(along):
            if geometry.points.count >= 2 { travel = geometry.heading(atM: along, spanM: Self.headingSpanM) }
        case .free:
            if let course = fix?.course, (fix?.speedMps ?? 0) >= Self.stationarySpeedMps { travel = course }
        case nil:
            break
        }
        let target = usesCompass ? compass?.degrees : travel
        guard let target = target ?? bearing ?? travel ?? compass?.degrees else { return }
        guard let current = bearing, let currentCamera = cameraBearing, !stale else {
            bearing = target
            cameraBearing = target
            return
        }
        bearing = Self.turned(current, toward: target, by: Self.blend(dt, tau: usesCompass ? Self.compassBearingTau : Self.bearingTau))
        cameraBearing = Self.turned(currentCamera, toward: target, by: Self.blend(dt, tau: Self.cameraBearingTau))
    }

    private var modelCoordinate: Coordinate? {
        switch track {
        case let .route(along): geometry.points.isEmpty ? nil : geometry.position(atM: along).coordinate
        case let .free(position): position
        case nil: nil
        }
    }

    private var shownCoordinate: Coordinate? {
        modelCoordinate.map { Self.moved($0, east: residual.east, north: residual.north) }
    }

    // Switching between following the route line and the raw position must not make the marker jump.
    private mutating func retarget(_ next: Track) {
        let before = shownCoordinate
        track = next
        guard let before, let after = modelCoordinate else {
            residual = (0, 0)
            return
        }
        let offset = Self.delta(from: after, to: before)
        let far = (offset.east * offset.east + offset.north * offset.north).squareRoot() > Self.snapM
        residual = far ? (0, 0) : offset
    }

    static func blend(_ dt: Double, tau: Double) -> Double {
        dt <= 0 ? 0 : 1 - exp(-dt / tau)
    }

    static func turned(_ from: Double, toward target: Double, by share: Double) -> Double {
        var difference = (target - from).truncatingRemainder(dividingBy: 360)
        if difference > 180 { difference -= 360 }
        if difference < -180 { difference += 360 }
        let next = (from + difference * share).truncatingRemainder(dividingBy: 360)
        return next < 0 ? next + 360 : next
    }

    private static let metersPerDegree = Geo.earthRadiusM * .pi / 180

    private static func delta(from a: Coordinate, to b: Coordinate) -> (east: Double, north: Double) {
        ((b.lon - a.lon) * metersPerDegree * cos(a.lat * .pi / 180), (b.lat - a.lat) * metersPerDegree)
    }

    private static func moved(_ origin: Coordinate, east: Double, north: Double) -> Coordinate {
        guard east != 0 || north != 0 else { return origin }
        return Coordinate(
            lat: origin.lat + north / metersPerDegree,
            lon: origin.lon + east / (metersPerDegree * cos(origin.lat * .pi / 180))
        )
    }
}
