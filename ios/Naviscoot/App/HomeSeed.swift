#if DEBUG
import Foundation

@MainActor
enum HomeSeed {
    static let launchKey = "NaviscootSeedHome"
    static let parkedKey = "NaviscootSeedParked"

    static func applyIfRequested(places: PlacesStore, trips: TripStore, parked: ParkedScooterStore, defaults: UserDefaults = .standard) {
        if let spot = defaults.string(forKey: parkedKey).flatMap(RideOptions.parseCoordinate) {
            parked.record(spot, at: Date().addingTimeInterval(-600))
        } else if defaults.bool(forKey: launchKey) {
            parked.clear()
        }
        guard defaults.bool(forKey: launchKey) else { return }
        places.removeAll()
        places.setHome(Destination(title: "Utrechtseweg 1", subtitle: "Amersfoort", coordinate: Coordinate(lat: 52.1491, lon: 5.3738)))
        places.setWork(Destination(title: "Stationsplein 9", subtitle: "Amersfoort", coordinate: Coordinate(lat: 52.1532, lon: 5.3745)))
        places.addFavourite(Destination(title: "Koppelpoort", subtitle: "Amersfoort", coordinate: Coordinate(lat: 52.1593, lon: 5.3818)))
        places.recordRecent(Destination(title: "Lieve Vrouwestraat 33", subtitle: "Amersfoort", coordinate: Coordinate(lat: 52.1561, lon: 5.3878)))
        trips.removeAll()
        let now = Date()
        trips.add(dompleinDraft(startedAt: now.addingTimeInterval(-86400)))
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

    // About 3.6 km north then east with an 8 % drop: enough for per-trip stats, below the 20 % that teaches the range model.
    private static func dompleinDraft(startedAt: Date) -> TripDraft {
        var draft = TripDraft(startedAt: startedAt, destination: "Domplein")
        draft.recordScooter(ScooterTelemetry(batteryPercent: 72, rangeKm: 34, odometerKm: 1203.0, speedKmh: 0))
        var point = Coordinate(lat: 52.0700, lon: 5.0900)
        for step in 0 ..< 61 {
            let north = step < 30
            _ = draft.add(TrackFix(coordinate: point, time: startedAt.addingTimeInterval(Double(step) * 10), courseDegrees: north ? 0 : 90))
            point = north ? Coordinate(lat: point.lat + 0.0006, lon: point.lon) : Coordinate(lat: point.lat, lon: point.lon + 0.0008)
        }
        draft.recordScooter(ScooterTelemetry(batteryPercent: 64, rangeKm: 30, odometerKm: 1206.6, speedKmh: 0))
        return draft
    }
}
#endif
