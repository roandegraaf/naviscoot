import MapLibreSwiftUI
import SwiftUI

struct SearchView: View {
    @ObservedObject var model: SearchModel
    @ObservedObject var location: LocationService
    let onSelect: (Destination) -> Void

    @State private var camera = MapViewCamera.center(CLLocationCoordinate2D(latitude: 52.156, longitude: 5.387), zoom: 12)
    @State private var centeredOnUser = false
    @State private var resultsHeight: CGFloat = 0
    @FocusState private var fieldFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            RouteMapView(camera: $camera, origin: location.coordinate)

            VStack(spacing: 10) {
                searchField
                if !model.results.isEmpty || model.errorMessage != nil || showsNoResults {
                    resultsCard
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
        }
        .onChange(of: location.coordinate) { _, coordinate in
            guard !centeredOnUser, let coordinate else { return }
            centeredOnUser = true
            camera = .center(coordinate.clLocation, zoom: 13)
        }
    }

    private var showsNoResults: Bool {
        !model.isSearching && model.query.trimmingCharacters(in: .whitespaces).count >= 2 && model.results.isEmpty
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .accessibilityHidden(true)
            TextField(Strings.searchPlaceholder, text: $model.query)
                .font(.system(size: 20))
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($fieldFocused)
                .accessibilityIdentifier("search.field")
            if model.isSearching {
                ProgressView()
            } else if !model.query.isEmpty {
                Button {
                    model.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 60)
        .background(.white, in: Capsule())
        .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
    }

    private var resultsCard: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if let error = model.errorMessage {
                    Text(error)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.danger)
                        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                } else if model.results.isEmpty {
                    Text(Strings.noResults)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                }
                ForEach(model.results) { result in
                    row(result)
                    if result.id != model.results.last?.id {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { resultsHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: resultsHeight)
        .background(.white, in: RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 2)
    }

    private func row(_ result: SearchResult) -> some View {
        Button {
            fieldFocused = false
            Task {
                if let destination = await model.resolve(result) {
                    onSelect(destination)
                }
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: result.source == .place ? "building.2" : "mappin.and.ellipse")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 44, height: 44)
                    .background(Theme.iconBackground, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(subtitle(result))
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.muted)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                if model.resolvingId == result.id {
                    ProgressView()
                }
            }
            .frame(minHeight: 68)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("search.result")
    }

    private func subtitle(_ result: SearchResult) -> String {
        let kind = result.source == .place ? Strings.placeKind : Strings.addressKind
        return result.subtitle.isEmpty ? kind : "\(kind) · \(result.subtitle)"
    }
}
