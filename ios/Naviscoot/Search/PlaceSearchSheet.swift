import SwiftUI

struct PlaceSearchSheet: View {
    let title: String
    let near: Coordinate?
    var onCurrentLocation: (() -> Void)?
    let onSelect: (Destination) -> Void

    @StateObject private var model = SearchModel()
    @FocusState private var fieldFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(PlacesStore.self) private var places: PlacesStore?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    field
                }
                if let onCurrentLocation, model.query.isEmpty {
                    Button {
                        onCurrentLocation()
                        dismiss()
                    } label: {
                        Label(Strings.yourLocation, systemImage: "location.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.verifiedText)
                            .frame(minHeight: 52)
                    }
                    .accessibilityIdentifier("placeSearch.currentLocation")
                }
                if model.query.isEmpty, !savedPlaces.isEmpty {
                    Section {
                        ForEach(Array(savedPlaces.enumerated()), id: \.element.id) { index, place in
                            PlaceRow(
                                systemImage: place.systemImage,
                                title: place.kind == .home || place.kind == .work ? Strings.slotName(place.kind) : place.displayName,
                                subtitle: place.kind == .home || place.kind == .work ? place.address : place.rowSubtitle,
                                id: "placeSearch.saved.\(index)"
                            ) {
                                onSelect(place.destination)
                                dismiss()
                            }
                        }
                    }
                }
                if let error = model.errorMessage {
                    Text(error)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.dangerText)
                } else if showsNoResults {
                    Text(Strings.noResults)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                }
                ForEach(model.results) { result in
                    SearchResultRow(result: result, isResolving: model.resolvingId == result.id) {
                        fieldFocused = false
                        Task {
                            if let place = await model.resolve(result) {
                                onSelect(place)
                                dismiss()
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.cancel) { dismiss() }
                        .font(.system(size: 18, weight: .semibold))
                        .accessibilityIdentifier("placeSearch.cancel")
                }
            }
        }
        .onAppear {
            let near = near
            model.origin = { near }
            fieldFocused = true
        }
    }

    private var savedPlaces: [Place] {
        guard let places else { return [] }
        return [places.home, places.work].compactMap { $0 } + places.favourites + places.recents.prefix(Self.recentLimit)
    }

    private static let recentLimit = 5

    private var showsNoResults: Bool {
        !model.isSearching && model.query.trimmingCharacters(in: .whitespaces).count >= 2 && model.results.isEmpty
    }

    private var field: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .accessibilityHidden(true)
            TextField(Strings.searchPlaceholder, text: $model.query)
                .font(.system(size: 20))
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($fieldFocused)
                .accessibilityIdentifier("placeSearch.field")
            if model.isSearching {
                ProgressView()
            }
        }
        .frame(minHeight: 52)
    }
}
