import SwiftUI

struct PlacesEditSheet: View {
    let places: PlacesStore

    @Environment(\.dismiss) private var dismiss
    @State private var renaming: Place?
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                if !places.hasSavedPlaces {
                    Text(Strings.nothingSaved)
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.muted)
                }
                let slots = [places.home, places.work].compactMap { $0 }
                if !slots.isEmpty {
                    Section {
                        ForEach(slots) { place in
                            row(place, id: "places.\(place.kind.rawValue)", title: Strings.slotName(place.kind), subtitle: place.address, renamable: false)
                        }
                    }
                }
                if !places.favourites.isEmpty {
                    Section(Strings.favourites) {
                        ForEach(Array(places.favourites.enumerated()), id: \.element.id) { index, place in
                            row(place, id: "places.favourite.\(index)", title: place.displayName, subtitle: place.rowSubtitle, renamable: true)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(Strings.editPlacesTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.done) { dismiss() }
                        .font(.system(size: 18, weight: .semibold))
                        .accessibilityIdentifier("places.done")
                }
            }
            .alert(Strings.renameTitle, isPresented: isRenaming, presenting: renaming) { place in
                TextField(place.displayName, text: $newName)
                    .accessibilityIdentifier("places.rename.field")
                Button(Strings.save) { places.rename(place, to: newName) }
                    .accessibilityIdentifier("places.rename.save")
                Button(Strings.cancel, role: .cancel) {}
            }
        }
    }

    private var isRenaming: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    private func row(_ place: Place, id: String, title: String, subtitle: String, renamable: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: place.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.muted)
            }
            .lineLimit(1)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(id)
            Spacer(minLength: 0)
            if renamable {
                iconButton("pencil", label: Strings.rename, id: "\(id).rename") {
                    newName = place.name ?? ""
                    renaming = place
                }
            }
            iconButton("trash", label: Strings.removePlace, id: "\(id).remove") {
                places.remove(place)
            }
        }
        .frame(minHeight: 56)
    }

    private func iconButton(_ systemImage: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(systemImage == "trash" ? Theme.dangerText : Theme.ink)
                .frame(width: 44, height: 44)
                .background(Theme.iconBackground, in: Circle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}
