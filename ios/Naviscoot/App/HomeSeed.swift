#if DEBUG
import Foundation

@MainActor
enum HomeSeed {
    static let launchKey = "NaviscootSeedHome"

    static func applyIfRequested(places: PlacesStore, trips: TripStore, defaults: UserDefaults = .standard) {
        guard defaults.bool(forKey: launchKey) else { return }
        places.removeAll()
        places.setHome(Destination(title: "Utrechtseweg 1", subtitle: "Amersfoort", coordinate: Coordinate(lat: 52.1491, lon: 5.3738)))
        places.setWork(Destination(title: "Stationsplein 9", subtitle: "Amersfoort", coordinate: Coordinate(lat: 52.1532, lon: 5.3745)))
        places.addFavourite(Destination(title: "Koppelpoort", subtitle: "Amersfoort", coordinate: Coordinate(lat: 52.1593, lon: 5.3818)))
        places.recordRecent(Destination(title: "Lieve Vrouwestraat 33", subtitle: "Amersfoort", coordinate: Coordinate(lat: 52.1561, lon: 5.3878)))
        trips.removeAll()
        let now = Date()
        trips.add(draft(to: "Domplein", startedAt: now.addingTimeInterval(-86400), from: Coordinate(lat: 52.0850, lon: 5.1100)))
        trips.add(draft(to: "Koppelpoort", startedAt: now.addingTimeInterval(-3600), from: Coordinate(lat: 52.1500, lon: 5.3700)))
    }

    private static func draft(to destination: String, startedAt: Date, from start: Coordinate) -> TripDraft {
        var draft = TripDraft(startedAt: startedAt, destination: destination)
        for step in 0 ..< 40 {
            let fix = TrackFix(
                coordinate: Coordinate(lat: start.lat + Double(step) * 0.0003, lon: start.lon + Double(step) * 0.0002),
                time: startedAt.addingTimeInterval(Double(step) * 5),
                courseDegrees: 25
            )
            _ = draft.add(fix)
        }
        return draft
    }
}
#endif
