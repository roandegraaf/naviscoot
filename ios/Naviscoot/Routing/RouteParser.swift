import FerrostarCoreFFI
import Foundation

enum RouteParseError: Error, Equatable {
    case noRoute
    case geometryMismatch(geometryPoints: Int, lastShapeIndex: Int)
    case stretchOutOfRange(start: Int, end: Int, geometryPoints: Int)
}

enum RouteParser {
    private struct Envelope: Decodable {
        struct Summary: Decodable {
            let distance: Double
            let duration: Double
        }

        let routes: [Summary]
        let naviscoot: NaviscootMeta
    }

    static func parse(_ data: Data) throws -> RoutePlan {
        let routes = try createOsrmResponseParser(polylinePrecision: 6).parseResponse(response: data)
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard let route = routes.first, let summary = envelope.routes.first else {
            throw RouteParseError.noRoute
        }
        let segments = try split(geometry: route.geometry.map(Coordinate.init), stretches: envelope.naviscoot.stretches)
        return RoutePlan(route: route, durationS: summary.duration, meta: envelope.naviscoot, segments: segments)
    }

    static func split(geometry: [Coordinate], stretches: [Stretch]) throws -> [RouteSegment] {
        if let last = stretches.last, last.endShapeIndex != geometry.count - 1 {
            throw RouteParseError.geometryMismatch(geometryPoints: geometry.count, lastShapeIndex: last.endShapeIndex)
        }
        return try stretches.map { stretch in
            guard stretch.startShapeIndex >= 0,
                  stretch.startShapeIndex <= stretch.endShapeIndex,
                  stretch.endShapeIndex < geometry.count
            else {
                throw RouteParseError.stretchOutOfRange(
                    start: stretch.startShapeIndex,
                    end: stretch.endShapeIndex,
                    geometryPoints: geometry.count
                )
            }
            var points = Array(geometry[stretch.startShapeIndex ... stretch.endShapeIndex])
            if points.count == 1 {
                points.append(points[0])
            }
            return RouteSegment(stretchClass: stretch.stretchClass, coordinates: points)
        }
    }
}
