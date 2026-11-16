import MapLibre
import MapLibreSwiftUI
import SwiftUI

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
    @State private var screenHeight: CGFloat = 800
    @State private var sheetHeight: CGFloat = 470
    @State private var sheetCollapsed = false
    @State private var sheetDrag: CGFloat = 0
    @State private var scrollContentHeight: CGFloat = 0
    @State private var panelFrame: CGRect = .zero
    @State private var backFrame: CGRect = .zero
    @State private var windowFrame: CGRect = .zero
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
                destination: model.destination.coordinate
            )

            Button(action: onBack) {
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
            } else {
                VStack {
                    Spacer()
                    sheet
                }
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { screenHeight = $0 }
        .background {
            Color.clear
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { windowFrame = $0 }
                .ignoresSafeArea()
        }
        .onAppear { model.originChanged(location.coordinate) }
        .onChange(of: location.coordinate) { _, coordinate in model.originChanged(coordinate) }
        .onChange(of: plan?.meta.routeId) { _, _ in fitRoute() }
        .onChange(of: sheetHeight) { _, _ in
            if !focusedOnUnverified, !isLandscape { fitRoute() }
        }
        .onChange(of: [panelFrame, windowFrame]) { _, _ in
            if !focusedOnUnverified, isLandscape { fitRoute() }
        }
        .onChange(of: isLandscape) { _, _ in
            if !focusedOnUnverified { fitRoute() }
        }
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
        model.plans.enumerated()
            .filter { $0.offset != model.selectedIndex }
            .map { $0.element.route.geometry.map(Coordinate.init) }
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
                : UIEdgeInsets(top: 90, left: 36, bottom: sheetHeight + 10, right: 36)
        )
        focusedOnUnverified = false
    }

    private var isLandscape: Bool { verticalSizeClass == .compact }

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

    private var sheet: some View {
        VStack(spacing: 12) {
            sheetHandle

            if sheetCollapsed {
                collapsedContent
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
                    .gesture(sheetDragGesture)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        itinerary
                        content
                    }
                    .padding(.horizontal, 16)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { scrollContentHeight = $0 }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: min(scrollContentHeight, max(220, screenHeight * 0.5)))
            }

            footer
                .padding(.horizontal, 16)
        }
        .padding(.bottom, 34)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24)
                .fill(Theme.surface)
                .padding(.bottom, -400)
                .shadow(color: .black.opacity(0.12), radius: 12, y: -2)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { sheetHeight = $0 }
        .offset(y: sheetDrag)
    }

    private var sheetHandle: some View {
        Button {
            setSheetCollapsed(!sheetCollapsed)
        } label: {
            Capsule()
                .fill(Theme.line)
                .frame(width: 40, height: 5)
                .frame(maxWidth: .infinity, minHeight: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .gesture(sheetDragGesture)
        .accessibilityLabel(sheetCollapsed ? Strings.expandRouteDetails : Strings.collapseRouteDetails)
        .accessibilityIdentifier("preview.sheet.handle")
    }

    private var sheetDragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                let pull = value.translation.height
                sheetDrag = switch (sheetCollapsed, pull > 0) {
                case (false, true): pull
                case (true, false): max(pull * 0.5, -120)
                default: pull * 0.2
                }
            }
            .onEnded { value in
                let pull = value.predictedEndTranslation.height
                if sheetCollapsed, pull < -60 {
                    setSheetCollapsed(false)
                } else if !sheetCollapsed, pull > 100 {
                    setSheetCollapsed(true)
                } else {
                    withAnimation(.spring(duration: 0.3)) { sheetDrag = 0 }
                }
            }
    }

    private func setSheetCollapsed(_ collapsed: Bool) {
        withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
            sheetCollapsed = collapsed
            sheetDrag = 0
        }
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
        HStack(spacing: 12) {
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
                .accessibilityIdentifier("preview.stop.\(index)")
            Spacer(minLength: 0)
            if index > 0 {
                iconButton("arrow.up", label: Strings.moveStopUp, id: "preview.stop.\(index).up") {
                    model.moveStopUp(at: index)
                }
            }
            iconButton("xmark", label: Strings.removeStop, id: "preview.stop.\(index).remove") {
                model.removeStop(at: index)
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
                verifiedOnlyToggle(plan: plan)
                if case .loaded = model.state {
                    startControl
                        .frame(width: 140)
                }
            }
        } else {
            VStack(spacing: 12) {
                if !sheetCollapsed {
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
                    onStart(plan, ride)
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
        return Button {
            model.select(index)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(Format.duration(seconds: plan.durationS))
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Text(Format.distance(meters: plan.meta.lengthM))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.muted)
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
            Format.duration(seconds: plan.durationS),
            Format.distance(meters: plan.meta.lengthM),
            unverified,
        ].joined(separator: ", ")))
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
                : UIEdgeInsets(top: 160, left: 80, bottom: sheetHeight + 80, right: 80)
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
