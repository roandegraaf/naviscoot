import MapLibre
import MapLibreSwiftUI
import SwiftUI

extension PresentationDetent {
    static let previewCollapsed = PresentationDetent.height(PreviewView.collapsedHeight)
}

struct PreviewView: View {
    private enum SearchTarget: String, Identifiable {
        case start
        case stop

        var id: String { rawValue }
    }

    @StateObject private var model: PreviewModel
    @ObservedObject var location: LocationService
    let onBack: () -> Void
    let onStart: (RoutePlan, ActiveRide) -> Void

    @State private var camera: MapViewCamera
    @State private var focusedOnUnverified = false
    @State private var searchTarget: SearchTarget?
    @State private var showsTimeSheet = false
    @State private var choosingSave = false
    @Environment(PlacesStore.self) private var places
    @Environment(ScooterConnection.self) private var scooter
    @Environment(TripStore.self) private var trips
    @Environment(AppSettings.self) private var settings
    @State private var detent: PresentationDetent = .medium
    @State private var drawerReady = false
    @State private var leaving = false
    @State private var pendingExit: (() -> Void)?
    @State private var scrollContentHeight: CGFloat = 0
    @State private var panelFrame: CGRect = .zero
    @State private var backFrame: CGRect = .zero
    @State private var windowFrame: CGRect = .zero
    @State private var routePoints = MapPointTracker()
    @State private var stopDropTarget: Int?
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    init(
        destination: Destination,
        client: NaviscootClient?,
        settings: AppSettings,
        location: LocationService,
        onBack: @escaping () -> Void,
        onStart: @escaping (RoutePlan, ActiveRide) -> Void
    ) {
        _model = StateObject(wrappedValue: PreviewModel(destination: destination, client: client, settings: settings))
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
                otherRoutes: otherRoutes,
                stops: model.trip.stops.map(\.coordinate),
                origin: originCoordinate,
                destination: model.destination.coordinate,
                mopedPathMarkers: plan?.mopedPathMarkers ?? []
            )
            .onMapViewProxyUpdate(updateMode: .realtime) { [routePoints] proxy in
                routePoints.mapChanged(proxy)
            }
            .onTapMapGesture { context in
                selectRoute(near: Coordinate(context.coordinate))
            }
            .overlay(alignment: .topLeading) {
                if model.plans.count > 1 {
                    RouteTimeBubbles(bubbles: bubbles, tracker: routePoints) { model.select($0) }
                        .ignoresSafeArea()
                }
            }

            Button {
                leave(then: onBack)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 60, height: 60)
                    .background(Theme.surface, in: Circle())
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
            }
            .accessibilityLabel(Strings.back)
            .accessibilityIdentifier("preview.back")
            .padding(.leading, 12)
            .padding(.top, 8)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { backFrame = $0 }

            if isLandscape {
                HStack(alignment: .top, spacing: 0) {
                    Spacer(minLength: 0)
                    sidePanel
                }
                .padding(.trailing, 12)
                .padding(.vertical, 8)
            }
        }
        .background {
            Color.clear
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { windowFrame = $0 }
                .ignoresSafeArea()
        }
        .onAppear {
            model.originChanged(location.coordinate)
            routePoints.track(model.bubbleAnchors)
        }
        .onChange(of: model.bubbleAnchors) { _, anchors in routePoints.track(anchors) }
        .onChange(of: location.coordinate) { _, coordinate in model.originChanged(coordinate) }
        .onChange(of: plan?.meta.routeId) { _, _ in fitRoute() }
        .onChange(of: detent) { _, newDetent in
            if !focusedOnUnverified, !isLandscape, newDetent != .large { fitRoute() }
        }
        .onChange(of: [panelFrame, windowFrame]) { _, _ in
            if !focusedOnUnverified { fitRoute() }
        }
        .onChange(of: isLandscape) { _, _ in
            if !focusedOnUnverified { fitRoute() }
        }
        .task {
            // Presenting while the home drawer is still animating away drops the presentation.
            try? await Task.sleep(for: .milliseconds(400))
            drawerReady = true
        }
        .sheet(isPresented: drawerPresented, onDismiss: finishLeaving) {
            drawer
                .environment(settings)
                .environment(places)
                .environment(scooter)
                .environment(trips)
                .presentationDetents([.previewCollapsed, .medium, .large], selection: $detent)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .presentationContentInteraction(.resizes)
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled()
                .drawerBackground()
        }
    }

    static let collapsedHeight: CGFloat = 200

    private var drawerPresented: Binding<Bool> {
        Binding(get: { drawerReady && !isLandscape && !leaving }, set: { _ in })
    }

    private var collapsed: Bool { detent == .previewCollapsed }

    private func leave(then action: @escaping () -> Void) {
        guard !leaving else { return }
        let waitsForDrawer = drawerPresented.wrappedValue
        leaving = true
        pendingExit = action
        guard waitsForDrawer else { return finishLeaving() }
        Task {
            try? await Task.sleep(for: .seconds(1))
            finishLeaving()
        }
    }

    private func finishLeaving() {
        guard leaving, let pendingExit else { return }
        self.pendingExit = nil
        pendingExit()
    }

    private func withPanelPresentations(_ panel: some View) -> some View {
        panel
            .sheet(item: $searchTarget) { target in
                switch target {
                case .start:
                    PlaceSearchSheet(
                        title: Strings.startSearchTitle,
                        near: location.coordinate,
                        onCurrentLocation: { model.setStart(.currentLocation) },
                        onSelect: { model.setStart(.place($0)) }
                    )
                case .stop:
                    PlaceSearchSheet(title: Strings.stopSearchTitle, near: location.coordinate) { model.addStop($0) }
                }
            }
            .sheet(isPresented: $showsTimeSheet) {
                TripTimeSheet(time: model.trip.time) { model.setTime($0) }
            }
            .confirmationDialog(Strings.savePlace, isPresented: $choosingSave, titleVisibility: .hidden) {
                if !savedKinds.contains(.favourite) {
                    Button(Strings.saveAsFavourite) { places.addFavourite(model.destination) }
                        .accessibilityIdentifier("preview.save.favourite")
                }
                Button(Strings.saveAsHome) { places.setHome(model.destination) }
                    .accessibilityIdentifier("preview.save.home")
                Button(Strings.saveAsWork) { places.setWork(model.destination) }
                    .accessibilityIdentifier("preview.save.work")
                Button(Strings.cancel, role: .cancel) {}
            }
    }

    private var plan: RoutePlan? { model.selectedPlan }

    private var otherRoutes: [[Coordinate]] {
        alternatives.map(\.coordinates)
    }

    private var alternatives: [(index: Int, coordinates: [Coordinate])] {
        model.plans.enumerated()
            .filter { $0.offset != model.selectedIndex }
            .map { ($0.offset, $0.element.route.geometry.map(Coordinate.init)) }
    }

    private var bubbles: [RouteTimeBubble] {
        model.plans.enumerated().map { index, plan in
            RouteTimeBubble(
                index: index,
                duration: Format.duration(seconds: plan.durationS),
                selected: index == model.selectedIndex
            )
        }
    }

    private func selectRoute(near coordinate: Coordinate) {
        guard model.plans.count > 1, let tap = routePoints.screenPoints([coordinate]).first else { return }
        let routes = alternatives.map { (index: $0.index, points: routePoints.screenPoints($0.coordinates)) }
        if let index = RouteBubbles.nearestRoute(to: tap, routes: routes, tolerance: 22) {
            model.select(index)
        }
    }

    private var originCoordinate: Coordinate? {
        switch model.trip.start {
        case .currentLocation: location.coordinate
        case let .place(place): place.coordinate
        }
    }

    private func fitRoute() {
        let boxes = model.plans.map(\.route.bbox)
        guard let first = boxes.first else { return }
        var sw = CLLocationCoordinate2D(latitude: first.sw.lat, longitude: first.sw.lng)
        var ne = CLLocationCoordinate2D(latitude: first.ne.lat, longitude: first.ne.lng)
        for box in boxes {
            sw.latitude = min(sw.latitude, box.sw.lat)
            sw.longitude = min(sw.longitude, box.sw.lng)
            ne.latitude = max(ne.latitude, box.ne.lat)
            ne.longitude = max(ne.longitude, box.ne.lng)
        }
        camera = .boundingBox(
            MLNCoordinateBounds(sw: sw, ne: ne),
            edgePadding: isLandscape
                ? landscapePadding(extra: 16)
                : UIEdgeInsets(top: 90, left: 36, bottom: drawerInset + 10, right: 36)
        )
        focusedOnUnverified = false
    }

    private var isLandscape: Bool { verticalSizeClass == .compact }

    private var drawerInset: CGFloat {
        guard !collapsed else { return Self.collapsedHeight }
        return (windowFrame.isEmpty ? 800 : windowFrame.height) / 2
    }

    private func landscapePadding(extra: CGFloat) -> UIEdgeInsets {
        guard !panelFrame.isEmpty, !windowFrame.isEmpty else {
            return UIEdgeInsets(top: 30 + extra, left: 100 + extra, bottom: 30 + extra, right: 440 + extra)
        }
        return UIEdgeInsets(
            top: panelFrame.minY + extra,
            left: backFrame.maxX + extra,
            bottom: windowFrame.height - panelFrame.maxY + extra,
            right: windowFrame.width - panelFrame.minX + extra
        )
    }

    private var sidePanel: some View {
        withPanelPresentations(sidePanelBody)
    }

    private var sidePanelBody: some View {
        VStack(spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    itinerary
                    content
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { scrollContentHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: scrollContentHeight)

            footer
                .padding(.horizontal, 16)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 12)
        .frame(width: windowFrame.isEmpty ? 400 : min(420, windowFrame.width * 0.48))
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 2)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { panelFrame = $0 }
    }

    private var drawer: some View {
        let panel = VStack(spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if collapsed {
                        collapsedContent
                    } else {
                        itinerary
                        content
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 22)
            }
            .scrollBounceBehavior(.basedOnSize)
            .accessibilityIdentifier("preview.drawer")

            footer
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        return withPanelPresentations(panel)
    }

    @ViewBuilder
    private var collapsedContent: some View {
        if case .loaded = model.state, let plan {
            VStack(alignment: .leading, spacing: 2) {
                summary(plan)
                Text(model.destination.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            content
        }
    }

    private var itinerary: some View {
        VStack(alignment: .leading, spacing: 4) {
            fromRow
            ForEach(Array(model.trip.stops.enumerated()), id: \.offset) { index, stop in
                stopRow(index: index, stop: stop)
                    .contentShape(Rectangle())
                    .draggable(TripPlan.stopDragPayload(index)) {
                        stopRow(index: index, stop: stop)
                            .padding(.horizontal, 12)
                            .frame(width: 320)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .dropDestination(for: String.self) { payloads, _ in
                        guard let source = payloads.first.flatMap(TripPlan.stopIndex(fromDragPayload:)) else { return false }
                        model.moveStop(from: source, to: index)
                        return true
                    } isTargeted: { targeted in
                        if targeted {
                            stopDropTarget = index
                        } else if stopDropTarget == index {
                            stopDropTarget = nil
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(stopDropTarget == index ? Theme.selectedBackground : .clear)
                            .padding(.horizontal, -6)
                    )
            }
            toRow
            HStack(spacing: 10) {
                if model.trip.canAddStop {
                    chip(Strings.addStop, systemImage: "plus", id: "preview.addStop") { searchTarget = .stop }
                }
                chip(timeLabel, systemImage: "clock", id: "preview.time") { showsTimeSheet = true }
            }
            .padding(.top, 6)
        }
    }

    private var fromRow: some View {
        HStack(spacing: 12) {
            Button {
                searchTarget = .start
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: model.trip.startsFromCurrentLocation ? "location.fill" : "circle.circle")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.verified)
                        .frame(width: 32)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(Strings.from)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                        Text(startTitle)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint(Strings.changeStart)
            .accessibilityIdentifier("preview.from")

            if !model.trip.startsFromCurrentLocation {
                iconButton("location", label: Strings.useYourLocation, id: "preview.from.reset") {
                    model.setStart(.currentLocation)
                }
            }
        }
    }

    private var startTitle: String {
        switch model.trip.start {
        case .currentLocation: Strings.yourLocation
        case let .place(place): place.title
        }
    }

    private func stopRow(index: Int, stop: Destination) -> some View {
        let count = model.trip.stops.count
        return HStack(spacing: 12) {
            Text(verbatim: "\(index + 1)")
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(Theme.screen)
                .frame(width: 26, height: 26)
                .background(Theme.ink, in: Circle())
                .frame(width: 32)
                .accessibilityHidden(true)
            Text(stop.title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .accessibilityLabel(Text(verbatim: "\(Strings.stop(index + 1)), \(stop.title)"))
                .accessibilityAction(named: Strings.moveStopUp) {
                    if index > 0 { model.moveStop(from: index, to: index - 1) }
                }
                .accessibilityAction(named: Strings.moveStopDown) {
                    if index < count - 1 { model.moveStop(from: index, to: index + 1) }
                }
                .accessibilityIdentifier("preview.stop.\(index)")
            Spacer(minLength: 0)
            iconButton("xmark", label: Strings.removeStop, id: "preview.stop.\(index).remove") {
                model.removeStop(at: index)
            }
            if count > 1 {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 32, height: 44)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 52)
    }

    private var toRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(Strings.to)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                Text(model.destination.subtitle.isEmpty
                    ? model.destination.title
                    : "\(model.destination.title), \(model.destination.subtitle)")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .accessibilityIdentifier("preview.destination")
            }
            Spacer(minLength: 0)
            Button {
                choosingSave = true
            } label: {
                Image(systemName: savedKinds.isEmpty ? "star" : "star.fill")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 44, height: 44)
                    .background(Theme.iconBackground, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Strings.savePlace)
            .accessibilityValue(savedKinds.isEmpty ? "" : Strings.savedPlace)
            .accessibilityIdentifier("preview.save")
        }
        .frame(minHeight: 52)
    }

    private var savedKinds: Set<PlaceKind> { places.savedKinds(at: model.destination.coordinate) }

    private var timeLabel: String {
        switch model.trip.time {
        case nil: Strings.leaveNow
        case let .departAt(date): "\(Strings.timeMode(.departAt)) · \(Format.dayTime(date))"
        case let .arriveBy(date): "\(Strings.timeMode(.arriveBy)) · \(Format.dayTime(date))"
        }
    }

    private func chip(_ title: String, systemImage: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(Theme.iconBackground, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private func iconButton(_ systemImage: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 44, height: 44)
                .background(Theme.iconBackground, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .waitingForLocation:
            status(location.denied ? Strings.locationDenied : Strings.waitingForLocation, spinner: !location.denied)
        case .loading:
            status(Strings.calculating, spinner: true)
        case let .failed(message):
            status(message, spinner: false)
            Button(Strings.retry) { model.reload() }
                .font(.system(size: 20, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 60)
                .background(Theme.line.opacity(0.4), in: Capsule())
        case let .loaded(plans):
            if plans.count > 1 {
                routeList(plans)
            }
            if let plan {
                summary(plan)
                rangeLine(plan)
                breakdown(plan.meta.totalsM)
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if isLandscape {
            HStack(alignment: .center, spacing: 12) {
                if model.showsVerifiedOnlyToggle {
                    verifiedOnlyToggle(plan: plan)
                    if case .loaded = model.state {
                        startControl
                            .frame(width: 140)
                    }
                } else {
                    startControl
                }
            }
        } else {
            VStack(spacing: 12) {
                if !collapsed, model.showsVerifiedOnlyToggle {
                    verifiedOnlyToggle(plan: plan)
                }
                startControl
            }
        }
    }

    @ViewBuilder
    private var startControl: some View {
        if case .loaded = model.state {
            if let plan, let ride = model.rideToStart() {
                Button {
                    leave { onStart(plan, ride) }
                } label: {
                    Text(Strings.start)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .background(Theme.verified, in: Capsule())
                }
                .accessibilityIdentifier("preview.start")
            } else {
                Text(Strings.startFromYourLocation)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .accessibilityIdentifier("preview.startHint")
            }
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

    private func routeList(_ plans: [RoutePlan]) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(plans.enumerated()), id: \.offset) { index, plan in
                routeCard(index: index, plan: plan)
            }
        }
    }

    private func routeCard(index: Int, plan: RoutePlan) -> some View {
        let selected = index == model.selectedIndex
        let unverified = unverifiedText(plan)
        let roads = plan.mainRoadPercent.map(Strings.routeMainRoads)
        let quiet = plan.meta.profile == .quiet
        return Button {
            model.select(index)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(Format.duration(seconds: plan.durationS))
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    if quiet {
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.verified)
                    }
                }
                Text(Format.distance(meters: plan.meta.lengthM))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                if let roads {
                    Text(roads)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(quiet ? Theme.verified : Theme.muted)
                }
                Text(unverified)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(plan.meta.totalsM.unverified > 0 ? Theme.unverifiedText : Theme.muted)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(selected ? Theme.selectedBackground : Theme.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? Theme.verified : Theme.line, lineWidth: selected ? 3 : 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: [
            Strings.route(index + 1),
            quiet ? Strings.routeQuiet : nil,
            Format.duration(seconds: plan.durationS),
            Format.distance(meters: plan.meta.lengthM),
            roads,
            unverified,
        ].compactMap { $0 }.joined(separator: ", ")))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("preview.route.\(index).\(plan.meta.routeId)")
    }

    private func unverifiedText(_ plan: RoutePlan) -> String {
        switch UnverifiedStatus(meta: plan.meta) {
        case .none: Strings.routeNoUnverified
        case let .unavoidable(meters) where model.verifiedOnly: Strings.routeUnavoidable(Format.distance(meters: meters))
        case let .unavoidable(meters), let .remaining(meters): Strings.routeUnverified(Format.distance(meters: meters))
        }
    }

    private func summary(_ plan: RoutePlan) -> some View {
        let schedule = TripPlan.schedule(for: model.trip.time, durationS: plan.durationS, now: Date())
        let when = if case .arriveBy = model.trip.time {
            Strings.leaveAt(Format.clockTime(schedule.departure))
        } else {
            Strings.arrive(Format.clockTime(schedule.arrival))
        }
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(Format.duration(seconds: plan.durationS))
                .font(.system(size: 34, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .accessibilityIdentifier("preview.duration")
            Text(verbatim: "\(Format.distance(meters: plan.meta.lengthM)), \(when)")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .accessibilityIdentifier("preview.distance")
        }
    }

    @ViewBuilder
    private func rangeLine(_ plan: RoutePlan) -> some View {
        if let check = RangeCheck(
            routeM: plan.meta.lengthM,
            telemetry: scooter.telemetry,
            readAt: scooter.telemetryAt,
            now: Date(),
            model: trips.consumption,
            marginPercent: settings.rangeMarginPercent
        ) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "\(check.headline) · \(check.roundTripText)")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Self.color(check.oneWay))
                Text(verbatim: check.detail)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("preview.range")
        }
    }

    private static func color(_ verdict: RangeVerdict) -> Color {
        switch verdict {
        case .fits: Theme.verifiedText
        case .tight: Theme.unverifiedText
        case .short: Theme.dangerText
        }
    }

    private func breakdown(_ totals: RouteTotals) -> some View {
        let classes = totals.presentClasses
        return VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    ForEach(classes, id: \.self) { stretchClass in
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
            Circle()
                .fill(Theme.barColor(for: stretchClass))
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            Text(Strings.label(for: stretchClass))
                .foregroundStyle(Theme.labelColor(for: stretchClass))
            if showsMapHint {
                Image(systemName: focusedOnUnverified ? "arrow.up.left.and.arrow.down.right" : "scope")
                    .foregroundStyle(Theme.unverifiedText)
                    .accessibilityHidden(true)
            }
            Spacer()
            Text(Format.distance(meters: totals[stretchClass]))
                .foregroundStyle(Theme.body)
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
            edgePadding: isLandscape
                ? landscapePadding(extra: 60)
                : UIEdgeInsets(top: 160, left: 80, bottom: drawerInset + 80, right: 80)
        )
        focusedOnUnverified = true
        if detent == .large { detent = .medium }
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
            guard let plan else { return Strings.verifiedOnlyActive }
            switch UnverifiedStatus(meta: plan.meta) {
            case .none: return Strings.verifiedOnlyActive
            case let .unavoidable(meters): return Strings.stillUnverified(Format.distance(meters: meters))
            case let .remaining(meters): return Strings.verifiedOnlyRemaining(Format.distance(meters: meters))
            }
        }
        guard let unverified = model.defaultUnverifiedM else { return " " }
        guard unverified > 0 else { return Strings.verifiedOnlyNothingToSkip }
        return Strings.skipsUnverified(Format.distance(meters: unverified))
    }
}

struct RouteTimeBubble: Identifiable {
    let index: Int
    let duration: String
    let selected: Bool

    var id: Int { index }
}

private struct RouteTimeBubbles: View {
    let bubbles: [RouteTimeBubble]
    let tracker: MapPointTracker
    let onSelect: (Int) -> Void

    var body: some View {
        let points = tracker.points
        ZStack(alignment: .topLeading) {
            ForEach(bubbles.sorted { !$0.selected && $1.selected }) { bubble in
                if points.indices.contains(bubble.index) {
                    button(bubble)
                        .position(points[bubble.index])
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func button(_ bubble: RouteTimeBubble) -> some View {
        Button {
            onSelect(bubble.index)
        } label: {
            Text(verbatim: bubble.duration)
                .font(.system(size: 15, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(bubble.selected ? .white : Theme.ink)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(bubble.selected ? Theme.verified : Theme.surface, in: Capsule())
                .overlay(Capsule().stroke(bubble.selected ? Color.white : Theme.line, lineWidth: 2))
                .shadow(color: .black.opacity(0.22), radius: 4, y: 2)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "\(Strings.route(bubble.index + 1)), \(bubble.duration)"))
        .accessibilityAddTraits(bubble.selected ? .isSelected : [])
        .accessibilityIdentifier("preview.bubble.\(bubble.index)")
    }
}
