import MapKit

enum PlaceSearch {
    static func search(_ query: String, near: Coordinate?) async throws -> [SearchResult] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .pointOfInterest
        if let near {
            request.region = MKCoordinateRegion(center: near.clLocation, latitudinalMeters: 60000, longitudinalMeters: 60000)
        }
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.enumerated().compactMap { index, item in
            guard let name = item.name else { return nil }
            let coordinate = Coordinate(coordinate(of: item))
            return SearchResult(
                id: "poi-\(index)-\(coordinate.lat)-\(coordinate.lon)",
                title: name,
                subtitle: subtitle(of: item),
                source: .place,
                coordinate: coordinate
            )
        }
    }

    private static func coordinate(of item: MKMapItem) -> CLLocationCoordinate2D {
        if #available(iOS 26.0, *) {
            return item.location.coordinate
        }
        return item.placemark.coordinate
    }

    private static func subtitle(of item: MKMapItem) -> String {
        if #available(iOS 26.0, *) {
            return item.addressRepresentations?.cityName ?? item.address?.shortAddress ?? ""
        }
        return item.placemark.locality ?? ""
    }
}
