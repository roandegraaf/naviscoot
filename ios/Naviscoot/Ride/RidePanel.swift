import SwiftUI

extension PresentationDetent {
    static let ridePanelCollapsed = PresentationDetent.height(RidePanel.collapsedHeight)
}

struct VoiceModePicker: View {
    @Binding var selection: GuidanceMode
    var id = "voiceMode"

    var body: some View {
        Picker(Strings.voiceSection, selection: $selection) {
            ForEach(GuidanceMode.allCases) { mode in
                Text(Strings.voiceModeShort(mode)).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier(id)
    }
}

struct RidePanel: View {
    static let collapsedHeight: CGFloat = 128

    @ObservedObject var model: RideModel
    @Binding var expanded: Bool
    let inSheet: Bool
    let onOverview: () -> Void
    let onEnd: () -> Void

    @State private var searching: RouteEditKind?
    @State private var confirmingEnd = false
    @State private var controlsHeight: CGFloat = 0
    @State private var height: CGFloat = 0
    @Environment(AppSettings.self) private var settings
    @Environment(PlacesStore.self) private var places: PlacesStore?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            summary
            if showsControls {
                ScrollView {
                    controls
                        .padding(.top, 16)
                        .padding(.bottom, inSheet ? 16 : 0)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { controlsHeight = $0 }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: inSheet ? .infinity : controlsHeight)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, inSheet ? 22 : 12)
        .padding(.bottom, inSheet ? 0 : 12)
        .frame(maxWidth: .infinity, maxHeight: inSheet ? .infinity : nil, alignment: .top)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .sheet(item: $searching) { kind in
            PlaceSearchSheet(title: kind.title, near: model.userCoordinate) { place in
                model.edit(kind.edit(place))
                expanded = false
            }
            .environment(settings)
            .environment(places)
        }
        .alert(Strings.endRideTitle, isPresented: $confirmingEnd) {
            Button(Strings.endRideConfirm, role: .destructive, action: onEnd)
            Button(Strings.keepRiding, role: .cancel) {}
        }
    }

    private var summary: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.remainingS.map { Format.duration(seconds: $0) } ?? "–")
                        .font(.system(size: 30, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Text(remainingSubtitle)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("ride.remaining")
                if let stop = model.nextStop, !model.arrived {
                    Label(Strings.nextStop(stop.title), systemImage: "mappin.circle.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("ride.nextStop")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: toggle)
            Button(action: toggle) {
                Image(systemName: expanded ? "chevron.down" : "chevron.up")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 48, height: 48)
                    .background(Theme.iconBackground, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(expanded ? Strings.hideRideOptions : Strings.showRideOptions)
            .accessibilityIdentifier("ride.panel.toggle")
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                tile(symbol: "plus.circle", title: Strings.addStopMidRide, id: "ride.edit.addStop") { searching = .addStop }
                    .disabled(!canEdit)
                tile(symbol: "mappin.and.ellipse", title: Strings.changeDestination, id: "ride.edit.changeDestination") {
                    searching = .changeDestination
                }
                .disabled(!canEdit)
                tile(symbol: "map", title: Strings.routeOverview, id: "ride.overview") {
                    expanded = false
                    onOverview()
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(Strings.voiceSection)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                VoiceModePicker(selection: voiceMode, id: "ride.voiceMode")
            }

            @Bindable var settings = settings
            HStack(spacing: 10) {
                Toggle(isOn: $settings.northUp) {
                    Label(Strings.northUp, systemImage: "location.north.line")
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .accessibilityIdentifier("ride.northUp")
                Toggle(isOn: $settings.threeD) {
                    Label(Strings.threeD, systemImage: "cube")
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .accessibilityIdentifier("ride.threeD")
            }
            .toggleStyle(.button)
            .buttonStyle(.bordered)
            .font(.system(size: 16, weight: .semibold))

            Button(role: .destructive) {
                if model.arrived {
                    onEnd()
                } else {
                    confirmingEnd = true
                }
            } label: {
                Text(Strings.endRideConfirm)
                    .font(.system(size: 18, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 40)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.danger)
            .accessibilityIdentifier("ride.end")
        }
    }

    private func tile(symbol: String, title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .semibold))
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
        }
        .buttonStyle(.bordered)
        .tint(Theme.ink)
        .accessibilityIdentifier(id)
    }

    private var showsControls: Bool {
        expanded || (inSheet && height > Self.collapsedHeight + 10)
    }

    private var canEdit: Bool { model.canEdit && model.editState != .planning }

    private var voiceMode: Binding<GuidanceMode> {
        Binding(get: { settings.guidanceMode }, set: { model.setVoiceMode($0) })
    }

    private func toggle() {
        withAnimation { expanded.toggle() }
    }

    private var remainingSubtitle: String {
        guard let meters = model.remainingM, let seconds = model.remainingS else { return " " }
        let arrival = Format.clockTime(Date().addingTimeInterval(seconds))
        return "\(Format.distance(meters: Int(meters.rounded()))), \(Strings.arrive(arrival))"
    }
}
