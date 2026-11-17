import MapLibre
import MapLibreSwiftDSL
import MapLibreSwiftUI
import SwiftUI

struct RouteMapView: View {
    @Binding var camera: MapViewCamera
    var segments: [RouteSegment] = []
    var otherRoutes: [[Coordinate]] = []
    var stops: [Coordinate] = []
    var origin: Coordinate?
    var destination: Coordinate?
    var user: Coordinate?
    var ridden: [Coordinate] = []
    var mopedPathMarkers: [MopedPathMarker] = []
    var drawsUser = true

    @Environment(AppSettings.self) private var settings
    @Environment(\.colorScheme) private var colorScheme
    @State private var night: Bool?

    var body: some View {
        let style = MapStyle.resolve(
            choice: settings.mapStyle,
            darkAppearance: colorScheme == .dark,
            darkAtNight: settings.darkMapAtNight,
            isNight: night ?? currentlyNight
        )
        let palette = MapPalette.palette(for: style)
        MapView(styleURL: style.url, camera: $camera) {
            let others = ShapeSource(identifier: "route-others") {
                otherRoutes.map { MLNPolylineFeature(coordinates: $0.map(\.clLocation)) }
            }
            let riddenLine = ShapeSource(identifier: "route-ridden") {
                ridden.count >= 2 ? [MLNPolylineFeature(coordinates: ridden.map(\.clLocation))] : []
            }
            let verified = ShapeSource(identifier: "route-verified") {
                features(where: { $0 == .carriageway || $0 == .mopedPath })
            }
            let mopedPath = ShapeSource(identifier: "route-moped-path") {
                features(where: { $0 == .mopedPath })
            }
            let mopedPathSigns = ShapeSource(identifier: "route-moped-path-signs") {
                mopedPathMarkers.map { marker -> MLNPointFeature in
                    let feature = MLNPointFeature()
                    feature.coordinate = marker.coordinate.clLocation
                    feature.attributes = ["side": marker.side == .left ? "left" : "right"]
                    return feature
                }
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
            let stopPoints = ShapeSource(identifier: "route-stops") {
                stops.enumerated().map { index, point -> MLNPointFeature in
                    let feature = MLNPointFeature()
                    feature.coordinate = point.clLocation
                    feature.attributes = ["label": "\(index + 1)"]
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

            LineStyleLayer(identifier: "route-others-casing", source: others)
                .lineCap(.round)
                .lineJoin(.round)
                .lineColor(palette.casing)
                .lineWidth(byZoom: LineWidths.secondaryCasing)
            LineStyleLayer(identifier: "route-others-line", source: others)
                .lineCap(.round)
                .lineJoin(.round)
                .lineColor(palette.otherRoute)
                .lineWidth(byZoom: LineWidths.secondaryLine)
            LineStyleLayer(identifier: "route-ridden-casing", source: riddenLine)
                .lineCap(.round)
                .lineJoin(.round)
                .lineColor(palette.casing)
                .lineWidth(byZoom: LineWidths.secondaryCasing)
            LineStyleLayer(identifier: "route-ridden-line", source: riddenLine)
                .lineCap(.round)
                .lineJoin(.round)
                .lineColor(palette.ridden)
                .lineWidth(byZoom: LineWidths.secondaryLine)
            LineStyleLayer(identifier: "route-verified-casing", source: verified)
                .lineCap(.round)
                .lineJoin(.round)
                .lineColor(palette.casing)
                .lineWidth(byZoom: LineWidths.casing)
            LineStyleLayer(identifier: "route-unverified-casing", source: unverified)
                .lineCap(.butt)
                .lineJoin(.round)
                .lineColor(palette.casing)
                .lineWidth(byZoom: LineWidths.casing)
            LineStyleLayer(identifier: "route-forbidden-casing", source: forbidden)
                .lineCap(.butt)
                .lineJoin(.round)
                .lineColor(palette.forbiddenCasing)
                .lineWidth(byZoom: LineWidths.casing)
            LineStyleLayer(identifier: "route-verified-line", source: verified)
                .lineCap(.round)
                .lineJoin(.round)
                .lineColor(palette.verified)
                .lineWidth(byZoom: LineWidths.line)
            LineStyleLayer(identifier: "route-unverified-line", source: unverified)
                .lineCap(.butt)
                .lineJoin(.round)
                .lineColor(palette.unverified)
                .lineWidth(byZoom: LineWidths.line)
                .lineDashPattern([1.6, 1.0])
            LineStyleLayer(identifier: "route-forbidden-line", source: forbidden)
                .lineCap(.butt)
                .lineJoin(.round)
                .lineColor(palette.forbidden)
                .lineWidth(byZoom: LineWidths.line)
                .lineDashPattern([0.6, 0.6])
            LineStyleLayer(identifier: "route-moped-path-stripe", source: mopedPath)
                .lineCap(.butt)
                .lineJoin(.round)
                .lineColor(palette.casing)
                .lineWidth(byZoom: LineWidths.stripe)
            SymbolStyleLayer(identifier: "route-moped-path-sign", source: mopedPathSigns)
                .iconImage(
                    featurePropertyNamed: "side",
                    mappings: ["left": MopedPathSign.leftMapIcon, "right": MopedPathSign.rightMapIcon],
                    default: MopedPathSign.rightMapIcon
                )
                .iconAnchor("bottom")
                .iconAllowsOverlap(true)
                .minimumZoomLevel(Float(RideCamera.minZoom))
            CircleStyleLayer(identifier: "route-endpoints-dot", source: endpoints)
                .radius(8)
                .color(palette.endpointFill)
                .strokeColor(palette.endpointStroke)
                .strokeWidth(5)
            CircleStyleLayer(identifier: "route-stops-dot", source: stopPoints)
                .radius(13)
                .color(palette.stopFill)
                .strokeColor(palette.stopStroke)
                .strokeWidth(3)
            SymbolStyleLayer(identifier: "route-stops-label", source: stopPoints)
                .text(featurePropertyNamed: "label")
                .textFontNames(["Noto Sans Bold"])
                .textFontSize(14)
                .textColor(palette.stopText)
                .textAllowsOverlap(true)
            if drawsUser {
                CircleStyleLayer(identifier: "route-user-halo", source: userPoint)
                    .radius(24)
                    .color(palette.halo)
                CircleStyleLayer(identifier: "route-user-dot", source: userPoint)
                    .radius(11)
                    .color(Theme.verifiedUI)
                    .strokeColor(.white)
                    .strokeWidth(4)
            }
        }
        .ignoresSafeArea()
        .task(id: nightReference) {
            let reference = nightReference
            while !Task.isCancelled {
                let now = SolarTimes.isNight(at: AppClock.shared.now(), coordinate: reference)
                if night != now { night = now }
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    private var currentlyNight: Bool {
        SolarTimes.isNight(at: AppClock.shared.now(), coordinate: nightReference)
    }

    private var nightReference: Coordinate {
        let point = user ?? origin ?? destination ?? SolarTimes.fallbackCoordinate
        return Coordinate(lat: (point.lat * 10).rounded() / 10, lon: (point.lon * 10).rounded() / 10)
    }

    private func features(where include: (StretchClass) -> Bool) -> [MLNPolylineFeature] {
        segments.filter { include($0.stretchClass) }.map { segment in
            MLNPolylineFeature(coordinates: segment.coordinates.map(\.clLocation))
        }
    }
}

// Thinner at ride zoom so the line can sit on a moped path beside the road instead of covering both.
private enum LineWidths {
    static let casing: [Double: Double] = [14: 11, 16.5: 8, 18: 7]
    static let line: [Double: Double] = [14: 7, 16.5: 5, 18: 4.5]
    static let stripe: [Double: Double] = [14: 2, 16.5: 1.5]
    static let secondaryCasing: [Double: Double] = [14: 9, 16.5: 7, 18: 6]
    static let secondaryLine: [Double: Double] = [14: 5, 16.5: 4, 18: 3.5]
}

private extension LineStyleLayer {
    func lineWidth(byZoom stops: [Double: Double]) -> Self {
        lineWidth(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil, stops: NSExpression(forConstantValue: stops))
    }
}
