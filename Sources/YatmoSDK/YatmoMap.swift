import SwiftUI

/// SwiftUI wrapper around `YatmoMapView`.
///
/// ```swift
/// YatmoMap(yatmo: yatmo, latitude: 50.85, longitude: 4.34, zoom: 15, isochrones: .walking) { poi in
///     print(poi.name)
/// }
/// .frame(height: 320)
/// ```
public struct YatmoMap: UIViewRepresentable {
    public var yatmo: Yatmo
    public var latitude: Double
    public var longitude: Double
    public var zoom: Double
    public var style: YatmoMapStyle
    public var isochrones: YatmoTravelMode?
    public var poiTypeIds: [Int64]?
    public var poiIconSize: CGFloat
    public var onPoiSelected: ((YatmoPoi) -> Void)?
    public var onError: ((Error) -> Void)?

    public init(yatmo: Yatmo,
                latitude: Double,
                longitude: Double,
                zoom: Double = 15,
                style: YatmoMapStyle = .liberty,
                isochrones: YatmoTravelMode? = nil,
                poiTypeIds: [Int64]? = nil,
                poiIconSize: CGFloat = 24,
                onError: ((Error) -> Void)? = nil,
                onPoiSelected: ((YatmoPoi) -> Void)? = nil) {
        self.yatmo = yatmo
        self.latitude = latitude
        self.longitude = longitude
        self.zoom = zoom
        self.style = style
        self.isochrones = isochrones
        self.poiTypeIds = poiTypeIds
        self.poiIconSize = poiIconSize
        self.onError = onError
        self.onPoiSelected = onPoiSelected
    }

    public func makeUIView(context: Context) -> YatmoMapView {
        let view = YatmoMapView(yatmo: yatmo, style: style)
        view.poiIconSize = poiIconSize
        view.poiTypeIds = poiTypeIds
        view.onPoiSelected = onPoiSelected
        view.onError = onError
        view.showProperty(latitude: latitude, longitude: longitude, zoom: zoom)
        if let mode = isochrones { view.showIsochrones(mode: mode) }
        context.coordinator.state = State(latitude: latitude, longitude: longitude, style: style, isochrones: isochrones, poiTypeIds: poiTypeIds)
        return view
    }

    public func updateUIView(_ view: YatmoMapView, context: Context) {
        view.onPoiSelected = onPoiSelected
        view.onError = onError
        let previous = context.coordinator.state
        if previous.latitude != latitude || previous.longitude != longitude {
            view.showProperty(latitude: latitude, longitude: longitude, zoom: zoom, animated: true)
        }
        if previous.style != style { view.setStyle(style) }
        if previous.poiTypeIds != poiTypeIds { view.poiTypeIds = poiTypeIds }
        if previous.isochrones != isochrones {
            if let mode = isochrones { view.showIsochrones(mode: mode) } else { view.hideIsochrones() }
        }
        context.coordinator.state = State(latitude: latitude, longitude: longitude, style: style, isochrones: isochrones, poiTypeIds: poiTypeIds)
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public final class Coordinator {
        var state = State(latitude: 0, longitude: 0, style: .liberty, isochrones: nil, poiTypeIds: nil)
    }

    struct State {
        var latitude: Double
        var longitude: Double
        var style: YatmoMapStyle
        var isochrones: YatmoTravelMode?
        var poiTypeIds: [Int64]?
    }
}
