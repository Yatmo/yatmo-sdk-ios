import Foundation
import WebKit

/// Options of the iframe plugin (https://documentation.yatmo.com/plugins/iframe). Every field maps to a URL parameter.
public struct YatmoWebViewOptions: Sendable {
    public enum Mode: String, Sendable {
        case overlay, overlayScores = "overlay-scores", mapTop = "map-top", map, summary, summaryTabs = "summary-tabs"
    }

    public var latitude: Double
    public var longitude: Double
    public var mode: Mode
    public var zoom: Int
    /// Hex colour, for example "#428BFF".
    public var accentColor: String?
    /// "pin" or "circle".
    public var marker: String?
    public var mapStyle: YatmoMapStyle?
    /// Any extra iframe parameter, appended as is.
    public var extraParameters: [String: String]

    public init(latitude: Double, longitude: Double, mode: Mode = .overlay, zoom: Int = 15,
                accentColor: String? = nil, marker: String? = nil, mapStyle: YatmoMapStyle? = nil,
                extraParameters: [String: String] = [:]) {
        self.latitude = latitude
        self.longitude = longitude
        self.mode = mode
        self.zoom = zoom
        self.accentColor = accentColor
        self.marker = marker
        self.mapStyle = mapStyle
        self.extraParameters = extraParameters
    }

    public func url(configuration: YatmoConfiguration) -> URL {
        var components = URLComponents(string: "https://map.yatmo.com/plugin.html")!
        var items = [
            URLQueryItem(name: "licenseKey", value: configuration.licenseKey),
            URLQueryItem(name: "country", value: configuration.country.rawValue),
            URLQueryItem(name: "language", value: configuration.language.rawValue),
            URLQueryItem(name: "latitude", value: String(format: "%.7f", locale: Locale(identifier: "en_US_POSIX"), latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.7f", locale: Locale(identifier: "en_US_POSIX"), longitude)),
            URLQueryItem(name: "mode", value: mode.rawValue),
            URLQueryItem(name: "zoom", value: String(zoom))
        ]
        if let accentColor { items.append(URLQueryItem(name: "accentColor", value: accentColor)) }
        if let marker { items.append(URLQueryItem(name: "marker", value: marker)) }
        if let mapStyle { items.append(URLQueryItem(name: "mapStyle", value: String(mapStyle.rawValue))) }
        for (key, value) in extraParameters.sorted(by: { $0.key < $1.key }) {
            items.append(URLQueryItem(name: key, value: value))
        }
        components.queryItems = items
        return components.url!
    }
}

/// A WKWebView preloaded with the Yatmo iframe plugin: the full web experience (map, summary panel, scores, tabs).
public final class YatmoWebView: WKWebView {
    public let yatmo: Yatmo

    public init(yatmo: Yatmo, options: YatmoWebViewOptions, frame: CGRect = .zero) {
        self.yatmo = yatmo
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        super.init(frame: frame, configuration: configuration)
        scrollView.bounces = false
        load(options)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("YatmoWebView is created in code") }

    public func load(_ options: YatmoWebViewOptions) {
        load(URLRequest(url: options.url(configuration: yatmo.configuration)))
    }
}
