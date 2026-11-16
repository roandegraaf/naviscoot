import CoreLocation
import Foundation
import Observation
import SwiftData

enum PlaceKind: String, CaseIterable, Identifiable {
    case recent
    case favourite
    case home
    case work

    var id: String { rawValue }
}

@Model
final class SavedPlace {
    var kindRaw: String
    var title: String
    var subtitle: String
    var name: String?
    var latitude: Double
    var longitude: Double
    var sequence: Int

    init(kind: PlaceKind, destination: Destination, sequence: Int) {
        kindRaw = kind.rawValue
        title = destination.title
        subtitle = destination.subtitle
        latitude = destination.coordinate.lat
        longitude = destination.coordinate.lon
        self.sequence = sequence
    }

    var kind: PlaceKind? { PlaceKind(rawValue: kindRaw) }
    var coordinate: Coordinate { Coordinate(lat: latitude, lon: longitude) }
}

struct Place: Identifiable, Equatable {
    let id: PersistentIdentifier
    let kind: PlaceKind
    let title: String
    let subtitle: String
    let name: String?
    let coordinate: Coordinate

    var displayName: String { name ?? title }

    var address: String { subtitle.isEmpty ? title : "\(title), \(subtitle)" }

    var destination: Destination {
        if let name {
            return Destination(title: name, subtitle: address, coordinate: coordinate)
        }
        return Destination(title: title, subtitle: subtitle, coordinate: coordinate)
    }
}

@MainActor
@Observable
final class PlacesStore {
    static let recentLimit = 20
    static let sameSpotMeters: CLLocationDistance = 30
    static let resetLaunchKey = "NaviscootResetPlaces"

    static let defaultURL: URL = {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "places.store")
    }()

    static let shared: PlacesStore = {
        let onDisk = (try? PlacesStore.container(url: defaultURL)) ?? (try! PlacesStore.container(url: nil))
        let store = PlacesStore(container: onDisk)
        if UserDefaults.standard.bool(forKey: resetLaunchKey) {
            store.removeAll()
        }
        return store
    }()

    private(set) var home: Place?
    private(set) var work: Place?
    private(set) var favourites: [Place] = []
    private(set) var recents: [Place] = []

    var hasSavedPlaces: Bool { home != nil || work != nil || !favourites.isEmpty }

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private var models: [SavedPlace] = []

    init(container: ModelContainer) {
        context = ModelContext(container)
        context.autosaveEnabled = false
        reload()
    }

    static func container(url: URL?) throws -> ModelContainer {
        let configuration = url.map { ModelConfiguration(url: $0) } ?? ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: SavedPlace.self, configurations: configuration)
    }

    func recordRecent(_ destination: Destination) {
        for model in models(of: .recent) where Self.isSameSpot(model.coordinate, destination.coordinate) {
            context.delete(model)
        }
        context.insert(SavedPlace(kind: .recent, destination: destination, sequence: nextSequence))
        commit()
        for model in models(of: .recent).sorted(by: { $0.sequence > $1.sequence }).dropFirst(Self.recentLimit) {
            context.delete(model)
        }
        commit()
    }

    func clearRecents() {
        for model in models(of: .recent) {
            context.delete(model)
        }
        commit()
    }

    func addFavourite(_ destination: Destination) {
        guard !models(of: .favourite).contains(where: { Self.isSameSpot($0.coordinate, destination.coordinate) }) else { return }
        context.insert(SavedPlace(kind: .favourite, destination: destination, sequence: nextSequence))
        commit()
    }

    func setHome(_ destination: Destination) {
        replaceSlot(.home, with: destination)
    }

    func setWork(_ destination: Destination) {
        replaceSlot(.work, with: destination)
    }

    func rename(_ place: Place, to name: String) {
        guard let model = model(for: place) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        model.name = trimmed.isEmpty || trimmed == model.title ? nil : trimmed
        commit()
    }

    func remove(_ place: Place) {
        guard let model = model(for: place) else { return }
        context.delete(model)
        commit()
    }

    func removeAll() {
        for model in models {
            context.delete(model)
        }
        commit()
    }

    func savedKinds(at coordinate: Coordinate) -> Set<PlaceKind> {
        Set(models.compactMap { model in
            guard let kind = model.kind, kind != .recent, Self.isSameSpot(model.coordinate, coordinate) else { return nil }
            return kind
        })
    }

    static func isSameSpot(_ a: Coordinate, _ b: Coordinate) -> Bool {
        CLLocation(latitude: a.lat, longitude: a.lon).distance(from: CLLocation(latitude: b.lat, longitude: b.lon)) <= sameSpotMeters
    }

    private func replaceSlot(_ kind: PlaceKind, with destination: Destination) {
        for model in models(of: kind) {
            context.delete(model)
        }
        context.insert(SavedPlace(kind: kind, destination: destination, sequence: nextSequence))
        commit()
    }

    private var nextSequence: Int { (models.map(\.sequence).max() ?? 0) + 1 }

    private func models(of kind: PlaceKind) -> [SavedPlace] {
        models.filter { $0.kind == kind }
    }

    private func model(for place: Place) -> SavedPlace? {
        models.first { $0.persistentModelID == place.id }
    }

    // Saved at once: a killed app (or a UI test's terminate) would otherwise lose the change before autosave runs.
    private func commit() {
        try? context.save()
        reload()
    }

    private func reload() {
        models = (try? context.fetch(FetchDescriptor<SavedPlace>(sortBy: [SortDescriptor(\.sequence)]))) ?? []
        let places = models.compactMap(Self.place)
        home = places.filter { $0.kind == .home }.last
        work = places.filter { $0.kind == .work }.last
        favourites = places.filter { $0.kind == .favourite }
        recents = places.filter { $0.kind == .recent }.reversed()
    }

    private static func place(_ model: SavedPlace) -> Place? {
        guard let kind = model.kind else { return nil }
        return Place(
            id: model.persistentModelID,
            kind: kind,
            title: model.title,
            subtitle: model.subtitle,
            name: model.name,
            coordinate: model.coordinate
        )
    }
}
