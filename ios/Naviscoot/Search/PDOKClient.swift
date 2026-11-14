import Foundation

enum PDOKError: Error, Equatable {
    case http(status: Int)
    case notFound
    case badCentroid(String)
}

final class PDOKClient {
    static let baseURL = URL(string: "https://api.pdok.nl/bzk/locatieserver/search/v3_1")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    private struct SuggestResponse: Decodable {
        struct Body: Decodable { let docs: [Doc] }
        struct Doc: Decodable {
            let id: String
            let weergavenaam: String
            let type: String
        }

        let response: Body
    }

    private struct LookupResponse: Decodable {
        struct Body: Decodable { let docs: [Doc] }
        struct Doc: Decodable {
            let id: String
            let weergavenaam: String
            let centroide_ll: String
        }

        let response: Body
    }

    func suggestRequest(_ query: String, near: Coordinate?, rows: Int = 8) -> URLRequest {
        var items = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "rows", value: String(rows)),
            URLQueryItem(name: "fq", value: "type:(adres OR weg OR postcode OR woonplaats)"),
        ]
        if let near {
            items.append(URLQueryItem(name: "lat", value: String(near.lat)))
            items.append(URLQueryItem(name: "lon", value: String(near.lon)))
        }
        return URLRequest(url: Self.baseURL.appending(path: "suggest").appending(queryItems: items))
    }

    func suggest(_ query: String, near: Coordinate?) async throws -> [SearchResult] {
        try Self.parseSuggest(await fetch(suggestRequest(query, near: near)))
    }

    func lookup(id: String) async throws -> Coordinate {
        let items = [URLQueryItem(name: "id", value: id), URLQueryItem(name: "fl", value: "id,weergavenaam,centroide_ll")]
        let request = URLRequest(url: Self.baseURL.appending(path: "lookup").appending(queryItems: items))
        return try Self.parseLookup(await fetch(request))
    }

    private func fetch(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw PDOKError.http(status: status) }
        return data
    }

    static func parseSuggest(_ data: Data) throws -> [SearchResult] {
        try JSONDecoder().decode(SuggestResponse.self, from: data).response.docs.map { doc in
            let (title, subtitle) = splitDisplayName(doc.weergavenaam)
            return SearchResult(id: doc.id, title: title, subtitle: subtitle, source: .address(pdokId: doc.id), coordinate: nil)
        }
    }

    static func parseLookup(_ data: Data) throws -> Coordinate {
        guard let doc = try JSONDecoder().decode(LookupResponse.self, from: data).response.docs.first else {
            throw PDOKError.notFound
        }
        return try parsePoint(doc.centroide_ll)
    }

    static func parsePoint(_ wkt: String) throws -> Coordinate {
        let numbers = wkt
            .replacingOccurrences(of: "POINT(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .split(separator: " ")
            .compactMap { Double($0) }
        guard numbers.count == 2 else { throw PDOKError.badCentroid(wkt) }
        return Coordinate(lat: numbers[1], lon: numbers[0])
    }

    static func splitDisplayName(_ name: String) -> (title: String, subtitle: String) {
        guard let comma = name.firstIndex(of: ",") else { return (name, "") }
        let title = String(name[..<comma])
        let subtitle = name[name.index(after: comma)...].trimmingCharacters(in: .whitespaces)
        return (title, subtitle)
    }
}
