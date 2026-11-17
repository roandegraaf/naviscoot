import Foundation
import Observation

@MainActor
@Observable
final class PlaceETAStore {
    typealias Fetch = @MainActor (_ origin: Coordinate, _ destination: Coordinate) async throws -> TimeInterval

    static let maxPlaces = 5
    static let cacheLifetime: TimeInterval = 5 * 60
    static let skipWithinM: Double = 300
    nonisolated static let originCellM: Double = 200
    static let refreshInterval: Duration = .seconds(60)

    struct OriginCell: Hashable {
        let row: Int
        let column: Int

        init(_ origin: Coordinate) {
            let metresPerDegree = 111_320.0
            row = Int((origin.lat * metresPerDegree / PlaceETAStore.originCellM).rounded())
            let cellLat = Double(row) * PlaceETAStore.originCellM / metresPerDegree
            let metresPerLonDegree = metresPerDegree * cos(cellLat * .pi / 180)
            column = Int((origin.lon * metresPerLonDegree / PlaceETAStore.originCellM).rounded())
        }
    }

    private struct Key: Hashable {
        let cell: OriginCell
        let destination: Coordinate
    }

    private struct Entry {
        let seconds: TimeInterval?
        let fetchedAt: Date
    }

    @ObservationIgnored private let fetch: Fetch
    @ObservationIgnored private let now: () -> Date
    private var cache: [Key: Entry] = [:]
    @ObservationIgnored private var inFlight: Set<Key> = []

    init(fetch: @escaping Fetch, now: @escaping () -> Date = Date.init) {
        self.fetch = fetch
        self.now = now
    }

    func seconds(to destination: Coordinate, from origin: Coordinate) -> TimeInterval? {
        guard let entry = cache[Key(cell: OriginCell(origin), destination: destination)], isFresh(entry) else { return nil }
        return entry.seconds
    }

    func refresh(from origin: Coordinate, to destinations: [Coordinate]) async {
        let cell = OriginCell(origin)
        for destination in destinations.prefix(Self.maxPlaces) {
            guard !Task.isCancelled else { return }
            guard Geo.distanceM(origin, destination) >= Self.skipWithinM else { continue }
            let key = Key(cell: cell, destination: destination)
            if let entry = cache[key], isFresh(entry) { continue }
            guard inFlight.insert(key).inserted else { continue }
            let seconds = try? await fetch(origin, destination)
            inFlight.remove(key)
            guard !Task.isCancelled else { return }
            cache[key] = Entry(seconds: seconds, fetchedAt: now())
        }
    }

    func keepFresh(from origin: Coordinate, to destinations: [Coordinate]) async {
        while !Task.isCancelled {
            await refresh(from: origin, to: destinations)
            try? await Task.sleep(for: Self.refreshInterval)
        }
    }

    private func isFresh(_ entry: Entry) -> Bool {
        now().timeIntervalSince(entry.fetchedAt) < Self.cacheLifetime
    }
}

extension PlaceETAStore {
    static func live(client: NaviscootClient?, settings: AppSettings) -> PlaceETAStore {
        #if DEBUG
        if let simulated = UserDefaults.standard.string(forKey: simulatedLaunchKey) {
            return PlaceETAStore { _, _ in
                guard let seconds = TimeInterval(simulated) else { throw URLError(.cannotConnectToHost) }
                return seconds
            }
        }
        #endif
        return PlaceETAStore { origin, destination in
            guard let client else { throw URLError(.userAuthenticationRequired) }
            return try await client.route(
                from: origin,
                to: destination,
                stops: [],
                avoid: settings.routeAvoid,
                verifiedOnly: settings.verifiedOnlyByDefault,
                language: settings.language
            ).durationS
        }
    }

    #if DEBUG
    static let simulatedLaunchKey = "NaviscootSimETA"
    #endif
}

extension PlacesStore {
    var etaDestinations: [Coordinate] {
        ([home, work].compactMap { $0 } + favourites.prefix(3)).map(\.coordinate)
    }
}
