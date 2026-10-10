import Foundation

/// POI icons are served from one CDN for every country: cdn/<iso code>/ (same rule as the web plugin's getCdnUrl).
public enum YatmoCdn {
    public static let host = "https://beprod-chh6e6e9hhg8bwha.z01.azurefd.net/"

    public static func baseURL(for country: YatmoCountry) -> URL {
        URL(string: host + "cdn/" + country.rawValue.lowercased() + "/")!
    }

    /// `{cdn}/icons{size}/{iconId}@2x.png`, size 24 or 32.
    public static func iconURL(country: YatmoCountry, iconId: String, size: Int = 24) -> URL {
        baseURL(for: country).appendingPathComponent("icons\(size)/\(iconId)@2x.png")
    }

    /// `{cdn}/subicons24/{subIconId}@2x.png`: transit line badges.
    public static func subIconURL(country: YatmoCountry, subIconId: String) -> URL {
        baseURL(for: country).appendingPathComponent("subicons24/\(subIconId)@2x.png")
    }
}
