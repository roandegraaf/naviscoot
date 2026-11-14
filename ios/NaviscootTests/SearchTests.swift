@testable import Naviscoot
import XCTest

final class SearchTests: XCTestCase {
    private func address(_ title: String, _ subtitle: String = "Amersfoort") -> SearchResult {
        SearchResult(id: "adr-\(title)", title: title, subtitle: subtitle, source: .address(pdokId: "adr-\(title)"), coordinate: nil)
    }

    private func place(_ title: String) -> SearchResult {
        SearchResult(id: "poi-\(title)", title: title, subtitle: "Amersfoort", source: .place, coordinate: Coordinate(lat: 52, lon: 5))
    }

    func testQueryWithANumberPutsAddressesFirstAndInterleaves() {
        let merged = SearchMerge.merge(
            addresses: [address("Stationsplein 10"), address("Stationsplein 12"), address("Stationsplein 14")],
            places: [place("Station Amersfoort Centraal")],
            query: "stationsplein 1"
        )
        XCTAssertEqual(merged.map(\.title), ["Stationsplein 10", "Station Amersfoort Centraal", "Stationsplein 12", "Stationsplein 14"])
    }

    func testQueryWithoutANumberPutsPlacesFirst() {
        let merged = SearchMerge.merge(
            addresses: [address("Stationsplein")],
            places: [place("Amersfoort Centraal"), place("Amersfoort Schothorst")],
            query: "amersfoort station"
        )
        XCTAssertEqual(merged.map(\.title), ["Amersfoort Centraal", "Stationsplein", "Amersfoort Schothorst"])
    }

    func testPlaceWithTheSameNameAsAnAddressIsDropped() {
        let merged = SearchMerge.merge(
            addresses: [address("Stationsplein")],
            places: [place("STATIONSPLEIN "), place("Café Stationsplein")],
            query: "stationsplein"
        )
        XCTAssertEqual(merged.map(\.id), ["poi-Café Stationsplein", "adr-Stationsplein"])
    }

    func testDiacriticsDoNotDefeatDeduplication() {
        let merged = SearchMerge.merge(addresses: [address("Cafe de Paris")], places: [place("Café de Paris")], query: "cafe")
        XCTAssertEqual(merged.map(\.id), ["adr-Cafe de Paris"])
    }

    func testOneSideEmptyAndLimit() {
        let addresses = (1 ... 20).map { address("Dorpsstraat \($0)") }
        XCTAssertEqual(SearchMerge.merge(addresses: addresses, places: [], query: "dorpsstraat 1").count, 12)
        XCTAssertEqual(SearchMerge.merge(addresses: [], places: [place("A"), place("B")], query: "x").map(\.title), ["A", "B"])
        XCTAssertTrue(SearchMerge.merge(addresses: [], places: [], query: "x").isEmpty)
    }

    func testDuplicateIdsAppearOnce() {
        let merged = SearchMerge.merge(addresses: [address("A"), address("A")], places: [], query: "a 1")
        XCTAssertEqual(merged.count, 1)
    }

    func testPDOKSuggestAndLookupParse() throws {
        let bundle = Bundle(for: Self.self)
        let suggest = try Data(contentsOf: XCTUnwrap(bundle.url(forResource: "pdok-suggest", withExtension: "json")))
        let results = try PDOKClient.parseSuggest(suggest)
        XCTAssertEqual(results.map(\.title), ["Stationsplein", "Stationsplein 12", "Stationsplein 51A"])
        XCTAssertEqual(results.map(\.subtitle), ["Amersfoort", "Amersfoort", "Amersfoort"])
        XCTAssertEqual(results.first?.source, .address(pdokId: "weg-724b88570ef48bf173188bc23995cf66"))
        XCTAssertTrue(results.allSatisfy { $0.coordinate == nil })

        let lookup = try Data(contentsOf: XCTUnwrap(bundle.url(forResource: "pdok-lookup", withExtension: "json")))
        XCTAssertEqual(try PDOKClient.parseLookup(lookup), Coordinate(lat: 52.15333786, lon: 5.37290257))
    }

    func testPDOKHelpers() throws {
        XCTAssertThrowsError(try PDOKClient.parsePoint("POINT(5.1)"))
        XCTAssertEqual(PDOKClient.splitDisplayName("Stationsplein 101, 3818LE Amersfoort").title, "Stationsplein 101")
        XCTAssertEqual(PDOKClient.splitDisplayName("Stationsplein 101, 3818LE Amersfoort").subtitle, "3818LE Amersfoort")
        XCTAssertEqual(PDOKClient.splitDisplayName("Amersfoort").subtitle, "")

        let request = PDOKClient().suggestRequest("stationsplein 1", near: Coordinate(lat: 52.156, lon: 5.387))
        let components = try XCTUnwrap(URLComponents(url: XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.path, "/bzk/locatieserver/search/v3_1/suggest")
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["q"], "stationsplein 1")
        XCTAssertEqual(items["lat"], "52.156")
        XCTAssertEqual(items["fq"], "type:(adres OR weg OR postcode OR woonplaats)")
    }
}
