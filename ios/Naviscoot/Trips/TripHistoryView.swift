import MapLibre
import MapLibreSwiftDSL
import MapLibreSwiftUI
import SwiftUI

struct TripHistoryView: View {
    @Environment(TripStore.self) private var trips
    @Environment(\.dismiss) private var dismiss
    @State private var path: [TripSummary]

    init(opening: TripSummary? = nil) {
        _path = State(initialValue: opening.map { [$0] } ?? [])
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if trips.trips.isEmpty {
                    Section {
                        Text(Strings.noTrips)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .frame(minHeight: 52)
                            .accessibilityIdentifier("trips.empty")
                    } footer: {
                        Text(Strings.noTripsFooter)
                    }
                } else {
                    Section {
                        TripTotalsGrid(totals: trips.totals, kmPerPercent: trips.consumption.kmPerPercent)
                    } header: {
                        Text(Strings.tripTotals)
                    }
                    Section {
                        ForEach(Array(trips.trips.enumerated()), id: \.element.id) { index, trip in
                            NavigationLink(value: trip) {
                                TripRow(trip: trip)
                            }
                            .accessibilityIdentifier("trips.trip.\(index)")
                            .accessibilityValue(Text(verbatim: TripDebug.value(trip)))
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    trips.delete(trip)
                                } label: {
                                    Label(Strings.deleteTrip, systemImage: "trash")
                                }
                                .accessibilityIdentifier("trips.delete")
                            }
                        }
                    } header: {
                        Text(Strings.tripsSection)
                    }
                }
            }
            .navigationTitle(Strings.tripHistory)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: TripSummary.self) { trip in
                TripDetailView(trip: trip, track: trips.track(for: trip))
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.done) { dismiss() }
                        .font(.system(size: 18, weight: .bold))
                        .accessibilityIdentifier("trips.done")
                }
            }
        }
    }
}

enum TripDebug {
    static func value(_ trip: TripSummary) -> String {
        String(format: "distanceM=%.0f durationS=%.0f avgKmh=%.1f", locale: Locale(identifier: "en_US_POSIX"), trip.distanceM, trip.durationS, trip.averageKmh)
    }
}

private struct TripRow: View {
    let trip: TripSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(trip.destination)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            Text(Format.dayTime(trip.startedAt))
                .font(.system(size: 15))
                .foregroundStyle(Theme.muted)
            Text(verbatim: [
                Format.distance(meters: Int(trip.distanceM.rounded())),
                Format.duration(seconds: trip.durationS),
                Format.speed(kmh: trip.averageKmh),
            ].joined(separator: " · "))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.body)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
    }
}

private struct TripTotalsGrid: View {
    let totals: TripTotals
    let kmPerPercent: Double?

    var body: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                StatTile(title: Strings.tripCount, value: "\(totals.count)", raw: "\(totals.count)", id: "trips.total.count")
                StatTile(
                    title: Strings.tripDistance,
                    value: Format.distance(meters: Int(totals.distanceM.rounded())),
                    raw: String(format: "%.0f", totals.distanceM),
                    id: "trips.total.distance"
                )
            }
            GridRow {
                StatTile(
                    title: Strings.tripTime,
                    value: Format.duration(seconds: totals.durationS),
                    raw: String(format: "%.0f", totals.durationS),
                    id: "trips.total.time"
                )
                StatTile(
                    title: Strings.tripSpeed,
                    value: Format.speed(kmh: totals.averageKmh),
                    raw: String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), totals.averageKmh),
                    id: "trips.total.speed"
                )
            }
            if let kmPerPercent {
                GridRow {
                    StatTile(
                        title: Strings.rangePerPercent,
                        value: Format.approximateDistance(meters: kmPerPercent * 1000),
                        raw: String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), kmPerPercent),
                        id: "trips.total.kmPerPercent"
                    )
                    .gridCellColumns(2)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    var raw: String?
    let id: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(verbatim: value)
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.iconBackground, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(title), \(value)"))
        .accessibilityValue(Text(verbatim: raw ?? value))
        .accessibilityIdentifier(id)
    }
}

struct TripDetailView: View {
    let trip: TripSummary
    let track: [[Coordinate]]

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        Group {
            if verticalSizeClass == .compact {
                HStack(alignment: .top, spacing: 16) {
                    map
                    ScrollView {
                        details
                    }
                    .frame(width: 340)
                }
                .padding(16)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        map
                            .frame(height: 340)
                        details
                    }
                    .padding(16)
                }
            }
        }
        .background(Theme.screen)
        .navigationTitle(Strings.trip)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var map: some View {
        TripMapView(track: track)
            .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(trip.destination)
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                    .accessibilityIdentifier("trip.destination")
                Text(Format.dayTime(trip.startedAt))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                if !trip.stops.isEmpty {
                    Text(Strings.tripVia(trip.stops))
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.body)
                        .accessibilityIdentifier("trip.stops")
                }
            }
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    StatTile(title: Strings.tripDistance, value: Format.distance(meters: Int(trip.distanceM.rounded())), id: "trip.distance")
                    StatTile(title: Strings.tripDuration, value: Format.duration(seconds: trip.durationS), id: "trip.duration")
                }
                GridRow {
                    StatTile(title: Strings.tripSpeed, value: Format.speed(kmh: trip.averageKmh), id: "trip.speed")
                        .gridCellColumns(2)
                }
            }
        }
    }
}

struct TripMapView: View {
    let track: [[Coordinate]]

    @Environment(AppSettings.self) private var settings
    @Environment(\.colorScheme) private var colorScheme
    @State private var camera: MapViewCamera
    @StateObject private var probe = TripMapProbe()

    init(track: [[Coordinate]]) {
        self.track = track
        let points = track.flatMap { $0 }
        if let bounds = RideCamera.bounds(of: points) {
            _camera = State(initialValue: .boundingBox(
                MLNCoordinateBounds(sw: bounds.southWest.clLocation, ne: bounds.northEast.clLocation),
                edgePadding: UIEdgeInsets(top: 40, left: 40, bottom: 40, right: 40)
            ))
        } else {
            _camera = State(initialValue: .center(SolarTimes.fallbackCoordinate.clLocation, zoom: 12))
        }
    }

    var body: some View {
        let points = track.flatMap { $0 }
        let style = MapStyle.resolve(
            choice: settings.mapStyle,
            darkAppearance: colorScheme == .dark,
            darkAtNight: settings.darkMapAtNight,
            isNight: SolarTimes.isNight(at: AppClock.shared.now(), coordinate: points.first ?? SolarTimes.fallbackCoordinate)
        )
        let palette = MapPalette.palette(for: style)
        MapView(styleURL: style.url, camera: $camera) {
            let line = ShapeSource(identifier: "trip-track") {
                track.filter { $0.count >= 2 }.map { MLNPolylineFeature(coordinates: $0.map(\.clLocation)) }
            }
            let ends = ShapeSource(identifier: "trip-ends") {
                [points.first, points.last].compactMap { $0 }.map { point -> MLNPointFeature in
                    let feature = MLNPointFeature()
                    feature.coordinate = point.clLocation
                    return feature
                }
            }
            LineStyleLayer(identifier: "trip-track-casing", source: line)
                .lineCap(.round)
                .lineJoin(.round)
                .lineColor(palette.casing)
                .lineWidth(10)
            LineStyleLayer(identifier: TripMapProbe.lineLayer, source: line)
                .lineCap(.round)
                .lineJoin(.round)
                .lineColor(palette.endpointStroke)
                .lineWidth(6)
            CircleStyleLayer(identifier: "trip-ends-dot", source: ends)
                .radius(8)
                .color(palette.endpointFill)
                .strokeColor(palette.endpointStroke)
                .strokeWidth(5)
        }
        .mapControls {
            LogoView()
            AttributionButton()
        }
        .unsafeMapViewControllerModifier { [probe] controller in
            probe.attach(controller.mapView)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Strings.tripMap)
        .accessibilityValue(Text(verbatim: RideOptions.current.simulate ? "segments=\(track.count) points=\(points.count) features=\(probe.features)" : ""))
        .accessibilityIdentifier("trip.map")
        .task {
            for _ in 0 ..< 40 where probe.features == 0 {
                try? await Task.sleep(for: .milliseconds(500))
                probe.count()
            }
        }
    }
}

@MainActor
final class TripMapProbe: ObservableObject {
    static let lineLayer = "trip-track-line"

    @Published private(set) var features = 0
    private weak var mapView: MLNMapView?

    func attach(_ mapView: MLNMapView) {
        if self.mapView !== mapView { self.mapView = mapView }
    }

    func count() {
        guard let mapView else { return }
        let rect = CGRect(origin: .zero, size: mapView.bounds.size)
        let found = mapView.visibleFeatures(in: rect, styleLayerIdentifiers: [Self.lineLayer]).count
        if found != features { features = found }
    }
}
