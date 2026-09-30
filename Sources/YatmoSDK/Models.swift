import Foundation

// MARK: - /Points

/// One point of interest as returned by GET /Points (compact keys on the wire).
public struct YatmoPoi: Codable, Identifiable, Hashable, Sendable {
    public let name: String
    /// Translated type, for example "Preschool" or "Bus stop (Dansaert)".
    public let type: String
    public let latitude: Double
    public let longitude: Double
    /// Category id, the value to pass in `poiTypeIds`.
    public let categoryId: String
    /// Icon ids, comma separated when several POIs share the same position.
    public let icon: String
    /// Sub-icon ids (transit lines), comma separated, may be empty.
    public let subIcon: String
    public let grouped: Bool
    public let rpt: String?
    /// Specific data as a JSON string (transit lines, brand...), "{}" when empty.
    public let specificData: String?
    public let filterId: String?

    public var id: String { "\(latitude),\(longitude),\(name)" }
    public var iconIds: [String] { icon.split(separator: ",").map(String.init) }
    public var subIconIds: [String] { subIcon.split(separator: ",").map(String.init) }

    enum CodingKeys: String, CodingKey {
        case name = "n", type = "t", latitude = "la", longitude = "ln", categoryId = "p", icon = "i", subIcon = "si"
        case grouped = "g", rpt, specificData = "sd", filterId = "fid"
    }
}

// MARK: - /Summary

/// Travel information for one mode, as computed by the routing engine.
public struct YatmoTravelData: Codable, Hashable, Sendable {
    public let hasTravelInformation: Bool
    /// 1 driving, 2 walking, 3 bicycling, 4 transit. See `travelMode`.
    public let travelModeCode: Int
    public let translatedTravelMode: String?
    public let distanceMeters: Int?
    public let distanceLongLabel: String?
    public let distanceShortLabel: String?
    public let travelTimeSeconds: Int?
    public let travelTimeLongLabel: String?
    public let travelTimeShortLabel: String?
    public let travelTimeExtraShortLabel: String?

    public var travelMode: YatmoTravelMode? {
        YatmoTravelMode.allCases.first { $0.summaryCode == travelModeCode }
    }

    enum CodingKeys: String, CodingKey {
        case hasTravelInformation = "hti", travelModeCode = "tm", translatedTravelMode = "ttm"
        case distanceMeters = "ptdd", distanceLongLabel = "ptdll", distanceShortLabel = "ptdsl"
        case travelTimeSeconds = "tt", travelTimeLongLabel = "ttll", travelTimeShortLabel = "ttsl", travelTimeExtraShortLabel = "ttesl"
    }
}

/// One place inside a Summary sub-category.
public struct YatmoSummaryPlace: Codable, Hashable, Sendable {
    public let categoryId: Int64
    public let icon: Int
    public let subIcon: Int
    public let latitude: Double
    public let longitude: Double
    public let name: String
    public let specificData: String?
    public let travelData: [YatmoTravelData]

    public func travel(_ mode: YatmoTravelMode) -> YatmoTravelData? {
        travelData.first { $0.travelModeCode == mode.summaryCode }
    }

    enum CodingKeys: String, CodingKey {
        case categoryId = "id", icon = "i", subIcon = "si", latitude = "la", longitude = "lo", name = "n", specificData = "sd", travelData = "td"
    }
}

public struct YatmoSummarySubCategory: Codable, Hashable, Sendable {
    public let subType: Int
    public let label: String
    public let singularLabel: String?
    public let places: [YatmoSummaryPlace]

    enum CodingKeys: String, CodingKey {
        case subType = "st", label = "l", singularLabel = "lb", places = "d"
    }
}

public struct YatmoSummaryCategory: Codable, Hashable, Sendable {
    public let categoryType: Int
    public let label: String
    public let subCategories: [YatmoSummarySubCategory]

    enum CodingKeys: String, CodingKey {
        case categoryType = "ct", label = "l", subCategories = "sc"
    }
}

public struct YatmoGeoPosition: Codable, Hashable, Sendable {
    public let latitude: Double
    public let longitude: Double

    enum CodingKeys: String, CodingKey {
        case latitude = "Latitude", longitude = "Longitude"
    }
}

public struct YatmoCloseCity: Codable, Hashable, Sendable {
    /// City name per language code (EN, FR, NL...).
    public let names: [String: String]
    public let travelData: [YatmoTravelData]
    public let center: YatmoGeoPosition?

    public func name(in language: YatmoLanguage) -> String? {
        names[language.rawValue] ?? names["EN"] ?? names.values.first
    }

    enum CodingKeys: String, CodingKey {
        case names = "n", travelData = "td", center = "c"
    }
}

public struct YatmoPlaceInformation: Codable, Hashable, Sendable {
    public let streetName: String?
    public let isLocality: Bool
    public let cityName: String?
    public let zipCode: String?
    public let localizedStreetNames: [String: String]?
    public let localizedCityNames: [String: String]?

    enum CodingKeys: String, CodingKey {
        case streetName = "StreetName", isLocality = "IsLocality", cityName = "CityName", zipCode = "ZipCode"
        case localizedStreetNames = "LocalizedStreetNames", localizedCityNames = "LocalizedCityNames"
    }
}

/// GET /Summary: nearby places grouped by category, closest cities and reverse-geocoded place.
public struct YatmoSummary: Codable, Hashable, Sendable {
    public let categories: [YatmoSummaryCategory]
    public let closeCities: [YatmoCloseCity]
    public let placeInformation: YatmoPlaceInformation?

    enum CodingKeys: String, CodingKey {
        case categories = "AvailableCategoriesAroundPosition", closeCities = "CloseCities", placeInformation = "PlaceInformation"
    }
}

// MARK: - /Summary/text

/// Generated neighbourhood paragraphs, resolved to the configured language by the client.
public struct YatmoSummaryText: Hashable, Sendable {
    public struct Paragraph: Hashable, Sendable {
        public let sentences: [String]
        public var text: String { sentences.joined(separator: " ") }
    }

    public let paragraphs: [Paragraph]
    public var text: String { paragraphs.map(\.text).joined(separator: "\n\n") }

    struct Wire: Decodable {
        struct Paragraph: Decodable { let Sentences: [[String: String]] }
        let Paragraphs: [Paragraph]
    }

    init(wire: Wire, language: YatmoLanguage) {
        paragraphs = wire.Paragraphs.map { paragraph in
            Paragraph(sentences: paragraph.Sentences.compactMap { translations in
                translations[language.rawValue] ?? translations["EN"] ?? translations.values.first
            })
        }
    }
}

// MARK: - /Scores

public struct YatmoScore: Codable, Hashable, Sendable {
    /// Stable key: publicTransport, trains, motorways, nurseries, schools, supermarkets...
    public let key: String
    public let label: String
    /// 0 to 10.
    public let value: Double
    public let iconId: Int?
    public let categoryType: Int?
    public let subTypes: [Int]?

    enum CodingKeys: String, CodingKey {
        case key = "k", label = "l", value = "v", iconId, categoryType = "pt", subTypes = "st"
    }
}

public struct YatmoScores: Codable, Hashable, Sendable {
    public let scores: [YatmoScore]
    public let language: String?
}

// MARK: - /Enrichment

public struct YatmoTravelInfo: Codable, Hashable, Sendable {
    public let distanceMeters: Int
    public let durationSeconds: Int
    public let durationMinutes: Int
}

public struct YatmoNearestPoi: Codable, Hashable, Sendable {
    public let name: String
    public let latitude: Double
    public let longitude: Double
    public let straightLineDistanceMeters: Int
    public let walking: YatmoTravelInfo?
    public let bicycling: YatmoTravelInfo?
    public let driving: YatmoTravelInfo?
    public let transit: YatmoTravelInfo?
}

public struct YatmoEnrichedCategory: Codable, Hashable, Sendable {
    public let id: Int64
    public let key: String
    public let group: String
    public let label: String
    public let nearest: YatmoNearestPoi?
}

/// GET /Enrichment: the nearest place of each category with routed distances and times.
public struct YatmoEnrichment: Codable, Hashable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let country: String
    public let language: String
    public let searchRadiusMeters: Int
    public let categories: [YatmoEnrichedCategory]
}

// MARK: - /Isochrone/GetMultipleTimes

/// One reachable area. `geometry` is the GeoJSON geometry object (Polygon or MultiPolygon) as returned by the API.
public struct YatmoIsochrone: Hashable, Sendable {
    public let label: String
    public let geometryJSON: Data

    public var geometry: [String: Any]? {
        (try? JSONSerialization.jsonObject(with: geometryJSON)) as? [String: Any]
    }
}

// MARK: - /Geolocation/GetClose (Photon)

public struct YatmoPlace: Hashable, Sendable {
    public let name: String?
    public let street: String?
    public let houseNumber: String?
    public let postcode: String?
    public let city: String?
    public let country: String?
    public let countryCode: String?
    public let type: String?
    public let latitude: Double
    public let longitude: Double

    /// "Rue Neuve, 1000 Brussels" style single line.
    public var label: String {
        [name ?? street, [postcode, city].compactMap { $0 }.joined(separator: " ")]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

// MARK: - /SimplifiedCategories

public struct YatmoCategoryGroup: Hashable, Sendable {
    /// Education, Transports, Motorways, Shopping, Tourism...
    public let name: String
    public let poiTypeIds: [Int64]
}
