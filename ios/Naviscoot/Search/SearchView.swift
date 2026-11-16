import MapLibreSwiftUI
import SwiftUI

struct SearchView: View {
    @ObservedObject var model: SearchModel
    @ObservedObject var location: LocationService
    var drawerEnabled = true
    let resumeOffer: ResumeOfferAlert
    let onSelect: (Destination) -> Void

    @Environment(AppSettings.self) private var settings
    @Environment(PlacesStore.self) private var places
    @Environment(TripStore.self) private var trips
    @Environment(ParkedScooterStore.self) private var parked
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var screenSize = CGSize(width: 400, height: 800)
    @State private var camera = MapViewCamera.center(CLLocationCoordinate2D(latitude: 52.156, longitude: 5.387), zoom: 12)
    @State private var centeredOnUser = false
    @State private var detent: PresentationDetent = .medium
    @State private var showsLayers = false
    @State private var leaving = false

    private var landscape: Bool { verticalSizeClass == .compact }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RouteMapView(camera: $camera, destination: model.pin?.coordinate, user: location.coordinate)
                .onLongPressMapGesture { context in
                    guard context.state == .began else { return }
                    model.dropPin(at: Coordinate(context.coordinate))
                }

            if landscape {
                landscapePanel
            }
        }
        .overlay(alignment: .topTrailing) {
            mapControls
                .padding(.trailing, 12)
                .padding(.top, 8)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { screenSize = $0 }
        .sheet(isPresented: drawerPresented) {
            drawer(inSheet: true)
                .environment(settings)
                .environment(places)
                .environment(trips)
                .environment(parked)
                .presentationDetents([.drawerCollapsed, .medium, .large], selection: $detent)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .presentationContentInteraction(.resizes)
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled()
                .drawerBackground()
        }
        .onChange(of: location.coordinate, initial: true) { _, coordinate in
            guard !centeredOnUser, let coordinate else { return }
            centeredOnUser = true
            camera = .center(coordinate.clLocation, zoom: 13)
        }
    }

    private var drawerPresented: Binding<Bool> {
        Binding(get: { drawerEnabled && !landscape && !leaving }, set: { _ in })
    }

    private func drawer(inSheet: Bool) -> some View {
        HomeDrawer(
            model: model,
            near: location.coordinate,
            inSheet: inSheet,
            detent: inSheet ? $detent : .constant(.large),
            showsLayers: $showsLayers,
            onSelect: choose
        )
        .modifier(resumeOffer)
    }

    private func choose(_ destination: Destination) {
        leaving = true
        onSelect(destination)
    }

    private var landscapePanel: some View {
        drawer(inSheet: false)
            .frame(width: min(420, screenSize.width * 0.5))
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.18), radius: 10, y: 2)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
    }

    private var mapControls: some View {
        VStack(spacing: 0) {
            mapButton(symbol: "location.fill", label: Strings.showMyLocation, id: "home.locate") {
                guard let coordinate = location.coordinate else { return }
                withAnimation { camera = .center(coordinate.clLocation, zoom: 15) }
            }
            .accessibilityValue(Text(verbatim: cameraCenter))
            Divider()
                .frame(width: 30)
            mapButton(symbol: "map.fill", label: Strings.mapStyleSection, id: "home.layers") {
                showsLayers = true
            }
            .accessibilityValue(Text(verbatim: settings.mapStyle.rawValue))
        }
        .mapControlBackground()
    }

    private func mapButton(symbol: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 50, height: 50)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    private var cameraCenter: String {
        guard case let .centered(center, zoom, _, _, _) = camera.state else { return "" }
        return String(format: "%.5f,%.5f,%.2f", locale: Locale(identifier: "en_US_POSIX"), center.latitude, center.longitude, zoom)
    }
}

private extension View {
    @ViewBuilder
    func drawerBackground() -> some View {
        if #available(iOS 26, *) {
            self
        } else {
            presentationBackground(.regularMaterial)
        }
    }

    @ViewBuilder
    func mapControlBackground() -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
        } else {
            background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
        }
    }
}
