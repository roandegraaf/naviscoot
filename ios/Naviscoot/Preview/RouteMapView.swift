import MapLibre
import MapLibreSwiftDSL
import MapLibreSwiftUI
import SwiftUI

struct RouteMapView: View {
    @Binding var camera: MapViewCamera
    var segments: [RouteSegment] = []
    var origin: Coordinate?
    var destination: Coordinate?
    var user: Coordinate?

    var body: some View {
        MapView(styleURL: Theme.mapStyleURL, camera: $camera) {
            let verified = ShapeSource(identifier: "route-verified") {
                features(where: { $0 == .carriageway || $0 == .mopedPath })
            }
            let unverified = ShapeSource(identifier: "route-unverified") {
                features(where: { $0 == .unverified })
            }
            let forbidden = ShapeSource(identifier: "route-forbidden") {
                features(where: { $0 == .forbidden })
            }
            let endpoints = ShapeSource(identifier: "route-endpoints") {
                [origin, destination].compactMap { $0 }.map { point -> MLNPointFeature in
                    let feature = MLNPointFeature()
                    feature.coordinate = point.clLocation
                    return feature
                }
            }
            let userPoint = ShapeSource(identifier: "route-user") {
                [user].compactMap { $0 }.map { point -> MLNPointFeature in
                    let feature = MLNPointFeature()
                    feature.coordinate = point.clLocation
                    return feature
                }
            }

            LineStyleLayer(identifier: "route-verified-casing", source: verified)
                .lineCap(.round)
                .lineJoin(.round)
                .lineColor(.white)
                .lineWidth(11)
            LineStyleLayer(identifier: "route-unverified-casing", source: unverified)
                .lineCap(.butt)
                .lineJoin(.round)
                .lineColor(.white)
                .lineWidth(11)
            LineStyleLayer(identifier: "route-verified-line", source: verified)
                .lineCap(.round)
                .lineJoin(.round)
                .lineColor(Theme.verifiedUI)
                .lineWidth(7)
            LineStyleLayer(identifier: "route-unverified-line", source: unverified)
                .lineCap(.butt)
                .lineJoin(.round)
                .lineColor(Theme.unverifiedUI)
                .lineWidth(7)
                .lineDashPattern([1.6, 1.0])
            LineStyleLayer(identifier: "route-forbidden-line", source: forbidden)
                .lineCap(.butt)
                .lineJoin(.round)
                .lineColor(Theme.dangerUI)
                .lineWidth(7)
                .lineDashPattern([0.6, 0.6])
            CircleStyleLayer(identifier: "route-endpoints-dot", source: endpoints)
                .radius(8)
                .color(.white)
                .strokeColor(Theme.inkUI)
                .strokeWidth(5)
            CircleStyleLayer(identifier: "route-user-halo", source: userPoint)
                .radius(24)
                .color(Theme.verifiedUI.withAlphaComponent(0.18))
            CircleStyleLayer(identifier: "route-user-dot", source: userPoint)
                .radius(11)
                .color(Theme.verifiedUI)
                .strokeColor(.white)
                .strokeWidth(4)
        }
        .ignoresSafeArea()
    }

    private func features(where include: (StretchClass) -> Bool) -> [MLNPolylineFeature] {
        segments.filter { include($0.stretchClass) }.map { segment in
            MLNPolylineFeature(coordinates: segment.coordinates.map(\.clLocation))
        }
    }
}
