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
    case tooManyStops
    case conflictingTimes
    case alternativesNeedTwoPoints
    case stopsUnsupported
    case http(status: Int, code: String?)
}

struct RouteAvoid: Equatable, Codable {
    var ferries = false
    var unpaved = false
    var mainRoads = false
}

enum RouteTime: Equatable {
    case departAt(Date)
    case arriveBy(Date)
}

struct RouteOptions: Equatable {
    var stops: [Coordinate] = []
    var alternatives = 0
    var time: RouteTime?
    var avoid = RouteAvoid()
}

final class NaviscootClient {
    private let config: APIConfig
    private let session: URLSession

    init(config: APIConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    func makeRouteRequest(
        from origin: Coordinate,
        to destination: Coordinate,
        options: RouteOptions = RouteOptions(),
        verifiedOnly: Bool,
        language: Language
    ) throws -> URLRequest {
        var request = URLRequest(url: config.baseURL.appending(path: "route"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        var body: [String: Any] = [
            "origin": ["lat": origin.lat, "lon": origin.lon],
            "destination": ["lat": destination.lat, "lon": destination.lon],
            "verified_only": verifiedOnly,
            "format": "osrm",
            "language": language.speechCode,
        ]
        if !options.stops.isEmpty {
            body["waypoints"] = options.stops.map { ["lat": $0.lat, "lon": $0.lon] }
        }
        if options.alternatives > 0 {
            body["alternatives"] = options.alternatives
        }
        switch options.time {
        case let .departAt(date): body["depart_at"] = ISO8601DateFormatter().string(from: date)
        case let .arriveBy(date): body["arrive_by"] = ISO8601DateFormatter().string(from: date)
        case nil: break
        }
        if options.avoid != RouteAvoid() {
            body["avoid"] = ["ferries": options.avoid.ferries, "unpaved": options.avoid.unpaved, "main_roads": options.avoid.mainRoads]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    func route(from origin: Coordinate, to destination: Coordinate, stops: [Coordinate], avoid: RouteAvoid, verifiedOnly: Bool, language: Language) async throws -> RoutePlan {
        let options = RouteOptions(stops: stops, avoid: avoid)
        guard let plan = try await routes(from: origin, to: destination, options: options, verifiedOnly: verifiedOnly, language: language).first else {
            throw RouteParseError.noRoute
        }
        return plan
    }

    func routes(
        from origin: Coordinate,
        to destination: Coordinate,
        options: RouteOptions = RouteOptions(),
        verifiedOnly: Bool,
        language: Language
    ) async throws -> [RoutePlan] {
        let request = try makeRouteRequest(from: origin, to: destination, options: options, verifiedOnly: verifiedOnly, language: language)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw Self.error(status: status, body: data)
        }
        let plans = try RouteParser.parseAll(data)
        if !options.stops.isEmpty, let primary = plans.first, primary.route.waypoints.count != options.stops.count + 2 {
            throw RouteRequestError.stopsUnsupported
        }
        return plans
    }

    static func error(status: Int, body: Data) -> RouteRequestError {
        struct ErrorBody: Decodable { let error: String }
        let code = (try? JSONDecoder().decode(ErrorBody.self, from: body))?.error
        switch (status, code) {
        case (401, _): return .unauthorized
        case (422, "no_route"): return .noRoute
        case (502, "valhalla_unavailable"): return .serviceUnavailable
        case (502, "classification_failed"): return .classificationFailed
        case (400, "too_many_waypoints"): return .tooManyStops
        case (400, "conflicting_times"): return .conflictingTimes
        case (400, "alternatives_need_two_points"): return .alternativesNeedTwoPoints
        default: return .http(status: status, code: code)
        }
    }
}

extension NaviscootClient: ReportSending {
    func makeReportRequest(_ report: PendingReport) throws -> URLRequest {
        var request = URLRequest(url: config.baseURL.appending(path: "reports"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        var body: [String: Any] = [
            "lat": report.lat,
            "lon": report.lon,
            "time": ISO8601DateFormatter().string(from: report.time),
        ]
        if let routeId = report.routeId {
            body["route_id"] = routeId
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    func send(_ report: PendingReport) async throws {
        let request = try makeReportRequest(report)
        let response: URLResponse
        do {
            (_, response) = try await session.data(for: request)
        } catch {
            throw ReportSendError.retryable
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200 ..< 300: return
        case 400, 413, 422: throw ReportSendError.rejected(status: status)
        default: throw ReportSendError.retryable
        }
    }
}
