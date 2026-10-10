import Foundation

/// Version sent in the X-Yatmo-SDK header. Keep in sync with the Git tag.
public let yatmoSdkVersion = "1.0.1"

/// Countries served by the Yatmo API. The raw value is the subdomain: `https://{country}.yatmo.com/`.
public enum YatmoCountry: String, CaseIterable, Codable, Sendable {
    case BE, FR, NL, LU, CH, DE, IT, ES, PT, IE, UK, AT, CA, GR, MA, AU, HR, MT, SI, RS, CY, BA, ME, BG, AL
}

/// Languages accepted by the `language` parameter of the API.
public enum YatmoLanguage: String, CaseIterable, Codable, Sendable {
    case EN, FR, NL, DE, IT, ES, PT, CA, ZH, HI, AR, RU, JA, EL, HR, MT, SL, SR, TR, BS, SQ, BG, CNR
}

/// The seven map styles of the web plugin. The raw value is the style id used by the plugin.
public enum YatmoMapStyle: Int, CaseIterable, Sendable {
    case liberty = 1, basic, bright, threeD, positron, dark, libertyStonehedge

    public var url: URL {
        let name: String
        switch self {
        case .liberty: name = "osm_liberty"
        case .basic: name = "osm_basic"
        case .bright: name = "osm_bright"
        case .threeD: name = "osm_3d"
        case .positron: name = "osm_positron"
        case .dark: name = "osm_dark"
        case .libertyStonehedge: name = "osm_liberty_stonehedge"
        }
        return URL(string: "https://map.yatmo.com/\(name).json")!
    }
}

/// Travel modes of the routing endpoints. The raw value is the API spelling.
public enum YatmoTravelMode: String, CaseIterable, Codable, Sendable {
    case driving = "Driving"
    case walking = "Walking"
    case bicycling = "Bicycling"
    case transit = "Transit"

    /// Numeric code used inside the Summary payload (`td[].tm`).
    public var summaryCode: Int {
        switch self {
        case .driving: return 1
        case .walking: return 2
        case .bicycling: return 3
        case .transit: return 4
        }
    }
}

/// Everything the SDK needs to talk to the API. One instance per app.
public struct YatmoConfiguration: Sendable {
    /// Your frontend key (the one used by the web plugins). Never the backend key.
    public var licenseKey: String
    public var country: YatmoCountry
    public var language: YatmoLanguage
    /// iOS bundle identifier sent in X-Yatmo-App-Id and checked against the app ids registered on your licence.
    /// Defaults to `Bundle.main.bundleIdentifier`.
    public var appId: String
    /// Override the API host, for staging environments. Defaults to `https://{country}.yatmo.com/`.
    public var apiBaseURL: URL?
    /// Request timeout in seconds.
    public var timeout: TimeInterval

    public init(licenseKey: String,
                country: YatmoCountry,
                language: YatmoLanguage,
                appId: String? = nil,
                apiBaseURL: URL? = nil,
                timeout: TimeInterval = 15) {
        self.licenseKey = licenseKey
        self.country = country
        self.language = language
        self.appId = appId ?? Bundle.main.bundleIdentifier ?? ""
        self.apiBaseURL = apiBaseURL
        self.timeout = timeout
    }

    var resolvedBaseURL: URL {
        apiBaseURL ?? URL(string: "https://\(country.rawValue.lowercased()).yatmo.com/")!
    }
}

/// Errors thrown by the client and reported by the map view.
public enum YatmoError: Error, LocalizedError {
    /// The API answered with a non-2xx status. 401 = key missing or unknown, 403 = app id or country not allowed, 429 = quota.
    case http(status: Int, message: String)
    case invalidResponse
    case transport(Error)

    public var errorDescription: String? {
        switch self {
        case .http(let status, let message): return "Yatmo API \(status): \(message)"
        case .invalidResponse: return "Yatmo API: unreadable response"
        case .transport(let error): return error.localizedDescription
        }
    }
}

/// Entry point: holds the configuration and the client. Create it once and share it.
public final class Yatmo: @unchecked Sendable {
    public let configuration: YatmoConfiguration
    public let client: YatmoClient

    public init(configuration: YatmoConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.client = YatmoClient(configuration: configuration, session: session)
    }

    /// Base URL of the POI icons for the configured country.
    public var cdnBaseURL: URL {
        YatmoCdn.baseURL(for: configuration.country)
    }
}
