import FerrostarCoreFFI
@testable import Naviscoot
import XCTest

final class RideBannerTests: XCTestCase {
    private func steps(_ name: String) throws -> [RouteStep] {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"))
        return try RouteParser.parse(Data(contentsOf: url)).route.steps
    }

    @MainActor
    private func banner(_ steps: [RouteStep], at index: Int, instruction: Int = 0) throws -> RideModel.Banner {
        let remaining = Array(steps[index...])
        let visual = try XCTUnwrap(remaining.first?.visualInstructions[instruction])
        return RideModel.Banner(visual: visual, distanceM: 200, remainingSteps: remaining)
    }

    @MainActor
    func testCloseTurnsShowTheManeuverAfterNext() throws {
        let steps = try steps("route-default")
        XCTAssertEqual(steps[16].distance, 34, accuracy: 1)
        XCTAssertEqual(steps[17].distance, 96, accuracy: 1)

        let first = try banner(steps, at: 15)
        XCTAssertEqual(first.text, "Havenstraat")
        XCTAssertEqual(first.then, ManeuverSummary(text: "Vleenenck", maneuverType: .turn, maneuverModifier: .left))

        let second = try banner(steps, at: 16)
        XCTAssertEqual(second.then, ManeuverSummary(text: "Torenstraat", maneuverType: .turn, maneuverModifier: .right))

        XCTAssertGreaterThan(steps[18].distance, ManeuverHints.nextNextWithinM)
        XCTAssertNil(try banner(steps, at: 17).then)
    }

    @MainActor
    func testTheManeuverAfterNextThresholdIsInclusive() throws {
        var steps = try steps("route-default")
        steps[16].distance = ManeuverHints.nextNextWithinM
        XCTAssertNotNil(try banner(steps, at: 15).then)
        steps[16].distance = ManeuverHints.nextNextWithinM + 0.5
        XCTAssertNil(try banner(steps, at: 15).then)
    }

    @MainActor
    func testARoundaboutShowsItsExitNumberAndNoRedundantExitRow() throws {
        let steps = try steps("route-default")
        XCTAssertEqual(steps[19].roundaboutExitNumber, 2)

        let approach = try banner(steps, at: 18)
        XCTAssertEqual(approach.maneuverType, .roundabout)
        XCTAssertEqual(approach.exitNumber, 2)
        XCTAssertLessThanOrEqual(steps[19].distance, ManeuverHints.nextNextWithinM)
        XCTAssertNil(approach.then, "entering a roundabout must not repeat its exit as the next-next row")

        let inside = try banner(steps, at: 19)
        XCTAssertEqual(inside.maneuverType, .exitRoundabout)
        XCTAssertEqual(inside.exitNumber, 2)
    }

    @MainActor
    func testAStepWithLaneDataShowsLanesWithTheValidOnesMarked() throws {
        let steps = try steps("route-default")
        XCTAssertEqual(steps[38].visualInstructions.count, 2)

        XCTAssertEqual(try banner(steps, at: 38, instruction: 0).lanes, [])
        let near = try banner(steps, at: 38, instruction: 1)
        XCTAssertEqual(near.lanes, [LaneHint(direction: .left, valid: true), LaneHint(direction: .straight, valid: false)])
        XCTAssertNil(near.exitNumber)
    }

    @MainActor
    func testNothingIsInventedWithoutData() throws {
        let steps = try steps("route-default")
        for index in [0, 15, 17, 37] {
            let banner = try banner(steps, at: index)
            XCTAssertNil(banner.exitNumber, "step \(index)")
            XCTAssertEqual(banner.lanes, [], "step \(index)")
        }
    }

    @MainActor
    func testAStopArrivalDoesNotShowTheZeroLengthLegBoundaryAsNextNext() throws {
        let steps = try steps("route-multi-stop")
        XCTAssertEqual(steps[22].distance, 0)
        XCTAssertEqual(steps[22].visualInstructions, [])
        XCTAssertNil(try banner(steps, at: 21).then)
    }

    func testLaneDirectionsMapFromOSRMNames() {
        XCTAssertEqual(LaneDirection("slight left"), .slightLeft)
        XCTAssertEqual(LaneDirection("sharp right"), .sharpRight)
        XCTAssertEqual(LaneDirection("uturn"), .uTurn)
        XCTAssertEqual(LaneDirection("none"), .straight)
        let lane = LaneInfo(active: true, directions: ["straight", "right"], activeDirection: "right")
        let visual = VisualInstruction(
            primaryContent: VisualInstructionContent(text: "", maneuverType: .turn, maneuverModifier: .right, roundaboutExitDegrees: nil, laneInfo: nil, exitNumbers: []),
            secondaryContent: nil,
            subContent: VisualInstructionContent(text: "", maneuverType: nil, maneuverModifier: nil, roundaboutExitDegrees: nil, laneInfo: [lane, LaneInfo(active: false, directions: ["left"], activeDirection: nil)], exitNumbers: []),
            triggerDistanceBeforeManeuver: 400
        )
        XCTAssertEqual(ManeuverHints.lanes(in: visual), [LaneHint(direction: .right, valid: true), LaneHint(direction: .left, valid: false)])
    }
}

final class RouteTrimTests: XCTestCase {
    private let points = (0 ... 5).map { Coordinate(lat: 52 + Double($0) * 0.001, lon: 5) }
    private lazy var geometry = RouteGeometry(points: points)
    private let stretches = [
        Stretch(stretchClass: .carriageway, startShapeIndex: 0, endShapeIndex: 2, lengthM: 222, wayIds: [], unavoidable: nil),
        Stretch(stretchClass: .unverified, startShapeIndex: 2, endShapeIndex: 4, lengthM: 222, wayIds: [], unavoidable: nil),
        Stretch(stretchClass: .mopedPath, startShapeIndex: 4, endShapeIndex: 5, lengthM: 111, wayIds: [], unavoidable: nil),
    ]

    func testNothingRiddenAtTheStart() {
        let trim = RouteTrim.split(geometry: geometry, stretches: stretches, atM: 0)
        XCTAssertEqual(trim.ridden, [])
        XCTAssertEqual(trim.ahead.map(\.stretchClass), [.carriageway, .unverified, .mopedPath])
        XCTAssertEqual(trim.ahead[1].coordinates, Array(points[2 ... 4]))
    }

    func testACutInsideAStretchKeepsItsClassFromTheCutOn() throws {
        let cut = (geometry.cumulativeM[2] + geometry.cumulativeM[3]) / 2
        let trim = RouteTrim.split(geometry: geometry, stretches: stretches, atM: cut)
        let cutPoint = geometry.position(atM: cut).coordinate

        XCTAssertEqual(trim.ridden, Array(points[0 ... 2]) + [cutPoint])
        XCTAssertEqual(trim.ahead.map(\.stretchClass), [.unverified, .mopedPath])
        XCTAssertEqual(trim.ahead[0].coordinates, [cutPoint, points[3], points[4]])
        XCTAssertEqual(trim.ahead[1].coordinates, Array(points[4 ... 5]))
        XCTAssertEqual(cutPoint.lat, 52.0025, accuracy: 1e-9)
    }

    func testACutOnAStretchBoundaryDropsTheStretchBehind() {
        let trim = RouteTrim.split(geometry: geometry, stretches: stretches, atM: geometry.cumulativeM[2])
        XCTAssertEqual(trim.ahead.map(\.stretchClass), [.unverified, .mopedPath])
        XCTAssertEqual(trim.ahead[0].coordinates, Array(points[2 ... 4]))
        XCTAssertEqual(trim.ridden.first, points[0])
        XCTAssertEqual(trim.ridden.last, points[2])
    }

    func testEverythingRiddenAtTheEnd() {
        for distance in [geometry.lengthM, geometry.lengthM + 50] {
            let trim = RouteTrim.split(geometry: geometry, stretches: stretches, atM: distance)
            XCTAssertEqual(trim.ahead, [])
            XCTAssertEqual(trim.ridden.first, points.first)
            XCTAssertEqual(trim.ridden.last, points.last)
        }
    }

    func testARealRouteSplitsWithoutLosingLengthOrClasses() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "route-default", withExtension: "json"))
        let plan = try RouteParser.parse(Data(contentsOf: url))
        let geometry = RouteGeometry(route: plan.route)
        let cut = geometry.lengthM * 0.37
        let trim = RouteTrim.split(geometry: geometry, stretches: plan.meta.stretches, atM: cut)

        func length(_ line: [Coordinate]) -> Double {
            zip(line, line.dropFirst()).map { Geo.distanceM($0, $1) }.reduce(0, +)
        }
        XCTAssertEqual(length(trim.ridden), cut, accuracy: 0.5)
        XCTAssertEqual(trim.ahead.map { length($0.coordinates) }.reduce(0, +), geometry.lengthM - cut, accuracy: 0.5)
        let expected = plan.meta.stretches.filter { geometry.distanceM(atShapeIndex: $0.endShapeIndex) > cut }.map(\.stretchClass)
        XCTAssertEqual(trim.ahead.map(\.stretchClass), expected)
        XCTAssertEqual(trim.ahead.last?.coordinates.last, geometry.points.last)
    }

    func testTheScreenAngleIsTheCourseRelativeToTheMapBearing() {
        XCTAssertEqual(RideCamera.screenAngle(course: 90, bearing: 90), 0)
        XCTAssertEqual(RideCamera.screenAngle(course: 90, bearing: 0), 90)
        XCTAssertEqual(RideCamera.screenAngle(course: 10, bearing: 350), 20)
        XCTAssertEqual(RideCamera.screenAngle(course: 350, bearing: 10), -20)
        XCTAssertEqual(RideCamera.screenAngle(course: 0, bearing: 180), 180)
    }
}
