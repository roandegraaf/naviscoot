import MapLibre
import MapLibreSwiftUI
import SwiftUI

struct PreviewView: View {
    @StateObject private var model: PreviewModel
    @ObservedObject var location: LocationService
    let onBack: () -> Void
    let onStart: (RoutePlan, Bool) -> Void

    @State private var camera: MapViewCamera
    @State private var focusedOnUnverified = false
    private static let sheetHeight: CGFloat = 470

    init(
        destination: Destination,
        client: NaviscootClient?,
        location: LocationService,
        onBack: @escaping () -> Void,
        onStart: @escaping (RoutePlan, Bool) -> Void
    ) {
        _model = StateObject(wrappedValue: PreviewModel(destination: destination, client: client))
        self.location = location
        self.onBack = onBack
        self.onStart = onStart
        _camera = State(initialValue: .center(destination.coordinate.clLocation, zoom: 13))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RouteMapView(
                camera: $camera,
                segments: plan?.segments ?? [],
                origin: location.coordinate,
                destination: model.destination.coordinate
            )

            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 60, height: 60)
                    .background(.white, in: Circle())
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
            }
            .accessibilityLabel(Strings.back)
            .padding(.leading, 12)
            .padding(.top, 8)

            VStack {
                Spacer()
                sheet
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .onAppear { model.originChanged(location.coordinate) }
        .onChange(of: location.coordinate) { _, coordinate in model.originChanged(coordinate) }
        .onChange(of: plan?.meta.routeId) { _, _ in fitRoute() }
    }

    private var plan: RoutePlan? {
        if case let .loaded(plan) = model.state { return plan }
        return nil
    }

    private func fitRoute() {
        guard let bbox = plan?.route.bbox else { return }
        let bounds = MLNCoordinateBounds(
            sw: CLLocationCoordinate2D(latitude: bbox.sw.lat, longitude: bbox.sw.lng),
            ne: CLLocationCoordinate2D(latitude: bbox.ne.lat, longitude: bbox.ne.lng)
        )
        camera = .boundingBox(bounds, edgePadding: UIEdgeInsets(top: 90, left: 36, bottom: Self.sheetHeight - 10, right: 36))
        focusedOnUnverified = false
    }

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Strings.to)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                Text(model.destination.subtitle.isEmpty
                    ? model.destination.title
                    : "\(model.destination.title), \(model.destination.subtitle)")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .accessibilityIdentifier("preview.destination")
            }
            content
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 34)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))
        .shadow(color: .black.opacity(0.12), radius: 12, y: -2)
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .waitingForLocation:
            status(location.denied ? Strings.locationDenied : Strings.waitingForLocation, spinner: !location.denied)
        case .loading:
            status(Strings.calculating, spinner: true)
            verifiedOnlyToggle(plan: nil)
        case let .failed(message):
            status(message, spinner: false)
            Button(Strings.retry) { model.reload() }
                .font(.system(size: 20, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 60)
                .background(Theme.line.opacity(0.4), in: Capsule())
        case let .loaded(plan):
            summary(plan)
            breakdown(plan.meta.totalsM)
            verifiedOnlyToggle(plan: plan)
            Button {
                onStart(plan, model.verifiedOnly)
            } label: {
                Text(Strings.start)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(Theme.verified, in: Capsule())
            }
            .accessibilityIdentifier("preview.start")
        }
    }

    private func status(_ text: String, spinner: Bool) -> some View {
        HStack(spacing: 12) {
            if spinner { ProgressView() }
            Text(text)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .accessibilityIdentifier("preview.status")
    }

    private func summary(_ plan: RoutePlan) -> some View {
        let arrival = Format.clockTime(Date().addingTimeInterval(plan.durationS))
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(Format.duration(seconds: plan.durationS))
                .font(.system(size: 34, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .accessibilityIdentifier("preview.duration")
            Text("\(Format.distance(meters: plan.meta.lengthM)), \(Strings.arrive(arrival))")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .accessibilityIdentifier("preview.distance")
        }
    }

    private func breakdown(_ totals: RouteTotals) -> some View {
        let classes = StretchClass.allCases.filter { $0 != .forbidden || totals.forbidden > 0 }
        return VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    ForEach(classes.filter { totals[$0] > 0 }, id: \.self) { stretchClass in
                        Theme.barColor(for: stretchClass)
                            .frame(width: max(4, proxy.size.width * CGFloat(totals[stretchClass]) / CGFloat(max(1, totals.sum))))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 12)
            .accessibilityHidden(true)

            ForEach(classes, id: \.self) { stretchClass in
                if stretchClass == .unverified, totals.unverified > 0 {
                    Button(action: toggleUnverifiedFocus) {
                        totalRow(stretchClass, totals: totals, showsMapHint: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Strings.showOnMap)
                    .accessibilityIdentifier("preview.total.\(stretchClass.rawValue)")
                } else {
                    totalRow(stretchClass, totals: totals, showsMapHint: false)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("preview.total.\(stretchClass.rawValue)")
                }
            }
        }
    }

    private func totalRow(_ stretchClass: StretchClass, totals: RouteTotals, showsMapHint: Bool) -> some View {
        HStack(spacing: 8) {
            Text(Strings.label(for: stretchClass))
                .foregroundStyle(Theme.labelColor(for: stretchClass))
            if showsMapHint {
                Image(systemName: focusedOnUnverified ? "arrow.up.left.and.arrow.down.right" : "scope")
                    .foregroundStyle(Theme.unverifiedText)
                    .accessibilityHidden(true)
            }
            Spacer()
            Text(Format.distance(meters: totals[stretchClass]))
                .foregroundStyle(Color(hex: 0x374151))
        }
        .font(.system(size: 17, weight: .semibold))
        .frame(minHeight: showsMapHint ? 44 : 0)
        .contentShape(Rectangle())
    }

    private func toggleUnverifiedFocus() {
        guard let plan else { return }
        if focusedOnUnverified {
            fitRoute()
            return
        }
        let points = plan.segments.filter { $0.stretchClass == .unverified }.flatMap(\.coordinates)
        guard let first = points.first else { return }
        var sw = first.clLocation
        var ne = first.clLocation
        for point in points {
            sw.latitude = min(sw.latitude, point.lat)
            sw.longitude = min(sw.longitude, point.lon)
            ne.latitude = max(ne.latitude, point.lat)
            ne.longitude = max(ne.longitude, point.lon)
        }
        camera = .boundingBox(
            MLNCoordinateBounds(sw: sw, ne: ne),
            edgePadding: UIEdgeInsets(top: 160, left: 80, bottom: Self.sheetHeight + 80, right: 80)
        )
        focusedOnUnverified = true
    }

    private func verifiedOnlyToggle(plan: RoutePlan?) -> some View {
        Toggle(isOn: $model.verifiedOnly) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Strings.verifiedOnly)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text(verifiedOnlySubtitle(plan))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.muted)
            }
        }
        .tint(Theme.verified)
        .padding(.horizontal, 14)
        .frame(minHeight: 64)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line, lineWidth: 2))
        .accessibilityIdentifier("preview.verifiedOnly")
    }

    private func verifiedOnlySubtitle(_ plan: RoutePlan?) -> String {
        if model.verifiedOnly {
            guard let remaining = plan?.meta.totalsM.unverified, remaining > 0 else { return Strings.verifiedOnlyActive }
            return Strings.stillUnverified(Format.distance(meters: remaining))
        }
        guard let unverified = model.defaultUnverifiedM else { return " " }
        guard unverified > 0 else { return Strings.verifiedOnlyNothingToSkip }
        return Strings.skipsUnverified(Format.distance(meters: unverified))
    }
}
