import FerrostarCoreFFI
import MapLibre
import MapLibreSwiftDSL
import MapLibreSwiftUI
import SwiftUI

struct RideView: View {
    @ObservedObject var model: RideModel
    @ObservedObject var location: LocationService
    let onEnd: () -> Void
    @State private var camera: MapViewCamera
    @State private var panelExpanded = false
    @State private var panelReady = false
    @State private var ending = false
    @State private var ended = false
    @StateObject private var tracker = RideCameraTracker()
    @State private var topFrame: CGRect = .zero
    @State private var sideFrame: CGRect = .zero
    @State private var bottomFrame: CGRect = .zero
    @State private var windowFrame: CGRect = .zero
    @State private var statusHeight: CGFloat = 0
    @Environment(\.openURL) private var openURL
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(AppSettings.self) private var settings
    @Environment(PlacesStore.self) private var places: PlacesStore?
    @Environment(ParkedScooterStore.self) private var parked: ParkedScooterStore?

    init(model: RideModel, location: LocationService, onEnd: @escaping () -> Void) {
        self.model = model
        self.location = location
        self.onEnd = onEnd
        let start = model.plan.route.geometry.first.map(Coordinate.init) ?? model.destination.coordinate
        let pitch = AppSettings.shared.threeD ? RideCamera.threeDPitch : 0
        _camera = State(initialValue: .center(start.clLocation, zoom: RideCamera.fixedZoom, pitch: pitch))
    }

    var body: some View {
        ZStack(alignment: .top) {
            RouteMapView(
                camera: $camera,
                segments: model.trim.ahead,
                stops: model.remainingStops.map(\.coordinate),
                destination: model.destination.coordinate,
                user: model.userCoordinate,
                ridden: model.trim.ridden,
                mopedPathMarkers: model.trim.mopedPathMarkers,
                drawsUser: false
            )
            .mapControls {
                LogoView()
                AttributionButton()
            }
            .mapCameraDisabled(tracker.camera.holdsStill)
            .unsafeMapViewControllerModifier { [tracker] controller in
                tracker.attach(controller.mapView)
            }
            .onMapViewProxyUpdate(updateMode: .realtime) { [tracker] proxy in
                tracker.mapChanged(proxy)
            }

            if isLandscape {
                landscapeOverlay
            } else {
                portraitOverlay
            }
        }
        .background {
            Color.clear
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { windowFrame = $0 }
                .ignoresSafeArea()
        }
        .onChange(of: [clearArea, windowFrame]) { _, _ in layOutMap() }
        .onChange(of: settings.northUp) { _, _ in layOutMap() }
        .onChange(of: model.arrived) { _, arrived in
            if arrived { withAnimation { panelExpanded = true } }
        }
        .onAppear {
            tracker.recordsDebug = model.options.simulate
            tracker.remainingRoute = { [weak model] in model?.remainingRoute ?? [] }
            tracker.userCoordinate = { [weak model] in model?.userCoordinate }
            tracker.motionFrame = { [weak model] time in model?.motionFrame(at: time) }
            tracker.options = { [settings] in settings.followOptions }
        }
        .onDisappear { tracker.stop() }
        .task {
            // Presenting while the previous screen's sheet is still animating away drops the presentation.
            try? await Task.sleep(for: .milliseconds(400))
            panelReady = true
        }
        .sheet(isPresented: panelPresented, onDismiss: finishEnding) {
            panel(inSheet: true)
                .environment(settings)
                .environment(places)
                .environment(parked)
                .presentationDetents([.ridePanelCollapsed, .medium], selection: panelDetent)
                .presentationBackgroundInteraction(.enabled)
                .presentationContentInteraction(.resizes)
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled()
                .drawerBackground()
        }
    }

    private var isLandscape: Bool { verticalSizeClass == .compact }

    private var panelPresented: Binding<Bool> {
        Binding(get: { panelReady && !isLandscape && !ending }, set: { _ in })
    }

    private var panelDetent: Binding<PresentationDetent> {
        Binding(
            get: { panelExpanded ? .medium : .ridePanelCollapsed },
            set: { panelExpanded = $0 != .ridePanelCollapsed }
        )
    }

    private func panel(inSheet: Bool) -> some View {
        RidePanel(model: model, expanded: $panelExpanded, inSheet: inSheet, onOverview: showOverview, onEnd: endRide)
    }

    private var portraitOverlay: some View {
        VStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                bannerView
                    .fixedSize(horizontal: false, vertical: true)
                statusRows
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { topFrame = $0 }
            .layoutPriority(1)

            HStack {
                Spacer()
                VStack(spacing: 12) {
                    reportButton
                    muteButton
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { sideFrame = $0 }
            }
            .padding(.trailing, 12)
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 10) {
                if let status = model.reportStatus {
                    reportToast(status)
                }
                HStack(alignment: .bottom, spacing: 10) {
                    speedView
                    if let limit = model.limitKmh {
                        limitSign(limit)
                    }
                    Spacer(minLength: 0)
                    recenterButton
                }
                if let alert = model.alert {
                    warning(alert)
                }
                if let scooterWarning = model.scooterWarning {
                    scooterAlert(scooterWarning)
                }
            }
            .padding(.horizontal, 12)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { bottomFrame = $0 }
            .padding(.bottom, RidePanel.collapsedHeight + 12)
        }
    }

    private var statusRows: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                chips
                troubleRows
                if model.options.simulate {
                    simulationPanel
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { statusHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: statusHeight)
    }

    private var landscapeOverlay: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                if !panelExpanded {
                    bannerView
                        .fixedSize(horizontal: false, vertical: true)
                    statusRows
                        .layoutPriority(1)
                    Spacer(minLength: 0)
                    if let status = model.reportStatus {
                        reportToast(status)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let alert = model.alert {
                        warning(alert)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let scooterWarning = model.scooterWarning {
                        scooterAlert(scooterWarning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                panel(inSheet: false)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24))
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 2)
                    .layoutPriority(2)
            }
            .frame(width: Self.landscapeColumnWidth)
            .frame(maxHeight: .infinity)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { topFrame = $0 }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 12) {
                HStack(spacing: 12) {
                    reportButton
                    muteButton
                }
                Spacer(minLength: 0)
                recenterButton
                HStack(alignment: .bottom, spacing: 10) {
                    if let limit = model.limitKmh {
                        limitSign(limit)
                    }
                    speedView
                }
            }
            .frame(width: Self.landscapeSideWidth, alignment: .trailing)
            .frame(maxHeight: .infinity)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { sideFrame = $0 }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private static let landscapeColumnWidth: CGFloat = 340
    private static let landscapeSideWidth: CGFloat = 178

    @ViewBuilder
    private var troubleRows: some View {
        if model.rerouteTrouble.isFailing {
            trouble(Strings.rerouteFailed, id: "ride.rerouteFailed")
        }
        if case let .failed(message) = model.editState {
            trouble(Strings.editFailed(message), id: "ride.editFailed")
        }
        if let trouble = location.trouble {
            locationTrouble(trouble)
        }
    }

    private var reportButton: some View {
        roundButton(symbol: "flag", tint: Theme.unverifiedText, label: Strings.report, id: "ride.report", action: model.report)
    }

    private var muteButton: some View {
        let mode = settings.guidanceMode
        return roundButton(
            symbol: Self.voiceSymbol(mode),
            tint: mode == .off ? Theme.dangerText : Theme.ink,
            label: mode == .off ? Strings.unmute : Strings.mute,
            id: "ride.mute",
            action: model.toggleMute
        )
        .accessibilityValue(Strings.voiceModeShort(mode))
    }

    static func voiceSymbol(_ mode: GuidanceMode) -> String {
        switch mode {
        case .all: "speaker.wave.2.fill"
        case .alertsOnly: "speaker.wave.1.fill"
        case .off: "speaker.slash.fill"
        }
    }

    private var followLayout: RideCamera.FollowLayout? {
        RideCamera.followLayout(area: clearArea, window: windowFrame.size, northUp: settings.northUp, landscape: isLandscape)
    }

    private func layOutMap() {
        let area = clearArea
        tracker.clearArea = area
        tracker.layout = followLayout
        switch tracker.camera.mode {
        case .following: tracker.setFollowInset(followInset)
        case .overview: showOverview()
        case .free: break
        }
    }

    // The frame-by-frame camera takes over from here; handing the map a new camera only replaces the overview it was
    // last given, which it would otherwise not show a second time.
    private func recenter() {
        tracker.layout = followLayout
        tracker.setFollowInset(followInset)
        tracker.recenter()
        if let coordinate = model.userCoordinate {
            let pitch = settings.threeD ? RideCamera.threeDPitch : 0
            camera = .center(coordinate.clLocation, zoom: RideCamera.fixedZoom, pitch: pitch, direction: model.courseDegrees)
        }
    }

    private func showOverview() {
        guard let bounds = RideCamera.bounds(of: model.remainingRoute) else { return }
        tracker.showOverview()
        let area = clearArea
        tracker.setFollowInset(isLandscape ? areaInset(for: area) : nil)
        let map = windowFrame.isEmpty ? tracker.mapSize : windowFrame.size
        var padding = area.isEmpty || map == .zero
            ? UIEdgeInsets(top: 220, left: 40, bottom: 300, right: 100)
            : UIEdgeInsets(
                top: area.minY + 16,
                left: area.minX + 16,
                bottom: map.height - area.maxY + 16,
                right: map.width - area.maxX + 16
            )
        // MapLibre adds the map's contentInset (the safe area in portrait, the follow inset in landscape) to edgePadding,
        // and the padding above is already measured from the screen edge, so the inset must not count twice.
        if let inset = tracker.contentInset {
            padding = UIEdgeInsets(
                top: max(0, padding.top - inset.top),
                left: max(0, padding.left - inset.left),
                bottom: max(0, padding.bottom - inset.bottom),
                right: max(0, padding.right - inset.right)
            )
        }
        camera = .boundingBox(
            MLNCoordinateBounds(sw: bounds.southWest.clLocation, ne: bounds.northEast.clLocation),
            edgePadding: padding
        )
    }

    private var clearArea: CGRect {
        if isLandscape {
            guard !topFrame.isEmpty, !sideFrame.isEmpty else { return .zero }
            let left = topFrame.maxX + 8
            let right = sideFrame.minX - 8
            let top = min(topFrame.minY, sideFrame.minY)
            let bottom = max(topFrame.maxY, sideFrame.maxY)
            guard right > left, bottom > top else { return .zero }
            return CGRect(x: left, y: top, width: right - left, height: bottom - top)
        }
        guard !topFrame.isEmpty, !sideFrame.isEmpty, !bottomFrame.isEmpty else { return .zero }
        let top = topFrame.maxY + 8
        let bottom = bottomFrame.minY - 8
        let right = sideFrame.minX - 8
        guard bottom > top, right > 8 else { return .zero }
        return CGRect(x: 8, y: top, width: right - 8, height: bottom - top)
    }

    private var followInset: UIEdgeInsets? {
        guard let layout = followLayout else { return nil }
        return UIEdgeInsets(
            top: layout.anchor.y - layout.halfSize.height,
            left: layout.anchor.x - layout.halfSize.width,
            bottom: windowFrame.height - layout.anchor.y - layout.halfSize.height,
            right: windowFrame.width - layout.anchor.x - layout.halfSize.width
        )
    }

    private func areaInset(for area: CGRect) -> UIEdgeInsets? {
        guard !area.isEmpty, !windowFrame.isEmpty else { return nil }
        return UIEdgeInsets(
            top: area.minY,
            left: area.minX,
            bottom: windowFrame.height - area.maxY,
            right: windowFrame.width - area.maxX
        )
    }

    private var recenterButton: some View {
        roundButton(
            symbol: tracker.camera.follows ? "location.fill" : "location",
            tint: Theme.verifiedText,
            label: Strings.recenter,
            id: "ride.recenter",
            action: recenter
        )
        .accessibilityValue(tracker.camera.mode.rawValue)
    }

    private func endRide() {
        guard !ending else { return }
        let waitsForPanel = panelPresented.wrappedValue
        ending = true
        model.end()
        guard waitsForPanel else { return finishEnding() }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            finishEnding()
        }
    }

    private func finishEnding() {
        guard ending, !ended else { return }
        ended = true
        onEnd()
    }

    private func trouble(_ text: String, id: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.system(size: 20, weight: .bold))
                .accessibilityHidden(true)
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 16, weight: .bold))
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.danger, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }

    private func locationTrouble(_ trouble: LocationTrouble) -> some View {
        HStack(spacing: 10) {
            self.trouble(trouble == .denied ? Strings.locationAccessOff : Strings.preciseLocationOff, id: "ride.locationTrouble")
            Button(Strings.locationSettings) {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .font(.system(size: 15, weight: .bold))
            .buttonStyle(.borderedProminent)
            .tint(Theme.bannerFill)
            .accessibilityIdentifier("ride.locationSettings")
        }
    }

    private var bannerView: some View {
        VStack(alignment: .leading, spacing: 12) {
            bannerMain
            if let banner = model.banner, !model.arrived {
                if !banner.lanes.isEmpty {
                    lanesRow(banner.lanes)
                }
                if let then = banner.then {
                    thenRow(then)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bannerFill, in: RoundedRectangle(cornerRadius: 22))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ride.banner")
    }

    private var bannerMain: some View {
        HStack(spacing: 16) {
            if let entry = model.banner?.mopedPathEntry, !model.arrived {
                MopedPathSign(side: entry)
                    .frame(width: 64, height: 72)
                    .accessibilityHidden(true)
                    .accessibilityIdentifier("ride.banner.mopedPathSign")
            } else {
                Image(systemName: Self.symbol(for: model.banner, arrived: model.arrived))
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                if model.arrived {
                    Text(Strings.arrived)
                        .font(.system(size: 30, weight: .heavy))
                        .foregroundStyle(.white)
                        .accessibilityIdentifier("ride.banner.street")
                } else if let banner = model.banner {
                    HStack(alignment: .center, spacing: 10) {
                        Text(Format.approximateDistance(meters: banner.distanceM))
                            .font(.system(size: 46, weight: .heavy))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                            .accessibilityIdentifier("ride.banner.distance")
                        if let exit = banner.exitNumber {
                            Text(Strings.roundaboutExit(exit))
                                .font(.system(size: 17, weight: .heavy))
                                .foregroundStyle(Theme.signInk)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(.white, in: Capsule())
                                .accessibilityLabel(Strings.roundaboutExitSpoken(exit))
                                .accessibilityIdentifier("ride.banner.exit")
                        } else if banner.mopedPathEntry != nil {
                            Text(Strings.chipMopedPath)
                                .font(.system(size: 17, weight: .heavy))
                                .foregroundStyle(MopedPathSign.red)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(.white, in: Capsule())
                                .accessibilityIdentifier("ride.banner.mopedPath")
                        }
                    }
                    Text(banner.text)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xE5E7EB))
                        .lineLimit(2)
                        .accessibilityIdentifier("ride.banner.street")
                } else {
                    Text(Strings.startingGuidance)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xE5E7EB))
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func lanesRow(_ lanes: [LaneHint]) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(lanes.enumerated()), id: \.offset) { _, lane in
                Image(systemName: Self.symbol(for: lane.direction))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(lane.valid ? Theme.signInk : .white.opacity(0.45))
                    .frame(width: 40, height: 40)
                    .background(lane.valid ? Color.white : .white.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Strings.lanes(valid: lanes.filter(\.valid).count, total: lanes.count))
        .accessibilityIdentifier("ride.banner.lanes")
    }

    private func thenRow(_ then: ManeuverSummary) -> some View {
        HStack(spacing: 10) {
            Text(Strings.then)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color(hex: 0x9CA3AF))
            Image(systemName: Self.symbol(type: then.maneuverType, modifier: then.maneuverModifier))
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
            Text(then.text)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color(hex: 0xE5E7EB))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Strings.thenManeuver(then.text))
        .accessibilityIdentifier("ride.banner.then")
    }

    private var chips: some View {
        HStack(spacing: 8) {
            if let stretchClass = model.currentClass {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Theme.barColor(for: stretchClass))
                        .frame(width: 10, height: 10)
                    Text(Strings.chip(for: stretchClass, limit: model.limitKmh))
                }
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.labelColor(for: stretchClass))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("ride.stretch")
            }
            if model.editState == .planning {
                Text(Strings.planningNewRoute)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.bannerFill, in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityIdentifier("ride.editPlanning")
            }
            if model.isRerouting {
                Text(Strings.rerouting)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.danger, in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityIdentifier("ride.rerouting")
            }
        }
    }

    private var simulationPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(verbatim: "\(Strings.simulatedRide), \(Strings.reroutes(model.rerouteCount))")
                    .accessibilityIdentifier("sim.status")
                Button(Strings.simulateDetour, action: model.simulateDetour)
                    .font(.system(size: 13, weight: .bold))
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("sim.detour")
            }
            Text(model.routeId)
                .font(.system(size: 10, design: .monospaced))
                .accessibilityIdentifier("sim.routeId")
            Text(verbatim: model.optionsSummary)
                .font(.system(size: 10, design: .monospaced))
                .accessibilityIdentifier("sim.options")
            Text(verbatim: tracker.debug)
                .font(.system(size: 10, design: .monospaced))
                .lineLimit(2)
                .accessibilityIdentifier("sim.camera")
            Text(verbatim: puckDebug)
                .font(.system(size: 10, design: .monospaced))
                .accessibilityIdentifier("sim.puck")
            Text(verbatim: tracker.styleDebug)
                .font(.system(size: 10, design: .monospaced))
                .accessibilityIdentifier("sim.style")
            Text(model.spoken.last.map { "\($0.language ?? "?"): \($0.text)" } ?? "")
                .lineLimit(2)
                .accessibilityIdentifier("sim.spoken")
                .accessibilityValue(model.spoken.map { "\($0.language ?? "?")|\($0.text)" }.joined(separator: "\n"))
            Text(verbatim: speechDebug)
                .font(.system(size: 10, design: .monospaced))
                .lineLimit(1)
                .accessibilityIdentifier("sim.speech")
                .accessibilityValue(model.speechDecisions.map {
                    "\($0.line.kind.rawValue)|\($0.spoken ? "spoken" : "suppressed")|\($0.line.text)"
                }.joined(separator: "\n"))
            Text(verbatim: activityDebug)
                .font(.system(size: 10, design: .monospaced))
                .lineLimit(1)
                .accessibilityIdentifier("sim.activity")
                .accessibilityValue(activityStateDebug)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(Theme.muted)
        .padding(8)
        .background(Theme.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
    }

    private var activityDebug: String {
        let stats = model.activityStats
        return "\(model.activityStatus) pushes=\(stats.pushes) bg=\(stats.backgroundPushes) spokenBg=\(stats.backgroundSpoken) remainingM=\(Int(model.remainingM ?? -1))"
    }

    private var activityStateDebug: String {
        guard let state = model.activityStats.lastState else { return "" }
        return [state.symbol, state.distance, state.street, state.arrivalLabel, state.arrival, state.remaining, state.warning ?? "-", state.arrived ? "arrived" : "riding"]
            .joined(separator: "|")
    }

    private var puckDebug: String {
        let screen = RideCamera.screenAngle(course: model.courseDegrees, bearing: tracker.bearing)
        return String(
            format: "course=%.0f bearing=%.0f screen=%.0f ridden=%d/%d",
            model.courseDegrees, tracker.bearing, screen, model.shapeIndex, model.plan.route.geometry.count
        )
    }

    private var speechDebug: String {
        let suppressed = model.speechDecisions.filter { !$0.spoken }.count
        let mode = model.speechDecisions.last?.mode ?? AppSettings.shared.guidanceMode
        let speeding = "speeding=\(model.isSpeeding ? "yes" : "no") episodes=\(model.speedingEpisodes)"
        guard let line = model.spoken.last else {
            return "mode=\(mode.rawValue) suppressed=\(suppressed) \(speeding) last=none"
        }
        return String(
            format: "mode=%@ suppressed=%d %@ last=%@ rate=%.2f volume=%.2f voice=%@",
            mode.rawValue, suppressed, speeding, line.kind.rawValue, line.rate, line.volume, line.voiceIdentifier ?? "none"
        )
    }

    private var speedView: some View {
        VStack(spacing: 0) {
            Text(model.speedKmh.map(String.init) ?? "–")
                .font(.system(size: 44, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(model.isSpeeding ? .white : Theme.ink)
            Text(Strings.kmh)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(model.isSpeeding ? .white : Theme.muted)
        }
        .frame(width: 104, height: 104)
        .background(model.isSpeeding ? Theme.danger : Theme.surface, in: Circle())
        .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityValue(model.isSpeeding ? Strings.overSpeedLimit : "")
        .accessibilityIdentifier("ride.speed")
    }

    private func limitSign(_ limit: Int) -> some View {
        Text(verbatim: "\(limit)")
            .font(.system(size: 28, weight: .heavy))
            .foregroundStyle(Theme.signInk)
            .frame(width: 64, height: 64)
            .background(.white, in: Circle())
            .overlay(Circle().stroke(Color(hex: 0xDC2626), lineWidth: 7))
            .accessibilityLabel(Strings.speedLimit(limit))
            .accessibilityIdentifier("ride.limit")
    }

    private func warning(_ alert: UnverifiedAlert) -> some View {
        let text = RideActivityContent.warningText(alert, language: .current)
        return HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22, weight: .bold))
                .accessibilityHidden(true)
            Text(text)
        }
        .font(.system(size: 16, weight: .bold))
        .foregroundStyle(Theme.unverifiedText)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.warningBackground, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.unverified, lineWidth: 2))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("ride.warning")
    }

    private func scooterAlert(_ warning: ScooterRideWarning) -> some View {
        HStack(spacing: 10) {
            Image(systemName: warning == .turnBack ? "arrow.uturn.backward.circle.fill" : "battery.25percent")
                .font(.system(size: 22, weight: .bold))
                .accessibilityHidden(true)
            Text(warning.text())
        }
        .font(.system(size: 16, weight: .bold))
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.danger, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("ride.scooterWarning")
    }

    private func reportToast(_ status: RideModel.ReportStatus) -> some View {
        let text = switch status {
        case .sending: Strings.reportSending
        case .sent: Strings.reportSent
        case let .queued(pending): Strings.reportQueued(pending)
        case .rejected: Strings.reportRejected
        }
        return Text(text)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Theme.bannerFill.opacity(0.92), in: Capsule())
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("ride.reportStatus")
    }

    private func roundButton(symbol: String, tint: Color, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 64, height: 64)
                .background(Theme.surface, in: Circle())
                .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
        }
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    static func symbol(for banner: RideModel.Banner?, arrived: Bool) -> String {
        if arrived { return "flag.checkered" }
        guard let banner else { return "location.north.line" }
        return symbol(type: banner.maneuverType, modifier: banner.maneuverModifier)
    }

    static func symbol(for lane: LaneDirection) -> String {
        switch lane {
        case .straight: "arrow.up"
        case .slightLeft: "arrow.up.left"
        case .left, .sharpLeft: "arrow.turn.up.left"
        case .slightRight: "arrow.up.right"
        case .right, .sharpRight: "arrow.turn.up.right"
        case .uTurn: "arrow.uturn.down"
        }
    }

    static func symbol(type: ManeuverType?, modifier: ManeuverModifier?) -> String {
        switch type {
        case .arrive: return "flag.checkered"
        case .roundabout, .rotary, .roundaboutTurn, .exitRoundabout, .exitRotary:
            return "arrow.triangle.turn.up.right.circle"
        default: break
        }
        switch modifier {
        case .uTurn: return "arrow.uturn.down"
        case .sharpRight, .right: return "arrow.turn.up.right"
        case .slightRight: return "arrow.up.right"
        case .sharpLeft, .left: return "arrow.turn.up.left"
        case .slightLeft: return "arrow.up.left"
        case .straight, .none: return "arrow.up"
        }
    }
}

enum RouteEditKind: String, Identifiable {
    case addStop
    case changeDestination

    var id: String { rawValue }

    var title: String {
        switch self {
        case .addStop: Strings.addStopMidRide
        case .changeDestination: Strings.changeDestination
        }
    }

    func edit(_ place: Destination) -> RouteEdit {
        switch self {
        case .addStop: .addStop(place)
        case .changeDestination: .changeDestination(place)
        }
    }
}

@MainActor
final class RideCameraTracker: ObservableObject {
    @Published private(set) var camera = RideCamera()
    @Published private(set) var debug = ""
    @Published private(set) var bearing: Double = 0
    @Published private(set) var styleDebug = ""
    var recordsDebug = false
    private weak var mapView: MLNMapView?
    var clearArea: CGRect = .zero
    var remainingRoute: () -> [Coordinate] = { [] }
    var userCoordinate: () -> Coordinate? = { nil }
    var motionFrame: (TimeInterval) -> RideMotion.Frame? = { _ in nil }
    var options: () -> RideCamera.FollowOptions = { RideCamera.FollowOptions() }
    var layout: RideCamera.FollowLayout?
    private(set) var followInset: UIEdgeInsets?
    private let puck = RidePuckView()
    private var ticker: FrameTicker?
    private var lastTick: TimeInterval?
    private var zoom: Double?
    private var pitch: Double?
    private var applied: Pose?
    private var startsRecentering = false
    private var recentering: (from: Pose, start: TimeInterval)?
    private var haloStyle: URL?
    private var baseInset: (automatic: Bool, inset: UIEdgeInsets)?
    private var latest: MapViewProxy?
    private var debugTask: Task<Void, Never>?

    var mapSize: CGSize { latest?.mapViewSize ?? .zero }
    var contentInset: UIEdgeInsets? { mapView?.contentInset }

    func mapChanged(_ proxy: MapViewProxy) {
        latest = proxy
        if proxy.lastReasonForChange?.isUserGesture == true, !camera.holdsStill {
            camera.userMovedMap()
            publishDebug()
        }
        guard recordsDebug else { return }
        guard debugTask == nil else { return }
        debugTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            self?.debugTask = nil
            self?.publishDebug()
        }
    }

    func attach(_ mapView: MLNMapView) {
        guard self.mapView !== mapView else { return }
        self.mapView = mapView
        baseInset = nil
        applyInset()
        puck.removeFromSuperview()
        mapView.addSubview(puck)
        applied = nil
        if ticker == nil {
            ticker = FrameTicker { [weak self] time in
                guard let self else { return false }
                self.frame(at: time)
                return true
            }
        }
    }

    func stop() {
        ticker?.stop()
        ticker = nil
    }

    private struct Pose {
        var center: Coordinate
        var zoom: Double
        var bearing: Double
        var pitch: Double

        func isClose(to other: Pose) -> Bool {
            Geo.distanceM(center, other.center) < 0.02 && abs(zoom - other.zoom) < 0.002
                && abs(RideCamera.screenAngle(course: bearing, bearing: other.bearing)) < 0.05 && abs(pitch - other.pitch) < 0.05
        }

        func blended(to other: Pose, share: Double) -> Pose {
            Pose(
                center: Coordinate(
                    lat: center.lat + (other.center.lat - center.lat) * share,
                    lon: center.lon + (other.center.lon - center.lon) * share
                ),
                zoom: zoom + (other.zoom - zoom) * share,
                bearing: RideMotion.turned(bearing, toward: other.bearing, by: share),
                pitch: pitch + (other.pitch - pitch) * share
            )
        }
    }

    private func frame(at time: TimeInterval) {
        let dt = lastTick.map { min(max(time - $0, 0), 0.25) } ?? 0
        lastTick = time
        guard let mapView, mapView.bounds.width > 0, mapView.bounds.height > 0, let frame = motionFrame(time) else { return }
        if camera.follows {
            follow(frame, on: mapView, time: time, dt: dt)
        } else {
            zoom = nil
            pitch = nil
            applied = nil
            recentering = nil
        }
        placePuck(frame, on: mapView)
    }

    private func follow(_ frame: RideMotion.Frame, on mapView: MLNMapView, time: TimeInterval, dt: Double) {
        let target = RideCamera.follow(
            bearing: frame.cameraBearing,
            options: options(),
            distanceToManeuverM: frame.distanceToManeuverM,
            speedKmh: frame.speedMps * 3.6,
            latitude: frame.coordinate.lat,
            viewport: layout?.viewport
        )
        let zoom = zoom.map { $0 + (target.zoom - $0) * RideMotion.blend(dt, tau: RideCamera.zoomTau) } ?? target.zoom
        let pitch = pitch.map { $0 + (target.pitch - $0) * RideMotion.blend(dt, tau: RideCamera.pitchTau) } ?? target.pitch
        self.zoom = zoom
        self.pitch = pitch
        var pose = Pose(center: frame.coordinate, zoom: zoom, bearing: target.direction, pitch: pitch)

        if startsRecentering {
            startsRecentering = false
            recentering = (Pose(
                center: Coordinate(mapView.centerCoordinate),
                zoom: mapView.zoomLevel,
                bearing: mapView.direction,
                pitch: mapView.camera.pitch
            ), time)
        }
        if let recentering {
            let share = (time - recentering.start) / RideCamera.recenterS
            if share >= 1 {
                self.recentering = nil
            } else {
                pose = recentering.from.blended(to: pose, share: share * share * (3 - 2 * share))
            }
        }

        if let applied, applied.isClose(to: pose) { return }
        applied = pose
        if mapView.minimumPitch != 0 { mapView.minimumPitch = 0 }
        if mapView.maximumPitch < 60 { mapView.maximumPitch = 60 }
        let altitude = MLNAltitudeForZoomLevel(pose.zoom, pose.pitch, pose.center.lat, mapView.frame.size)
        mapView.setCamera(
            MLNMapCamera(lookingAtCenter: pose.center.clLocation, altitude: altitude, pitch: pose.pitch, heading: pose.bearing),
            animated: false
        )
    }

    private func placePuck(_ frame: RideMotion.Frame, on mapView: MLNMapView) {
        if haloStyle != mapView.styleURL {
            haloStyle = mapView.styleURL
            let style = MapStyle.allCases.first { $0.url == mapView.styleURL } ?? .liberty
            puck.haloColor = MapPalette.palette(for: style).halo
        }
        if puck.superview !== mapView { mapView.addSubview(puck) }
        puck.place(
            at: mapView.convert(frame.coordinate.clLocation, toPointTo: mapView),
            screenAngle: RideCamera.screenAngle(course: frame.bearing, bearing: mapView.direction),
            pitch: mapView.camera.pitch
        )
    }

    func setFollowInset(_ inset: UIEdgeInsets?) {
        guard inset != followInset else { return }
        followInset = inset
        applied = nil
        applyInset()
    }

    private func applyInset() {
        guard let mapView else { return }
        if baseInset == nil, followInset != nil {
            baseInset = (mapView.automaticallyAdjustsContentInset, mapView.contentInset)
        }
        if let followInset {
            mapView.automaticallyAdjustsContentInset = false
            mapView.setContentInset(followInset, animated: false, completionHandler: nil)
        } else if let base = baseInset {
            mapView.automaticallyAdjustsContentInset = base.automatic
            mapView.setContentInset(base.inset, animated: false, completionHandler: nil)
            mapView.setNeedsLayout()
            mapView.layoutIfNeeded()
            baseInset = nil
        }
    }

    func recenter() {
        camera.recenter()
        startsRecentering = true
        applied = nil
        publishDebug()
    }

    func showOverview() {
        camera.showOverview()
        publishDebug()
    }

    private func publishDebug() {
        guard recordsDebug else { return }
        var text = "camera=\(camera.mode.rawValue)"
        if let direction = latest?.direction, direction != bearing { bearing = direction }
        if let latest {
            let center = latest.centerCoordinate
            text += String(format: " center=%.5f,%.5f", center.latitude, center.longitude)
        }
        if let mapView {
            text += String(format: " zoom=%.2f pitch=%.0f direction=%.0f", mapView.zoomLevel, mapView.camera.pitch, mapView.direction)
            publishStyleDebug(mapView)
        }
        if let latest {
            if let user = userCoordinate() {
                let point = latest.convert(user.clLocation, toPointTo: nil)
                text += String(format: " puck=%.0f,%.0f inClear=%@", point.x, point.y, clearArea.contains(point) ? "yes" : "no")
            }
            if camera.mode == .overview {
                let route = remainingRoute()
                let points = route.map { latest.convert($0.clLocation, toPointTo: nil) }
                let outside = points.filter { !clearArea.contains($0) }.count
                let fits = !route.isEmpty && !clearArea.isEmpty && outside == 0
                text += fits ? " fits=true" : " fits=false(\(outside)/\(route.count))"
                if let fill = Self.fill(points, in: clearArea) { text += String(format: " fill=%.2f", fill) }
                if !fits {
                    let xs = points.map(\.x), ys = points.map(\.y)
                    text += String(format: " x%.0f-%.0f y%.0f-%.0f clear%.0f,%.0f,%.0f,%.0f", xs.min() ?? 0, xs.max() ?? 0, ys.min() ?? 0, ys.max() ?? 0, clearArea.minX, clearArea.minY, clearArea.maxX, clearArea.maxY)
                }
            }
        }
        if text != debug { debug = text }
    }

    private static func fill(_ points: [CGPoint], in area: CGRect) -> Double? {
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max(),
              area.width > 0, area.height > 0 else { return nil }
        return max((maxX - minX) / area.width, (maxY - minY) / area.height)
    }

    private static let routeLayers: Set<String> = [
        "route-verified-line", "route-unverified-line", "route-forbidden-line", "route-ridden-line",
    ]

    private func publishStyleDebug(_ mapView: MLNMapView) {
        let style = MapStyle.allCases.first { $0.url == mapView.styleURL }?.rawValue ?? mapView.styleURL?.lastPathComponent ?? "?"
        let rect = CGRect(origin: .zero, size: mapView.bounds.size)
        let features = mapView.visibleFeatures(in: rect, styleLayerIdentifiers: Self.routeLayers)
        let layers = Self.routeLayers.filter { mapView.style?.layer(withIdentifier: $0) != nil }.count
        let text = "style=\(style) layers=\(layers)/\(Self.routeLayers.count) features=\(features.count)"
        if text != styleDebug { styleDebug = text }
    }
}

extension CameraChangeReason {
    var isUserGesture: Bool {
        switch self {
        case .gesturePan, .gesturePinch, .gestureRotate, .gestureZoomIn, .gestureZoomOut, .gestureOneFingerZoom, .gestureTilt: true
        case .programmatic, .resetNorth, .transitionCancelled: false
        }
    }
}
