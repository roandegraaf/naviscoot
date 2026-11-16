import SwiftUI

struct HomeSurface<Trips: View>: View {
    let places: PlacesStore
    let near: Coordinate?
    let onSelect: (Destination) -> Void
    let onSetSlot: (PlaceKind) -> Void
    let onEdit: () -> Void
    @ViewBuilder let trips: Trips

    @Environment(ParkedScooterStore.self) private var parkedStore
    @Environment(PlaceETAStore.self) private var etas

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let parked = parkedStore.parked {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    PlaceRow(systemImage: "scooter", title: Strings.scooterParkedTitle, subtitle: parked.subtitle(now: context.date), id: "home.parkedScooter") {
                        parkedStore.openWalkingDirections()
                    }
                    .accessibilityHint(Strings.tr("scooter.parked.accessibility"))
                }
                Divider()
            }
            if places.hasSavedPlaces {
                DrawerSectionHeader(title: Strings.savedPlaces, action: Strings.editPlaces, id: "home.edit", perform: onEdit)
            }
            HStack(spacing: 10) {
                slot(.home, places.home)
                slot(.work, places.work)
            }
            .padding(.vertical, 10)
            ForEach(Array(places.favourites.enumerated()), id: \.element.id) { index, place in
                Divider()
                PlaceRow(systemImage: place.systemImage, title: place.displayName, subtitle: reach(place, then: place.rowSubtitle), id: "home.favourite.\(index)") {
                    onSelect(place.destination)
                }
            }
            trips
            if !places.recents.isEmpty {
                DrawerSectionHeader(title: Strings.recents, action: Strings.clearRecents, accessibility: Strings.clearRecentsAccessibility, id: "home.clearRecents") {
                    places.clearRecents()
                }
                ForEach(Array(places.recents.enumerated()), id: \.element.id) { index, place in
                    if index > 0 { Divider() }
                    PlaceRow(systemImage: place.systemImage, title: place.displayName, subtitle: place.rowSubtitle, id: "home.recent.\(index)") {
                        onSelect(place.destination)
                    }
                }
            }
        }
    }

    private func reach(_ place: Place, then detail: String) -> String {
        guard let near else { return detail }
        let reach = etas.seconds(to: place.coordinate, from: near).map { Format.duration(seconds: $0) }
            ?? Format.approximateDistance(meters: Geo.distanceM(near, place.coordinate))
        return detail.isEmpty ? reach : "\(reach) · \(detail)"
    }

    private func slot(_ kind: PlaceKind, _ place: Place?) -> some View {
        Button {
            if let place {
                onSelect(place.destination)
            } else {
                onSetSlot(kind)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: kind == .home ? "house.fill" : "briefcase.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(place == nil ? Strings.setSlot(kind) : Strings.slotName(kind))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(place == nil ? Theme.verifiedText : Theme.ink)
                    if let place {
                        Text(reach(place, then: place.displayName))
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.muted)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(Theme.iconBackground, in: RoundedRectangle(cornerRadius: 16))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(kind == .home ? "home.home" : "home.work")
    }
}
