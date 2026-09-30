import Foundation

/// Typed, asynchronous client for the Yatmo REST API. Every call sends the licence and the mobile headers.
public final class YatmoClient: @unchecked Sendable {
    public let configuration: YatmoConfiguration
    private let session: URLSession
    private let decoder = JSONDecoder()

    public init(configuration: YatmoConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    // MARK: Endpoints

    /// GET /Summary: nearby places by category with travel times, closest cities, reverse-geocoded place.
    public func summary(latitude: Double, longitude: Double) async throws -> YatmoSummary {
        try await get("Summary", query: position(latitude, longitude) + language())
    }

    /// GET /Summary/text: generated paragraphs, resolved to the configured language.
    public func summaryText(latitude: Double, longitude: Double) async throws -> YatmoSummaryText {
        let wire: YatmoSummaryText.Wire = try await get("Summary/text", query: position(latitude, longitude) + language())
        return YatmoSummaryText(wire: wire, language: configuration.language)
    }

    /// GET /Scores: one 0 to 10 score per category.
    public func scores(latitude: Double, longitude: Double) async throws -> YatmoScores {
        try await get("Scores", query: position(latitude, longitude) + language())
    }

    /// GET /Enrichment: nearest place of each category with distances and times for four travel modes.
    public func enrichment(latitude: Double, longitude: Double) async throws -> YatmoEnrichment {
        try await get("Enrichment", query: position(latitude, longitude) + language())
    }

    /// GET /Points inside a bounding box. Only ask from zoom 13 upwards and debounce camera events.
    public func points(southWest: (latitude: Double, longitude: Double),
                       northEast: (latitude: Double, longitude: Double),
                       poiTypeIds: [Int64]? = nil) async throws -> [YatmoPoi] {
        var query = [
            URLQueryItem(name: "bound1", value: "\(fmt(southWest.latitude)),\(fmt(southWest.longitude))"),
            URLQueryItem(name: "bound2", value: "\(fmt(northEast.latitude)),\(fmt(northEast.longitude))"),
            URLQueryItem(name: "groupSamePositions", value: "true"),
            URLQueryItem(name: "caringForBigResponse", value: "true")
        ] + language()
        if let ids = poiTypeIds, !ids.isEmpty {
            query.append(URLQueryItem(name: "poiTypesIds", value: ids.map(String.init).joined(separator: ",")))
        }
        return try await get("Points", query: query)
    }

    /// GET /Isochrone/GetMultipleTimes: the 5, 10 and 20 minute areas, smallest first.
    public func isochrones(mode: YatmoTravelMode, latitude: Double, longitude: Double) async throws -> [YatmoIsochrone] {
        let data = try await getData("Isochrone/GetMultipleTimes",
                                     query: [URLQueryItem(name: "travelMode", value: mode.rawValue)] + position(latitude, longitude) + language())
        guard let items = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw YatmoError.invalidResponse }
        return try items.map { item in
            guard let label = item["label"] as? String, let iso = item["iso"] else { throw YatmoError.invalidResponse }
            return YatmoIsochrone(label: label, geometryJSON: try JSONSerialization.data(withJSONObject: iso))
        }
    }

    /// GET /Geolocation/GetClose: address autocomplete near a position, inside the configured country.
    public func geocode(query: String, latitude: Double, longitude: Double) async throws -> [YatmoPlace] {
        let data = try await getData("Geolocation/GetClose",
                                     query: [URLQueryItem(name: "address", value: query)] + position(latitude, longitude) + language())
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = root["features"] as? [[String: Any]] else { throw YatmoError.invalidResponse }
        return features.compactMap { feature in
            guard let geometry = feature["geometry"] as? [String: Any],
                  let coordinates = geometry["coordinates"] as? [Double], coordinates.count == 2 else { return nil }
            let p = feature["properties"] as? [String: Any] ?? [:]
            return YatmoPlace(name: p["name"] as? String, street: p["street"] as? String, houseNumber: p["housenumber"] as? String,
                              postcode: p["postcode"] as? String, city: p["city"] as? String, country: p["country"] as? String,
                              countryCode: p["countrycode"] as? String, type: p["type"] as? String,
                              latitude: coordinates[1], longitude: coordinates[0])
        }
    }

    /// GET /SimplifiedCategories: category ids grouped by family, the values accepted by `poiTypeIds`.
    public func simplifiedCategories() async throws -> [YatmoCategoryGroup] {
        let data = try await getData("SimplifiedCategories", query: language())
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: [NSNumber]] else { throw YatmoError.invalidResponse }
        return root.map { YatmoCategoryGroup(name: $0.key, poiTypeIds: $0.value.map(\.int64Value)) }
            .sorted { $0.name < $1.name }
    }

    // MARK: Plumbing

    /// Builds a request with the licence and mobile headers, for callers that need an endpoint not wrapped above.
    public func request(path: String, query: [URLQueryItem]) -> URLRequest {
        var components = URLComponents(url: configuration.resolvedBaseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query
        var request = URLRequest(url: components.url!, timeoutInterval: configuration.timeout)
        request.setValue(configuration.licenseKey, forHTTPHeaderField: "LicenseKey")
        request.setValue(configuration.appId, forHTTPHeaderField: "X-Yatmo-App-Id")
        request.setValue("ios", forHTTPHeaderField: "X-Yatmo-Platform")
        request.setValue("yatmo-ios/\(yatmoSdkVersion)", forHTTPHeaderField: "X-Yatmo-SDK")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem]) async throws -> T {
        let data = try await getData(path, query: query)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw YatmoError.invalidResponse
        }
    }

    private func getData(_ path: String, query: [URLQueryItem]) async throws -> Data {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request(path: path, query: query))
        } catch {
            throw YatmoError.transport(error)
        }
        guard let http = response as? HTTPURLResponse else { throw YatmoError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["Error"] as? String
                ?? String(data: data, encoding: .utf8) ?? ""
            throw YatmoError.http(status: http.statusCode, message: message)
        }
        return data
    }

    private func position(_ latitude: Double, _ longitude: Double) -> [URLQueryItem] {
        [URLQueryItem(name: "latitude", value: fmt(latitude)), URLQueryItem(name: "longitude", value: fmt(longitude))]
    }

    private func language() -> [URLQueryItem] {
        [URLQueryItem(name: "language", value: configuration.language.rawValue)]
    }

    private func fmt(_ value: Double) -> String {
        String(format: "%.7f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
