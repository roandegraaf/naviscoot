import FerrostarCoreFFI
import Foundation

enum RouteParseError: Error, Equatable {
    case noRoute
    case routeCountMismatch(routes: Int, metas: Int)
    case legsMismatch(geometryPoints: Int)
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
        guard let plan = try parseAll(data).first else { throw RouteParseError.noRoute }
        return plan
    }

    static func parseAll(_ data: Data) throws -> [RoutePlan] {
        let routes = try createOsrmResponseParser(polylinePrecision: 6).parseResponse(response: data)
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        let metas = [envelope.naviscoot] + (envelope.naviscoot.alternates ?? [])
        guard !routes.isEmpty, !envelope.routes.isEmpty else { throw RouteParseError.noRoute }
        guard routes.count == metas.count, envelope.routes.count == metas.count else {
            throw RouteParseError.routeCountMismatch(routes: routes.count, metas: metas.count)
        }
        return try zip(routes, zip(envelope.routes, metas)).map { route, pair in
            let (summary, meta) = pair
            let geometry = route.geometry.map(Coordinate.init)
            try checkLegs(meta.legs, geometryPoints: geometry.count)
            let segments = try split(geometry: geometry, stretches: meta.stretches)
            return RoutePlan(
                route: route,
                durationS: summary.duration,
                meta: meta,
                segments: segments,
                mopedPathMarkers: MopedPathMarker.all(geometry: RouteGeometry(points: geometry), stretches: meta.stretches)
            )
        }
    }

    static func checkLegs(_ legs: [RouteLeg]?, geometryPoints: Int) throws {
        guard let legs, let first = legs.first, let last = legs.last else { return }
        let joined = zip(legs, legs.dropFirst()).allSatisfy { $0.endShapeIndex == $1.startShapeIndex }
        guard first.startShapeIndex == 0, last.endShapeIndex == geometryPoints - 1, joined else {
            throw RouteParseError.legsMismatch(geometryPoints: geometryPoints)
        }
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
