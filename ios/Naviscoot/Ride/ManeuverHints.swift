import FerrostarCoreFFI
import Foundation

struct ManeuverSummary: Equatable {
    let text: String
    let maneuverType: ManeuverType?
    let maneuverModifier: ManeuverModifier?

    init(text: String, maneuverType: ManeuverType?, maneuverModifier: ManeuverModifier?) {
        self.text = text
        self.maneuverType = maneuverType
        self.maneuverModifier = maneuverModifier
    }

    init(_ content: VisualInstructionContent) {
        self.init(text: content.text, maneuverType: content.maneuverType, maneuverModifier: content.maneuverModifier)
    }
}

enum LaneDirection: Equatable {
    case straight
    case slightLeft
    case left
    case sharpLeft
    case slightRight
    case right
    case sharpRight
    case uTurn

    init(_ raw: String) {
        switch raw.lowercased() {
        case "slight left": self = .slightLeft
        case "left": self = .left
        case "sharp left": self = .sharpLeft
        case "slight right": self = .slightRight
        case "right": self = .right
        case "sharp right": self = .sharpRight
        case "uturn", "u-turn", "u turn": self = .uTurn
        default: self = .straight
        }
    }
}

struct LaneHint: Equatable {
    let direction: LaneDirection
    let valid: Bool
}

enum ManeuverHints {
    static let nextNextWithinM: Double = 150

    static func lanes(in visual: VisualInstruction) -> [LaneHint] {
        (visual.subContent?.laneInfo ?? []).map { lane in
            let shown = (lane.active ? lane.activeDirection : nil) ?? lane.directions.first ?? "straight"
            return LaneHint(direction: LaneDirection(shown), valid: lane.active)
        }
    }

    static func exitNumber(for visual: VisualInstruction, remainingSteps: [RouteStep]) -> Int? {
        let type = visual.primaryContent.maneuverType
        let step: RouteStep? = if isRoundaboutEntry(type) {
            remainingSteps.dropFirst().first
        } else if isRoundaboutExit(type) {
            remainingSteps.first
        } else {
            nil
        }
        return step?.roundaboutExitNumber.map(Int.init)
    }

    static func maneuverAfterNext(_ visual: VisualInstruction, remainingSteps: [RouteStep]) -> ManeuverSummary? {
        guard remainingSteps.count >= 2 else { return nil }
        let between = remainingSteps[1]
        guard between.distance > 0, between.distance <= nextNextWithinM,
              let content = between.visualInstructions.first?.primaryContent
        else { return nil }
        if isRoundaboutEntry(visual.primaryContent.maneuverType), isRoundaboutExit(content.maneuverType) {
            return nil
        }
        return ManeuverSummary(content)
    }

    static func isRoundaboutEntry(_ type: ManeuverType?) -> Bool {
        type == .roundabout || type == .rotary || type == .roundaboutTurn
    }

    static func isRoundaboutExit(_ type: ManeuverType?) -> Bool {
        type == .exitRoundabout || type == .exitRotary
    }
}

struct RouteTrim: Equatable {
    let ridden: [Coordinate]
    let ahead: [RouteSegment]

    static func split(geometry: RouteGeometry, stretches: [Stretch], atM distance: Double) -> RouteTrim {
        let points = geometry.points
        func whole(_ stretch: Stretch) -> RouteSegment {
            RouteSegment(stretchClass: stretch.stretchClass, coordinates: Array(points[stretch.startShapeIndex ... stretch.endShapeIndex]))
        }
        guard points.count >= 2, distance > 0 else {
            return RouteTrim(ridden: [], ahead: stretches.map(whole))
        }
        let cut = min(distance, geometry.lengthM)
        let cutPoint = geometry.position(atM: cut).coordinate
        let firstAhead = geometry.cumulativeM.firstIndex { $0 > cut } ?? points.count
        let ahead = stretches.compactMap { stretch -> RouteSegment? in
            guard geometry.distanceM(atShapeIndex: stretch.endShapeIndex) > cut else { return nil }
            guard geometry.distanceM(atShapeIndex: stretch.startShapeIndex) < cut else { return whole(stretch) }
            return RouteSegment(
                stretchClass: stretch.stretchClass,
                coordinates: [cutPoint] + points[firstAhead ... stretch.endShapeIndex]
            )
        }
        return RouteTrim(ridden: Array(points[..<firstAhead]) + [cutPoint], ahead: ahead)
    }
}
