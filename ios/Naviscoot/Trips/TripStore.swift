import Foundation
import Observation
import SwiftData

@Model
final class RecordedTrip {
    var startedAt: Date
    var destination: String
    var stops: [String]
    var distanceM: Double
    var durationS: Double
    @Attribute(.externalStorage) var trackData: Data
    var scooterStartBattery: Int?
    var scooterEndBattery: Int?
    var scooterStartOdometerKm: Double?
    var scooterEndOdometerKm: Double?

    init(_ draft: TripDraft) {
        startedAt = draft.startedAt
        destination = draft.destination
        stops = draft.stops
        distanceM = draft.distanceM
        durationS = draft.durationS
        trackData = TripTrackCoding.encode(draft.track)
        scooterStartBattery = draft.scooterStart?.batteryPercent
        scooterEndBattery = draft.scooterEnd?.batteryPercent
        scooterStartOdometerKm = draft.scooterStart?.odometerKm
        scooterEndOdometerKm = draft.scooterEnd?.odometerKm
    }

    var scooterSample: ScooterTripSample? {
        guard let scooterStartBattery, let scooterEndBattery, let scooterStartOdometerKm, let scooterEndOdometerKm else { return nil }
        return ScooterTripSample.between(
            ScooterReading(batteryPercent: scooterStartBattery, odometerKm: scooterStartOdometerKm),
            ScooterReading(batteryPercent: scooterEndBattery, odometerKm: scooterEndOdometerKm)
        )
    }
}

struct TripSummary: Identifiable, Hashable {
    let id: PersistentIdentifier
    let startedAt: Date
    let destination: String
    let stops: [String]
    let distanceM: Double
    let durationS: Double
    var scooterSample: ScooterTripSample?

    var averageKmh: Double { TripMath.averageKmh(distanceM: distanceM, durationS: durationS) }
}

struct TripTotals: Equatable {
    let count: Int
    let distanceM: Double
    let durationS: Double

    var averageKmh: Double { TripMath.averageKmh(distanceM: distanceM, durationS: durationS) }
}

enum TripTrackCoding {
    static func encode(_ track: [[Coordinate]]) -> Data {
        (try? JSONEncoder().encode(track.map { $0.map { [$0.lat, $0.lon] } })) ?? Data()
    }

    static func decode(_ data: Data) -> [[Coordinate]] {
        guard let segments = try? JSONDecoder().decode([[[Double]]].self, from: data) else { return [] }
        return segments.map { $0.compactMap { $0.count == 2 ? Coordinate(lat: $0[0], lon: $0[1]) : nil } }
    }
}

@MainActor
@Observable
final class TripStore {
    static let resetLaunchKey = "NaviscootResetTrips"

    static let defaultURL: URL = {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "trips.store")
    }()

    static let shared: TripStore = {
        let onDisk = (try? TripStore.container(url: defaultURL)) ?? (try! TripStore.container(url: nil))
        let store = TripStore(container: onDisk)
        if UserDefaults.standard.bool(forKey: resetLaunchKey) {
            store.removeAll()
        }
        return store
    }()

    private(set) var trips: [TripSummary] = []
    private(set) var totals = TripTotals(count: 0, distanceM: 0, durationS: 0)
    private(set) var consumption = ConsumptionModel(samples: [])

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private var models: [RecordedTrip] = []

    init(container: ModelContainer) {
        context = ModelContext(container)
        context.autosaveEnabled = false
        reload()
    }

    static func container(url: URL?) throws -> ModelContainer {
        let configuration = url.map { ModelConfiguration(url: $0) } ?? ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: RecordedTrip.self, configurations: configuration)
    }

    @discardableResult
    func add(_ draft: TripDraft) -> Bool {
        var closed = draft
        closed.close()
        guard closed.isWorthKeeping else { return false }
        context.insert(RecordedTrip(closed))
        commit()
        return true
    }

    func delete(_ trip: TripSummary) {
        guard let model = models.first(where: { $0.persistentModelID == trip.id }) else { return }
        context.delete(model)
        commit()
    }

    func removeAll() {
        for model in models {
            context.delete(model)
        }
        commit()
    }

    func track(for trip: TripSummary) -> [[Coordinate]] {
        guard let model = models.first(where: { $0.persistentModelID == trip.id }) else { return [] }
        return TripTrackCoding.decode(model.trackData)
    }

    // Saved at once: a killed app (or a UI test's terminate) would otherwise lose the change before autosave runs.
    private func commit() {
        try? context.save()
        reload()
    }

    private func reload() {
        models = (try? context.fetch(FetchDescriptor<RecordedTrip>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)]))) ?? []
        trips = models.map { model in
            TripSummary(
                id: model.persistentModelID,
                startedAt: model.startedAt,
                destination: model.destination,
                stops: model.stops,
                distanceM: model.distanceM,
                durationS: model.durationS,
                scooterSample: model.scooterSample
            )
        }
        consumption = ConsumptionModel(samples: trips.compactMap(\.scooterSample))
        totals = TripTotals(
            count: trips.count,
            distanceM: trips.reduce(0) { $0 + $1.distanceM },
            durationS: trips.reduce(0) { $0 + $1.durationS }
        )
    }
}
