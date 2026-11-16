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
    var heading: Double?

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
                .lineWidth(9)
            LineStyleLayer(identifier: "route-others-line", source: others)
                .lineCap(.round)
                .lineJoin(.round)
                .lineColor(palette.otherRoute)
                .lineWidth(5)
            LineStyleLayer(identifier: "route-ridden-casing", source: riddenLine)
                .lineCap(.round)
                .lineJoin(.round)
                .lineColor(palette.casing)
                .lineWidth(9)
            LineStyleLayer(identifier: "route-ridden-line", source: riddenLine)
                .lineCap(.round)
                .lineJoin(.round)
                .lineColor(palette.ridden)
                .lineWidth(5)
            LineStyleLayer(identifier: "route-verified-casing", source: verified)
                .lineCap(.round)
                .lineJoin(.round)
                .lineColor(palette.casing)
                .lineWidth(11)
            LineStyleLayer(identifier: "route-unverified-casing", source: unverified)
                .lineCap(.butt)
                .lineJoin(.round)
                .lineColor(palette.casing)
                .lineWidth(11)
            LineStyleLayer(identifier: "route-forbidden-casing", source: forbidden)
                .lineCap(.butt)
                .lineJoin(.round)
                .lineColor(palette.forbiddenCasing)
                .lineWidth(11)
            LineStyleLayer(identifier: "route-verified-line", source: verified)
                .lineCap(.round)
                .lineJoin(.round)
                .lineColor(palette.verified)
                .lineWidth(7)
            LineStyleLayer(identifier: "route-unverified-line", source: unverified)
                .lineCap(.butt)
                .lineJoin(.round)
                .lineColor(palette.unverified)
                .lineWidth(7)
                .lineDashPattern([1.6, 1.0])
            LineStyleLayer(identifier: "route-forbidden-line", source: forbidden)
                .lineCap(.butt)
                .lineJoin(.round)
                .lineColor(palette.forbidden)
                .lineWidth(7)
                .lineDashPattern([0.6, 0.6])
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
            CircleStyleLayer(identifier: "route-user-halo", source: userPoint)
                .radius(24)
                .color(palette.halo)
            if let heading {
                HeadingPuckLayer(identifier: "route-user-puck", source: userPoint, heading: heading)
            } else {
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

struct HeadingPuckLayer: SourceBoundStyleLayerDefinition {
    static let imageName = "naviscoot-heading-puck"

    let identifier: String
    let sourceLayerIdentifier: String? = nil
    var source: StyleLayerSource
    var heading: Double
    var isVisible = true
    var minimumZoomLevel: Float?
    var maximumZoomLevel: Float?
    var insertionPosition: LayerInsertionPosition = .above(.all)

    init(identifier: String, source: ShapeSource, heading: Double) {
        self.identifier = identifier
        self.source = .source(source)
        self.heading = heading
    }

    func makeStyleLayer(style: MLNStyle) -> StyleLayer {
        if style.image(forName: Self.imageName) == nil {
            style.setImage(Self.image, forName: Self.imageName)
        }
        let styleSource: MLNSource = switch source {
        case let .mglSource(existing):
            existing
        case let .source(definition):
            style.source(withIdentifier: definition.identifier) ?? {
                let made = definition.makeMGLSource()
                style.addSource(made)
                return made
            }()
        }
        return Built(definition: self, styleSource: styleSource)
    }

    // Map alignment keeps the arrow on the travel direction whatever the camera bearing (course-up, panned or north-up).
    private struct Built: StyleLayer {
        var definition: HeadingPuckLayer
        let styleSource: MLNSource

        var identifier: String { definition.identifier }
        var isVisible: Bool {
            get { definition.isVisible }
            set { definition.isVisible = newValue }
        }
        var minimumZoomLevel: Float? {
            get { definition.minimumZoomLevel }
            set { definition.minimumZoomLevel = newValue }
        }
        var maximumZoomLevel: Float? {
            get { definition.maximumZoomLevel }
            set { definition.maximumZoomLevel = newValue }
        }
        var insertionPosition: LayerInsertionPosition {
            get { definition.insertionPosition }
            set { definition.insertionPosition = newValue }
        }

        func makeMLNStyleLayer() -> MLNStyleLayer {
            let layer = MLNSymbolStyleLayer(identifier: identifier, source: styleSource)
            layer.iconImageName = NSExpression(forConstantValue: HeadingPuckLayer.imageName)
            layer.iconRotation = NSExpression(forConstantValue: NSNumber(value: definition.heading))
            layer.iconRotationAlignment = NSExpression(forConstantValue: "map")
            layer.iconPitchAlignment = NSExpression(forConstantValue: "map")
            layer.iconAllowsOverlap = NSExpression(forConstantValue: true)
            layer.iconIgnoresPlacement = NSExpression(forConstantValue: true)
            return layer
        }
    }

    static let image: UIImage = {
        let size = CGSize(width: 44, height: 44)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            UIColor.white.setFill()
            UIBezierPath(arcCenter: center, radius: 20, startAngle: 0, endAngle: .pi * 2, clockwise: true).fill()
            Theme.verifiedUI.setFill()
            UIBezierPath(arcCenter: center, radius: 16.5, startAngle: 0, endAngle: .pi * 2, clockwise: true).fill()
            let arrow = UIBezierPath()
            arrow.move(to: CGPoint(x: center.x, y: center.y - 11))
            arrow.addLine(to: CGPoint(x: center.x + 8.5, y: center.y + 9))
            arrow.addLine(to: CGPoint(x: center.x, y: center.y + 4.5))
            arrow.addLine(to: CGPoint(x: center.x - 8.5, y: center.y + 9))
            arrow.close()
            UIColor.white.setFill()
            arrow.fill()
        }
    }()
}
