import FerrostarCoreFFI
@testable import Naviscoot
import XCTest

final class RideMotionTests: XCTestCase {
    private let start = Coordinate(lat: 52.09, lon: 5.12)

    private func straight(lengthM: Double = 2000, bearing: Double = 0) -> RouteGeometry {
        RouteGeometry(points: stride(from: 0.0, through: lengthM, by: 50).map { Geo.offset(start, bearing: bearing, distanceM: $0) })
    }

    private func fix(_ geometry: RouteGeometry, at time: Double, alongM: Double, speed: Double, maneuverM: Double? = nil) -> RideFix {
        let position = geometry.position(atM: alongM)
        return RideFix(time: time, coordinate: position.coordinate, alongM: alongM, speedMps: speed, course: position.bearing, maneuverAlongM: maneuverM)
    }

    private func along(_ geometry: RouteGeometry, _ frame: RideMotion.Frame?) -> Double {
        frame.map { Geo.distanceM(geometry.points[0], $0.coordinate) } ?? -1
    }

    func testTheMarkerGlidesBetweenFixesInsteadOfSteppingOncePerSecond() {
        let geometry = straight()
        var motion = RideMotion(geometry: geometry)
        var previous: Double?
        var largestStep = 0.0
        for tick in 0 ..< 600 {
            let time = Double(tick) / 60
            if tick % 60 == 0 { motion.observe(fix(geometry, at: time, alongM: time * 12.5, speed: 12.5)) }
            let shown = along(geometry, motion.frame(at: time))
            if let previous {
                XCTAssertGreaterThanOrEqual(shown, previous - 0.001, "moved backwards at \(time) s")
                largestStep = max(largestStep, shown - previous)
            }
            XCTAssertEqual(shown, time * 12.5, accuracy: 1.0, "off the real position at \(time) s")
            previous = shown
        }
        XCTAssertLessThan(largestStep, 0.3, "a 12.5 m/s ride should move about 0.21 m per frame, not jump")
    }

    func testANoisyFixIsEasedInRatherThanJumpedTo() {
        let geometry = straight()
        var motion = RideMotion(geometry: geometry)
        var previous: Double?
        for tick in 0 ..< 600 {
            let time = Double(tick) / 60
            if tick % 60 == 0 {
                let noise = (tick / 60) % 2 == 0 ? 2.0 : -2.0
                motion.observe(fix(geometry, at: time, alongM: max(0, time * 10 + noise), speed: 10))
            }
            let shown = along(geometry, motion.frame(at: time))
            if let previous, tick > 1 {
                XCTAssertGreaterThanOrEqual(shown, previous - 0.001)
                XCTAssertLessThan(shown - previous, 0.25, "a 2 m correction came through as a jump at \(time) s")
            }
            previous = shown
        }
    }

    func testStandingStillHoldsTheMarkerWhileTheFixWanders() {
        let geometry = straight()
        var motion = RideMotion(geometry: geometry)
        motion.observe(fix(geometry, at: 0, alongM: 400, speed: 0))
        let held = along(geometry, motion.frame(at: 0))
        for second in 1 ... 20 {
            let wander = [3.0, -4.0, 5.0, -2.0, 4.5][second % 5]
            motion.observe(fix(geometry, at: Double(second), alongM: 400 + wander, speed: 0.2))
            for sub in 0 ..< 60 {
                XCTAssertEqual(along(geometry, motion.frame(at: Double(second) + Double(sub) / 60)), held, accuracy: 0.01)
            }
        }
        motion.observe(fix(geometry, at: 21, alongM: 430, speed: 0.2))
        var shown = held
        for sub in 0 ..< 600 { shown = along(geometry, motion.frame(at: 21 + Double(sub) / 60)) }
        XCTAssertEqual(shown, 430, accuracy: 0.5, "a real move while slow is still followed")
    }

    func testBrakingToAStopNeverRunsOnPastTheLastFixByMoreThanAFewMetres() {
        let geometry = straight()
        var motion = RideMotion(geometry: geometry)
        var position = 0.0
        var speed = 12.5
        var furthest = 0.0
        for second in 0 ..< 12 {
            motion.observe(fix(geometry, at: Double(second), alongM: position, speed: speed))
            for sub in 0 ..< 60 {
                furthest = max(furthest, along(geometry, motion.frame(at: Double(second) + Double(sub) / 60)))
            }
            let next = second >= 3 ? max(0, speed - 4) : speed
            position += (speed + next) / 2
            speed = next
        }
        XCTAssertLessThan(furthest - position, 2.5, "the marker ran on past where the scooter stopped")
        XCTAssertEqual(along(geometry, motion.frame(at: 12)), position, accuracy: RideMotion.holdRadiusM)
    }

    func testTheMarkerStopsWhenFixesStopArriving() {
        let geometry = straight()
        var motion = RideMotion(geometry: geometry)
        motion.observe(fix(geometry, at: 0, alongM: 100, speed: 12.5))
        var shown = 0.0
        for tick in 0 ..< 600 { shown = along(geometry, motion.frame(at: Double(tick) / 60)) }
        XCTAssertLessThan(shown, 100 + 12.5 * (RideMotion.maxExtrapolationS + 0.5))
    }

    func testLeavingAndRejoiningTheRouteDoesNotMakeTheMarkerJump() {
        let geometry = straight()
        var motion = RideMotion(geometry: geometry)
        var previous: Coordinate?
        for tick in 0 ..< 360 {
            let time = Double(tick) / 60
            if tick % 60 == 0 {
                let second = tick / 60
                let onRoute = fix(geometry, at: time, alongM: time * 10, speed: 10)
                if second == 2 || second == 3 {
                    let aside = Geo.offset(onRoute.coordinate, bearing: 90, distanceM: 30)
                    motion.observe(RideFix(time: time, coordinate: aside, alongM: nil, speedMps: 10, course: 0))
                } else {
                    motion.observe(onRoute)
                }
            }
            let shown = motion.frame(at: time)?.coordinate
            if let previous, let shown {
                XCTAssertLessThan(Geo.distanceM(previous, shown), 1.5, "jumped at \(time) s")
            }
            previous = shown
        }
    }

    func testAResumedAppSnapsToTheCurrentPosition() {
        let geometry = straight()
        var motion = RideMotion(geometry: geometry)
        motion.observe(fix(geometry, at: 0, alongM: 0, speed: 10))
        _ = motion.frame(at: 0)
        motion.observe(fix(geometry, at: 30, alongM: 300, speed: 10))
        XCTAssertEqual(along(geometry, motion.frame(at: 30)), 300, accuracy: 0.1)
    }

    func testTheMarkerTurnsWithTheRouteThroughABend() {
        let corner = Geo.offset(start, bearing: 0, distanceM: 200)
        let geometry = RouteGeometry(points: [start, corner, Geo.offset(corner, bearing: 90, distanceM: 200)])
        var motion = RideMotion(geometry: geometry)
        var bearings: [Double] = []
        for tick in 0 ..< 1500 {
            let time = Double(tick) / 60
            if tick % 60 == 0 { motion.observe(fix(geometry, at: time, alongM: min(400, time * 10), speed: 10)) }
            if let frame = motion.frame(at: time) { bearings.append(frame.bearing) }
        }
        XCTAssertEqual(bearings.first ?? -1, 0, accuracy: 1)
        XCTAssertEqual(bearings.last ?? -1, 90, accuracy: 1)
        for (before, after) in zip(bearings, bearings.dropFirst()) {
            XCTAssertLessThan(abs(RideCamera.screenAngle(course: after, bearing: before)), 4, "the arrow snapped round")
        }
    }

    func testTheCompassTurnsTheMapWhenStandingStillAndTheCourseTakesOverWhenRiding() {
        let geometry = straight(bearing: 0)
        var motion = RideMotion(geometry: geometry)
        motion.observe(compass: CompassReading(degrees: 140, accuracy: 10))
        motion.observe(fix(geometry, at: 0, alongM: 0, speed: 0))
        var frame = motion.frame(at: 0)
        XCTAssertEqual(frame?.usesCompass, true)
        XCTAssertEqual(frame?.bearing ?? -1, 140, accuracy: 0.1)
        XCTAssertEqual(frame?.cameraBearing ?? -1, 140, accuracy: 0.1)

        for tick in 1 ... 600 {
            let time = Double(tick) / 60
            if tick % 60 == 0 { motion.observe(fix(geometry, at: time, alongM: time * 8, speed: 8)) }
            frame = motion.frame(at: time)
        }
        XCTAssertEqual(frame?.usesCompass, false)
        XCTAssertEqual(frame?.bearing ?? -1, 0, accuracy: 1)
        XCTAssertEqual(frame?.cameraBearing ?? -1, 0, accuracy: 1)
    }

    func testAnUnreliableOrMissingCompassLeavesTheCourseInCharge() {
        let geometry = straight(bearing: 45)
        for reading in [nil, CompassReading(degrees: 200, accuracy: -1), CompassReading(degrees: 200, accuracy: 90)] {
            var motion = RideMotion(geometry: geometry)
            motion.observe(compass: reading)
            motion.observe(fix(geometry, at: 0, alongM: 0, speed: 0))
            let frame = motion.frame(at: 0)
            XCTAssertEqual(frame?.usesCompass, false)
            XCTAssertEqual(frame?.bearing ?? -1, 45, accuracy: 0.5)
        }
    }

    func testTheCompassDoesNotFlickerOnAndOffAroundWalkingPace() {
        let geometry = straight()
        var motion = RideMotion(geometry: geometry)
        motion.observe(compass: CompassReading(degrees: 90, accuracy: 10))
        var switches = 0
        var last: Bool?
        var position = 0.0
        for tick in 0 ..< 1200 {
            let time = Double(tick) / 60
            if tick % 60 == 0 {
                let speed = (tick / 60) % 2 == 0 ? 1.4 : 2.2
                position += speed
                motion.observe(fix(geometry, at: time, alongM: position, speed: speed))
            }
            let uses = motion.frame(at: time)?.usesCompass
            if let last, let uses, last != uses { switches += 1 }
            last = uses
        }
        XCTAssertLessThanOrEqual(switches, 1)
    }

    func testTheDistanceToTheManeuverCountsDownEveryFrame() {
        let geometry = straight()
        var motion = RideMotion(geometry: geometry)
        var previous = Double.infinity
        for tick in 0 ..< 300 {
            let time = Double(tick) / 60
            if tick % 60 == 0 { motion.observe(fix(geometry, at: time, alongM: time * 10, speed: 10, maneuverM: 300)) }
            let distance = motion.frame(at: time)?.distanceToManeuverM ?? -1
            XCTAssertLessThanOrEqual(distance, previous)
            previous = distance
        }
        XCTAssertEqual(previous, 300 - 49.8, accuracy: 1.5)
    }

    func testAMopedPathLeavingTheCarriagewayIsRecognisedWithItsSide() {
        let corner = Geo.offset(start, bearing: 0, distanceM: 300)
        let geometry = RouteGeometry(points: [start, corner, Geo.offset(corner, bearing: 40, distanceM: 300)])
        func stretches(_ first: StretchClass, _ second: StretchClass) -> [Stretch] {
            [
                Stretch(stretchClass: first, startShapeIndex: 0, endShapeIndex: 1, lengthM: 300, wayIds: [1], unavoidable: nil),
                Stretch(stretchClass: second, startShapeIndex: 1, endShapeIndex: 2, lengthM: 300, wayIds: [2], unavoidable: nil),
            ]
        }
        let entering = stretches(.carriageway, .mopedPath)
        XCTAssertEqual(MopedPathEntry.at(maneuverM: 300, modifier: .slightRight, geometry: geometry, stretches: entering), .right)
        XCTAssertEqual(MopedPathEntry.at(maneuverM: 300, modifier: .left, geometry: geometry, stretches: entering), .left)
        XCTAssertEqual(MopedPathEntry.at(maneuverM: 300, modifier: .straight, geometry: geometry, stretches: entering), .right, "the path bears right")
        XCTAssertEqual(MopedPathEntry.at(maneuverM: 300, modifier: nil, geometry: geometry, stretches: entering), .right)

        XCTAssertNil(MopedPathEntry.at(maneuverM: 300, modifier: .slightRight, geometry: geometry, stretches: stretches(.mopedPath, .carriageway)))
        XCTAssertNil(MopedPathEntry.at(maneuverM: 300, modifier: .slightRight, geometry: geometry, stretches: stretches(.carriageway, .carriageway)))
        XCTAssertNil(MopedPathEntry.at(maneuverM: 300, modifier: .slightRight, geometry: geometry, stretches: stretches(.mopedPath, .mopedPath)))
        XCTAssertNil(MopedPathEntry.at(maneuverM: 300, modifier: .slightRight, geometry: geometry, stretches: stretches(.carriageway, .unverified)))
        XCTAssertNil(MopedPathEntry.at(maneuverM: 600, modifier: .slightRight, geometry: geometry, stretches: entering), "the arrival is not an entry")

        let bearsLeft = RouteGeometry(points: [start, corner, Geo.offset(corner, bearing: 320, distanceM: 300)])
        XCTAssertEqual(MopedPathEntry.at(maneuverM: 300, modifier: .straight, geometry: bearsLeft, stretches: entering), .left)
    }

    func testAPathThatStartsJustPastTheTurnStillCountsAsAnEntry() {
        let turn = Geo.offset(start, bearing: 0, distanceM: 300)
        let link = Geo.offset(turn, bearing: 45, distanceM: 25)
        let geometry = RouteGeometry(points: [start, turn, link, Geo.offset(link, bearing: 0, distanceM: 300)])
        let stretches = [
            Stretch(stretchClass: .carriageway, startShapeIndex: 0, endShapeIndex: 2, lengthM: 325, wayIds: [1], unavoidable: nil),
            Stretch(stretchClass: .mopedPath, startShapeIndex: 2, endShapeIndex: 3, lengthM: 300, wayIds: [2], unavoidable: nil),
        ]
        XCTAssertEqual(MopedPathEntry.at(maneuverM: 300, modifier: .slightRight, geometry: geometry, stretches: stretches), .right)
    }

    func testEveryStepOfTheFixtureRoutesGetsAnEntryOnlyWhereTheClassReallyChanges() throws {
        for name in ["route-default", "route-multi-stop", "route-verified-only"] {
            let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"))
            let plan = try RouteParser.parse(Data(contentsOf: url))
            let geometry = RouteGeometry(route: plan.route)
            for (index, step) in plan.route.steps.enumerated() {
                guard let maneuverM = geometry.maneuverM(afterCompletedSteps: index) else { continue }
                let modifier = step.visualInstructions.first?.primaryContent.maneuverModifier
                let entry = MopedPathEntry.at(maneuverM: maneuverM, modifier: modifier, geometry: geometry, stretches: plan.meta.stretches)
                let before = RouteLookup.stretchClass(atM: max(0, maneuverM - 10), geometry: geometry, stretches: plan.meta.stretches)
                if entry != nil {
                    XCTAssertEqual(before, .carriageway, "\(name) step \(index)")
                } else if before == .carriageway {
                    let after = RouteLookup.stretchClass(atM: min(maneuverM + 10, geometry.lengthM - 0.1), geometry: geometry, stretches: plan.meta.stretches)
                    XCTAssertNotEqual(after, .mopedPath, "\(name) step \(index) missed an entry")
                }
            }
        }
    }

    private func stretch(_ stretchClass: StretchClass, _ start: Int, _ end: Int) -> Stretch {
        Stretch(stretchClass: stretchClass, startShapeIndex: start, endShapeIndex: end, lengthM: 0, wayIds: [], unavoidable: nil)
    }

    func testAMapSignMarksWhereTheRouteLeavesTheCarriagewayForAMopedPath() {
        let corner = Geo.offset(start, bearing: 0, distanceM: 300)
        let bearsRight = RouteGeometry(points: [start, corner, Geo.offset(corner, bearing: 20, distanceM: 300)])
        let entering = [stretch(.carriageway, 0, 1), stretch(.mopedPath, 1, 2)]

        let markers = MopedPathMarker.all(geometry: bearsRight, stretches: entering)
        XCTAssertEqual(markers.map(\.side), [.right])
        XCTAssertEqual(markers.first?.coordinate, corner)
        XCTAssertEqual(markers.first?.alongM ?? 0, 300, accuracy: 0.5)

        let bearsLeft = RouteGeometry(points: [start, corner, Geo.offset(corner, bearing: 340, distanceM: 300)])
        XCTAssertEqual(MopedPathMarker.all(geometry: bearsLeft, stretches: entering).map(\.side), [.left])

        XCTAssertEqual(MopedPathMarker.all(geometry: bearsRight, stretches: [stretch(.mopedPath, 0, 1), stretch(.carriageway, 1, 2)]), [])
        XCTAssertEqual(MopedPathMarker.all(geometry: bearsRight, stretches: [stretch(.unverified, 0, 1), stretch(.mopedPath, 1, 2)]), [])
    }

    func testCrossingASideStreetOnTheMopedPathPutsNoSignOnTheMap() {
        let crossing = Geo.offset(start, bearing: 0, distanceM: 200)
        let across = Geo.offset(crossing, bearing: 0, distanceM: 12)
        let geometry = RouteGeometry(points: [start, crossing, across, Geo.offset(across, bearing: 0, distanceM: 200)])
        let stretches = [stretch(.mopedPath, 0, 1), stretch(.carriageway, 1, 2), stretch(.mopedPath, 2, 3)]
        XCTAssertEqual(MopedPathMarker.all(geometry: geometry, stretches: stretches), [])

        let fromTheDoor = [stretch(.carriageway, 0, 1), stretch(.mopedPath, 1, 2)]
        XCTAssertEqual(MopedPathMarker.all(geometry: RouteGeometry(points: [start, Geo.offset(start, bearing: 0, distanceM: 10), across]), stretches: fromTheDoor).count, 1, "a short first stretch still counts")
    }

    func testTheMapSignStaysPutWhileTheRiderApproachesAndGoesOnceTheyAreOnThePath() {
        let corner = Geo.offset(start, bearing: 0, distanceM: 300)
        let geometry = RouteGeometry(points: [start, Geo.offset(start, bearing: 0, distanceM: 150), corner, Geo.offset(corner, bearing: 20, distanceM: 300)])
        let stretches = [stretch(.carriageway, 0, 2), stretch(.mopedPath, 2, 3)]
        let expected = MopedPathMarker.all(geometry: geometry, stretches: stretches)
        XCTAssertEqual(expected.count, 1)
        for cut in [0.0, 100, 280, 295, 299] {
            XCTAssertEqual(RouteTrim.split(geometry: geometry, stretches: stretches, atM: cut).mopedPathMarkers, expected, "at \(cut) m")
        }
        XCTAssertEqual(RouteTrim.split(geometry: geometry, stretches: stretches, atM: 305).mopedPathMarkers, [])
    }

    func testTheFixtureRoutesOnlyGetMapSignsWhereACarriagewayTurnsIntoAMopedPath() throws {
        for name in ["route-default", "route-multi-stop", "route-verified-only"] {
            let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"))
            let plan = try RouteParser.parse(Data(contentsOf: url))
            let geometry = RouteGeometry(route: plan.route)
            for marker in plan.mopedPathMarkers {
                let before = RouteLookup.stretchClass(atM: marker.alongM - 1, geometry: geometry, stretches: plan.meta.stretches)
                let after = RouteLookup.stretchClass(atM: marker.alongM + 1, geometry: geometry, stretches: plan.meta.stretches)
                XCTAssertEqual(before, .carriageway, name)
                XCTAssertEqual(after, .mopedPath, name)
            }
        }
    }
}
