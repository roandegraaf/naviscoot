import SwiftUI

extension PresentationDetent {
    static let drawerCollapsed = PresentationDetent.height(92)
}

struct HomeDrawer: View {
    @ObservedObject var model: SearchModel
    let near: Coordinate?
    let inSheet: Bool
    @Binding var detent: PresentationDetent
    @Binding var showsLayers: Bool
    @Binding var showsScooter: Bool
    let onSelect: (Destination) -> Void

    @Environment(AppSettings.self) private var settings
    @Environment(PlacesStore.self) private var places
    @Environment(PlaceETAStore.self) private var etas
    @Environment(TripStore.self) private var trips
    @Environment(ScooterConnection.self) private var scooter
    @State private var showsSettings = false
    @State private var showsPlacesEditor = false
    @State private var settingSlot: PlaceKind?
    @State private var tripSheet: TripSheet?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchRow
                .padding(.horizontal, 16)
                .padding(.top, inSheet ? 18 : 12)
                .padding(.bottom, 10)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    content
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.immediately)
            .ignoresSafeArea(.keyboard)
            .accessibilityIdentifier("home.drawer")
        }
        .sheet(isPresented: $showsSettings) {
            SettingsView(settings: settings)
        }
        .sheet(item: $tripSheet) { sheet in
            TripHistoryView(opening: sheet.trip)
        }
        .sheet(isPresented: $showsPlacesEditor) {
            PlacesEditSheet(places: places)
        }
        .sheet(item: $settingSlot) { kind in
            PlaceSearchSheet(title: Strings.setSlot(kind), near: near) { place in
                if kind == .work {
                    places.setWork(place)
                } else {
                    places.setHome(place)
                }
            }
        }
        .sheet(isPresented: $showsLayers) {
            MapStyleSheet()
        }
        .sheet(isPresented: $showsScooter) {
            NavigationStack {
                ScooterScreen(settings: settings)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(Strings.done) { showsScooter = false }
                                .accessibilityIdentifier("scooter.done")
                        }
                    }
            }
        }
        .task(id: etaRefresh) {
            guard let etaRefresh else { return }
            await etas.keepFresh(from: etaRefresh.origin, to: etaRefresh.destinations)
        }
        .onChange(of: fieldFocused) { _, focused in
            if focused, inSheet { detent = .large }
        }
        .onChange(of: detent) { _, newDetent in
            if newDetent != .large { fieldFocused = false }
        }
        .onChange(of: model.pin == nil) { _, cleared in
            if !cleared, inSheet, detent == .drawerCollapsed { detent = .medium }
        }
    }

    private var searching: Bool { fieldFocused || !model.query.isEmpty }

    static func wantsETA(detent: PresentationDetent, showsPlaces: Bool) -> Bool {
        showsPlaces && detent != .drawerCollapsed
    }

    private var etaRefresh: ETARefresh? {
        guard Self.wantsETA(detent: detent, showsPlaces: model.query.isEmpty), let near else { return nil }
        return ETARefresh(origin: near, destinations: places.etaDestinations)
    }

    @ViewBuilder
    private var content: some View {
        if !inSheet, !searching, let glance = ScooterGlance(scooter) {
            ScooterStrip(glance: glance, floating: false) {
                fieldFocused = false
                showsScooter = true
            }
        }
        if let pin = model.pin {
            pinCard(pin)
        }
        if model.query.isEmpty {
            HomeSurface(
                places: places,
                near: near,
                onSelect: choose,
                onSetSlot: { kind in
                    fieldFocused = false
                    settingSlot = kind
                },
                onEdit: {
                    fieldFocused = false
                    showsPlacesEditor = true
                },
                trips: {
                    if !trips.trips.isEmpty {
                        recentTrips
                    }
                }
            )
        } else if !model.results.isEmpty || model.errorMessage != nil || showsNoResults {
            results
        }
    }

    private var showsNoResults: Bool {
        !model.isSearching && model.query.trimmingCharacters(in: .whitespaces).count >= 2 && model.results.isEmpty
    }

    private func closeSearch() {
        model.query = ""
        fieldFocused = false
        if inSheet { detent = .medium }
    }

    private func choose(_ destination: Destination) {
        fieldFocused = false
        model.clearPin()
        onSelect(destination)
    }

    private var searchRow: some View {
        HStack(spacing: 10) {
            searchField
            Button {
                fieldFocused = false
                showsSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 48, height: 48)
                    .background(Theme.iconBackground, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Strings.openSettings)
            .accessibilityIdentifier("search.settings")
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            if searching {
                Button(action: closeSearch) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 40, height: 48)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Strings.closeSearch)
                .accessibilityIdentifier("search.close")
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 40, height: 48)
                    .accessibilityHidden(true)
            }
            TextField(Strings.searchPlaceholder, text: $model.query)
                .font(.system(size: 19))
                .foregroundStyle(Theme.ink)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($fieldFocused)
                .accessibilityIdentifier("search.field")
            if model.isSearching {
                ProgressView()
                    .padding(.trailing, 12)
            } else if !model.query.isEmpty {
                Button {
                    model.query = ""
                    fieldFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 44, height: 48)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Strings.clear)
                .accessibilityIdentifier("search.clear")
            }
        }
        .padding(.leading, 4)
        .frame(height: 48)
        .background(Theme.iconBackground, in: RoundedRectangle(cornerRadius: 14))
    }

    private var results: some View {
        LazyVStack(spacing: 0) {
            if let error = model.errorMessage {
                Text(error)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.dangerText)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            } else if model.results.isEmpty {
                Text(Strings.noResults)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            }
            ForEach(model.results) { result in
                SearchResultRow(result: result, isResolving: model.resolvingId == result.id) {
                    fieldFocused = false
                    Task {
                        if let destination = await model.resolve(result) {
                            choose(destination)
                        }
                    }
                }
                if result.id != model.results.last?.id {
                    Divider()
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("search.results")
    }

    private var recentTrips: some View {
        VStack(alignment: .leading, spacing: 0) {
            DrawerSectionHeader(title: Strings.recentTrips, action: Strings.seeAll, accessibility: Strings.seeAllTrips, id: "home.trips.all") {
                fieldFocused = false
                tripSheet = TripSheet(trip: nil)
            }
            ForEach(Array(trips.trips.prefix(2).enumerated()), id: \.element.id) { index, trip in
                if index > 0 { Divider() }
                PlaceRow(systemImage: "flag.checkered", title: trip.destination, subtitle: Self.tripSubtitle(trip), id: "home.trip.\(index)") {
                    fieldFocused = false
                    tripSheet = TripSheet(trip: trip)
                }
            }
        }
    }

    private static func tripSubtitle(_ trip: TripSummary) -> String {
        [Format.dayTime(trip.startedAt), Format.distance(meters: Int(trip.distanceM.rounded()))].joined(separator: " · ")
    }

    private func pinCard(_ pin: SearchModel.DroppedPin) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 44, height: 44)
                    .background(Theme.iconBackground, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pin.destination?.title ?? Strings.lookingUpAddress)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .accessibilityIdentifier("search.pin")
                        .accessibilityValue(Text(verbatim: "\(pin.coordinate.lat),\(pin.coordinate.lon)"))
                    if let subtitle = pin.destination?.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.muted)
                            .accessibilityIdentifier("search.pin.subtitle")
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                if pin.destination == nil {
                    ProgressView()
                }
                Button {
                    model.clearPin()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 44, height: 44)
                        .background(Theme.iconBackground, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Strings.removePin)
                .accessibilityIdentifier("search.pin.remove")
            }
            Button {
                if let destination = pin.destination { choose(destination) }
            } label: {
                Text(Strings.routeHere)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(pin.destination == nil ? Theme.muted : Theme.verified, in: Capsule())
            }
            .disabled(pin.destination == nil)
            .accessibilityIdentifier("search.pin.route")
        }
        .padding(.vertical, 8)
    }
}

private struct ETARefresh: Hashable {
    let origin: Coordinate
    let destinations: [Coordinate]

    static func == (lhs: ETARefresh, rhs: ETARefresh) -> Bool {
        PlaceETAStore.OriginCell(lhs.origin) == PlaceETAStore.OriginCell(rhs.origin) && lhs.destinations == rhs.destinations
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(PlaceETAStore.OriginCell(origin))
        hasher.combine(destinations)
    }
}

private struct TripSheet: Identifiable {
    let trip: TripSummary?

    var id: TripSummary.ID? { trip?.id }
}

struct DrawerSectionHeader: View {
    let title: String
    let action: String
    var accessibility: String?
    let id: String
    let perform: () -> Void

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.muted)
                .textCase(.uppercase)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button(action: perform) {
                Text(action)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.verifiedText)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibility ?? action)
            .accessibilityIdentifier(id)
        }
        .padding(.top, 6)
    }
}
