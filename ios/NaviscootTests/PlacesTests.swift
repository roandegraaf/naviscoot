@testable import Naviscoot
import XCTest

@MainActor
final class PlacesTests: XCTestCase {
    private func store(url: URL? = nil) throws -> PlacesStore {
        PlacesStore(container: try PlacesStore.container(url: url))
    }

    private func place(_ title: String, lat: Double, lon: Double = 5.4, subtitle: String = "Amersfoort") -> Destination {
        Destination(title: title, subtitle: subtitle, coordinate: Coordinate(lat: lat, lon: lon))
    }

    func testRecentsAreNewestFirstAndDeduplicatedByLocation() throws {
        let places = try store()
        places.recordRecent(place("Stationsplein 1", lat: 52.1533))
        places.recordRecent(place("Kapelweg 170A", lat: 52.1375))
        places.recordRecent(place("Station Amersfoort Centraal", lat: 52.15334, lon: 5.40015))

        XCTAssertEqual(places.recents.map(\.title), ["Station Amersfoort Centraal", "Kapelweg 170A"])
        XCTAssertTrue(places.recents.allSatisfy { $0.kind == .recent })

        places.recordRecent(place("Kapelweg 170A", lat: 52.1375))
        XCTAssertEqual(places.recents.map(\.title), ["Kapelweg 170A", "Station Amersfoort Centraal"])
    }

    func testTwoSpotsFurtherApartThanTheThresholdAreBothKept() throws {
        let places = try store()
        places.recordRecent(place("A", lat: 52.1500))
        places.recordRecent(place("B", lat: 52.1505))
        XCTAssertEqual(places.recents.map(\.title), ["B", "A"])
    }

    func testRecentsAreCappedKeepingTheNewest() throws {
        let places = try store()
        for index in 1 ... 25 {
            places.recordRecent(place("Recent \(index)", lat: 52 + Double(index) * 0.01))
        }
        XCTAssertEqual(PlacesStore.recentLimit, 20)
        XCTAssertEqual(places.recents.count, 20)
        XCTAssertEqual(places.recents.first?.title, "Recent 25")
        XCTAssertEqual(places.recents.last?.title, "Recent 6")
    }

    func testClearingRecentsKeepsSavedPlaces() throws {
        let places = try store()
        places.recordRecent(place("A", lat: 52.1))
        places.addFavourite(place("A", lat: 52.1))
        places.setHome(place("H", lat: 52.2))
        places.clearRecents()
        XCTAssertTrue(places.recents.isEmpty)
        XCTAssertEqual(places.favourites.map(\.title), ["A"])
        XCTAssertEqual(places.home?.title, "H")
    }

    func testFavouritesCanBeAddedRenamedAndRemoved() throws {
        let places = try store()
        places.addFavourite(place("Woudenbergseweg 42", lat: 52.0478, subtitle: "Maarsbergen"))
        places.addFavourite(place("Kapelweg 170A", lat: 52.1375))
        places.addFavourite(place("Woudenbergseweg 42 (again)", lat: 52.04781, subtitle: "Maarsbergen"))
        XCTAssertEqual(places.favourites.map(\.title), ["Woudenbergseweg 42", "Kapelweg 170A"])

        let first = try XCTUnwrap(places.favourites.first)
        places.rename(first, to: "  Grandma  ")
        let renamed = try XCTUnwrap(places.favourites.first)
        XCTAssertEqual(renamed.displayName, "Grandma")
        XCTAssertEqual(renamed.destination, Destination(
            title: "Grandma",
            subtitle: "Woudenbergseweg 42, Maarsbergen",
            coordinate: Coordinate(lat: 52.0478, lon: 5.4)
        ))

        places.rename(renamed, to: "")
        XCTAssertNil(places.favourites.first?.name)
        XCTAssertEqual(places.favourites.first?.destination.title, "Woudenbergseweg 42")

        places.remove(try XCTUnwrap(places.favourites.last))
        XCTAssertEqual(places.favourites.map(\.title), ["Woudenbergseweg 42"])
    }

    func testHomeAndWorkAreSingleSlotsThatGetReplaced() throws {
        let places = try store()
        places.setHome(place("Old home", lat: 52.1))
        places.setHome(place("New home", lat: 52.2))
        places.setWork(place("Office", lat: 52.3))

        XCTAssertEqual(places.home?.title, "New home")
        XCTAssertEqual(places.work?.title, "Office")
        XCTAssertTrue(places.favourites.isEmpty)
        XCTAssertEqual(places.savedKinds(at: Coordinate(lat: 52.2, lon: 5.4)), [.home])
        XCTAssertEqual(places.savedKinds(at: Coordinate(lat: 52.1, lon: 5.4)), [])

        places.remove(try XCTUnwrap(places.home))
        XCTAssertNil(places.home)
        XCTAssertTrue(places.hasSavedPlaces)
    }

    func testSavedKindsIgnoreRecents() throws {
        let places = try store()
        let spot = place("Spot", lat: 52.1)
        places.recordRecent(spot)
        XCTAssertEqual(places.savedKinds(at: spot.coordinate), [])
        places.addFavourite(spot)
        places.setWork(spot)
        XCTAssertEqual(places.savedKinds(at: spot.coordinate), [.favourite, .work])
    }

    func testEverythingSurvivesANewContainerOnDisk() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "places-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "places.store")

        do {
            let places = try store(url: url)
            places.recordRecent(place("Older", lat: 52.1))
            places.recordRecent(place("Newer", lat: 52.2))
            places.addFavourite(place("Favourite", lat: 52.3))
            places.rename(try XCTUnwrap(places.favourites.first), to: "Renamed")
            places.setHome(place("Home", lat: 52.4))
            places.setWork(place("Work", lat: 52.5))
        }

        let reopened = try store(url: url)
        XCTAssertEqual(reopened.recents.map(\.title), ["Newer", "Older"])
        XCTAssertEqual(reopened.favourites.map(\.displayName), ["Renamed"])
        XCTAssertEqual(reopened.home?.coordinate, Coordinate(lat: 52.4, lon: 5.4))
        XCTAssertEqual(reopened.work?.title, "Work")

        reopened.removeAll()
        let emptied = try store(url: url)
        XCTAssertFalse(emptied.hasSavedPlaces)
        XCTAssertTrue(emptied.recents.isEmpty)
    }

    func testPDOKReverseParsesTheNearestAddress() throws {
        let bundle = Bundle(for: Self.self)
        let hit = try Data(contentsOf: XCTUnwrap(bundle.url(forResource: "pdok-reverse", withExtension: "json")))
        XCTAssertEqual(try PDOKClient.parseReverse(hit), PDOKClient.NearbyAddress(
            title: "Kapelweg 170A",
            subtitle: "3818BW Amersfoort",
            coordinate: Coordinate(lat: 52.13739391, lon: 5.37269016),
            distanceM: 14.0
        ))

        let empty = try Data(contentsOf: XCTUnwrap(bundle.url(forResource: "pdok-reverse-empty", withExtension: "json")))
        XCTAssertNil(try PDOKClient.parseReverse(empty))
    }

    func testReverseRequestAsksForTheNearestAddressWithinTheRadius() throws {
        let request = PDOKClient().reverseRequest(Coordinate(lat: 52.1375, lon: 5.3728))
        let components = try XCTUnwrap(URLComponents(url: XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        XCTAssertTrue(components.path.hasSuffix("/search/v3_1/reverse"), components.path)
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["lat"], "52.1375")
        XCTAssertEqual(items["lon"], "5.3728")
        XCTAssertEqual(items["type"], "adres")
        XCTAssertEqual(items["rows"], "1")
        XCTAssertEqual(items["distance"], "200")
    }

    func testAPinKeepsThePressedPointAndFallsBackToCoordinates() {
        let pressed = Coordinate(lat: 52.2977646, lon: 5.445363)
        let address = PDOKClient.NearbyAddress(
            title: "Kapelweg 170A",
            subtitle: "3818BW Amersfoort",
            coordinate: Coordinate(lat: 52.1374, lon: 5.3727),
            distanceM: 14
        )
        XCTAssertEqual(
            SearchModel.pinDestination(at: pressed, address: address),
            Destination(title: "Kapelweg 170A", subtitle: "3818BW Amersfoort", coordinate: pressed)
        )

        let fallback = SearchModel.pinDestination(at: pressed, address: nil)
        XCTAssertEqual(fallback.title, "52.29776, 5.44536")
        XCTAssertEqual(fallback.coordinate, pressed)
        XCTAssertEqual(Strings.tr("pin.dropped", language: .dutch), "Gekozen punt")
        XCTAssertEqual(Strings.tr("pin.dropped", language: .english), "Dropped pin")
    }
}
