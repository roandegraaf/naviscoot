import Foundation

struct APIConfig: Equatable {
    let baseURL: URL
    let apiKey: String

    static func fromBundle(_ bundle: Bundle = .main) -> APIConfig? {
        guard let base = bundle.object(forInfoDictionaryKey: "NaviscootAPIBaseURL") as? String,
              let key = bundle.object(forInfoDictionaryKey: "NaviscootAPIKey") as? String,
              !key.isEmpty,
              let url = URL(string: base),
              url.scheme != nil, url.host() != nil
        else { return nil }
        return APIConfig(baseURL: url, apiKey: key)
    }
}

enum RouteRequestError: Error, Equatable {
    case unauthorized
    case noRoute
    case serviceUnavailable
    case classificationFailed
    case http(status: Int, code: String?)
}

final class NaviscootClient {
    private let config: APIConfig
    private let session: URLSession

    init(config: APIConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    func makeRouteRequest(from origin: Coordinate, to destination: Coordinate, verifiedOnly: Bool) throws -> URLRequest {
        var request = URLRequest(url: config.baseURL.appending(path: "route"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        let body: [String: Any] = [
            "origin": ["lat": origin.lat, "lon": origin.lon],
            "destination": ["lat": destination.lat, "lon": destination.lon],
            "verified_only": verifiedOnly,
            "format": "osrm",
            "language": "nl-NL",
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    func route(from origin: Coordinate, to destination: Coordinate, verifiedOnly: Bool) async throws -> RoutePlan {
        let request = try makeRouteRequest(from: origin, to: destination, verifiedOnly: verifiedOnly)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw Self.error(status: status, body: data)
        }
        return try RouteParser.parse(data)
    }

    static func error(status: Int, body: Data) -> RouteRequestError {
        struct ErrorBody: Decodable { let error: String }
        let code = (try? JSONDecoder().decode(ErrorBody.self, from: body))?.error
        switch (status, code) {
        case (401, _): return .unauthorized
        case (422, "no_route"): return .noRoute
        case (502, "valhalla_unavailable"): return .serviceUnavailable
        case (502, "classification_failed"): return .classificationFailed
        default: return .http(status: status, code: code)
        }
    }
}
