import Foundation
import UIKit
import MapLibre

/// A MapLibre map preconfigured with a Yatmo style, the property pin, POI markers that follow the camera,
/// and optional isochrones. The SDK draws no popup: handle `onPoiSelected` with your own UI.
public final class YatmoMapView: UIView, MLNMapViewDelegate {

    // MARK: Public surface

    public let yatmo: Yatmo
    /// The underlying MapLibre map, for camera animations, gesture options or your own annotations.
    public let mapView: MLNMapView

    /// Restrict the POIs to some categories (ids from `client.simplifiedCategories()`). Nil = all.
    public var poiTypeIds: [Int64]? { didSet { reloadPois() } }
    /// Marker size in points, 24 or 32 (icons exist for both).
    public var poiIconSize: CGFloat = 24
    /// No POI request below this zoom.
    public var minZoomForPois: Double = 13
    /// Called when a POI marker is tapped.
    public var onPoiSelected: ((YatmoPoi) -> Void)?
    /// Network or licence errors while loading POIs or isochrones.
    public var onError: ((Error) -> Void)?
    /// Like the web plugin: once the isochrones are drawn, the camera fits the largest area, and `hideIsochrones()`
    /// restores the previous camera.
    public var fitIsochrones = true
    /// Padding around the isochrones when the camera fits them, in points.
    public var isochronePadding = UIEdgeInsets(top: 40, left: 40, bottom: 40, right: 40)
    /// Fill colour of the isochrones, from the smallest area to the largest. Same palette as the web plugin
    /// (5 min blue, 10 min orange, 20 min pink); the outline takes the same colour, opaque.
    public var isochroneColors: [UIColor] = [
        UIColor(red: 0.44, green: 0.68, blue: 0.94, alpha: 0.5),
        UIColor(red: 0.96, green: 0.65, blue: 0.14, alpha: 0.4),
        UIColor(red: 0.94, green: 0.26, blue: 0.50, alpha: 0.3)
    ]

    public init(yatmo: Yatmo, style: YatmoMapStyle = .liberty, frame: CGRect = .zero) {
        self.yatmo = yatmo
        self.mapView = MLNMapView(frame: frame, styleURL: style.url)
        super.init(frame: frame)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mapView.frame = bounds
        mapView.delegate = self
        mapView.logoView.isHidden = true
        mapView.attributionButton.isHidden = false
        addSubview(mapView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("YatmoMapView is created in code") }

    /// Centres the map on the property and drops the pin.
    public func showProperty(latitude: Double, longitude: Double, zoom: Double = 15, animated: Bool = false) {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        if let pin = propertyAnnotation { mapView.removeAnnotation(pin) }
        let pin = MLNPointAnnotation()
        pin.coordinate = coordinate
        pin.title = "property"
        propertyAnnotation = pin
        mapView.addAnnotation(pin)
        mapView.setCenter(coordinate, zoomLevel: zoom, animated: animated)
        propertyCoordinate = coordinate
        cameraBeforeIsochrones = nil // the camera to restore is the one centred on the new property
        if let mode = isochroneMode { showIsochrones(mode: mode) }
    }

    /// Changes the basemap style.
    public func setStyle(_ style: YatmoMapStyle) {
        mapView.styleURL = style.url
    }

    /// Draws the 5, 10 and 20 minute areas around the property for the given mode.
    public func showIsochrones(mode: YatmoTravelMode) {
        isochroneMode = mode
        guard let coordinate = propertyCoordinate else { return }
        let requestId = UUID()
        isochroneRequestId = requestId
        Task { [weak self] in
            guard let self else { return }
            do {
                let isochrones = try await self.yatmo.client.isochrones(mode: mode, latitude: coordinate.latitude, longitude: coordinate.longitude)
                await MainActor.run {
                    guard self.isochroneRequestId == requestId else { return }
                    self.render(isochrones: isochrones)
                    if self.fitIsochrones, let largest = isochrones.last, let bounds = Self.bounds(of: largest) {
                        if self.cameraBeforeIsochrones == nil { self.cameraBeforeIsochrones = self.mapView.camera }
                        self.mapView.setVisibleCoordinateBounds(bounds, edgePadding: self.isochronePadding, animated: true, completionHandler: nil)
                    }
                }
            } catch {
                await MainActor.run { self.onError?(error) }
            }
        }
    }

    public func hideIsochrones() {
        isochroneMode = nil
        isochroneRequestId = nil
        removeIsochroneLayers()
        if let camera = cameraBeforeIsochrones {
            cameraBeforeIsochrones = nil
            mapView.setCamera(camera, animated: true)
        }
    }

    /// Bounding box of a GeoJSON Polygon or MultiPolygon, whatever its nesting depth.
    static func bounds(of isochrone: YatmoIsochrone) -> MLNCoordinateBounds? {
        guard let geometry = isochrone.geometry, let coordinates = geometry["coordinates"] else { return nil }
        var minLat = 90.0, maxLat = -90.0, minLng = 180.0, maxLng = -180.0
        func walk(_ node: Any) {
            guard let array = node as? [Any] else { return }
            if array.count >= 2, let lng = array[0] as? Double, let lat = array[1] as? Double {
                minLat = min(minLat, lat); maxLat = max(maxLat, lat); minLng = min(minLng, lng); maxLng = max(maxLng, lng)
            } else {
                array.forEach(walk)
            }
        }
        walk(coordinates)
        guard minLat <= maxLat, minLng <= maxLng else { return nil }
        return MLNCoordinateBounds(sw: CLLocationCoordinate2D(latitude: minLat, longitude: minLng), ne: CLLocationCoordinate2D(latitude: maxLat, longitude: maxLng))
    }

    /// Forces a POI reload for the current viewport.
    public func reloadPois() {
        scheduleLoadPois(delay: 0)
    }

    // MARK: Internals

    private var propertyAnnotation: MLNPointAnnotation?
    private var propertyCoordinate: CLLocationCoordinate2D?
    private var isochroneMode: YatmoTravelMode?
    private var isochroneRequestId: UUID?
    private var cameraBeforeIsochrones: MLNMapCamera?
    private var poiAnnotations: [String: YatmoPoiAnnotation] = [:]
    private var poiTask: Task<Void, Never>?
    private var styleLoaded = false

    private static let isochroneSourceId = "yatmo-isochrones"
    private static let isochroneLayerId = "yatmo-isochrones-fill"
    private static let isochroneLineLayerId = "yatmo-isochrones-line"

    private func scheduleLoadPois(delay: TimeInterval = 0.3) {
        poiTask?.cancel()
        guard styleLoaded, mapView.zoomLevel >= minZoomForPois else {
            if mapView.zoomLevel < minZoomForPois { removeAllPois() }
            return
        }
        let bounds = mapView.visibleCoordinateBounds
        let ids = poiTypeIds
        poiTask = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            guard !Task.isCancelled, let self else { return }
            do {
                let pois = try await self.yatmo.client.points(
                    southWest: (bounds.sw.latitude, bounds.sw.longitude),
                    northEast: (bounds.ne.latitude, bounds.ne.longitude),
                    poiTypeIds: ids)
                guard !Task.isCancelled else { return }
                await MainActor.run { self.merge(pois: pois) }
            } catch is CancellationError {
            } catch {
                await MainActor.run { self.onError?(error) }
            }
        }
    }

    /// Diff-merge like the web plugin: keep the markers already on the map, add the new ones, drop the ones out of view.
    private func merge(pois: [YatmoPoi]) {
        let incoming = Dictionary(uniqueKeysWithValues: pois.map { ($0.id, $0) })
        let stale = poiAnnotations.filter { incoming[$0.key] == nil }
        mapView.removeAnnotations(Array(stale.values))
        stale.keys.forEach { poiAnnotations.removeValue(forKey: $0) }
        let fresh = pois.filter { poiAnnotations[$0.id] == nil }.map { poi -> YatmoPoiAnnotation in
            let annotation = YatmoPoiAnnotation(poi: poi)
            poiAnnotations[poi.id] = annotation
            return annotation
        }
        mapView.addAnnotations(fresh)
    }

    private func removeAllPois() {
        mapView.removeAnnotations(Array(poiAnnotations.values))
        poiAnnotations.removeAll()
    }

    private func render(isochrones: [YatmoIsochrone]) {
        guard let style = mapView.style else { return }
        removeIsochroneLayers()
        // Largest area first so the smaller ones are drawn on top. The API returns bare geometries: MLNShape(data:)
        // turns those into plain MLNPolygon objects, which carry no attributes, so wrap each one in a GeoJSON Feature.
        let features: [MLNShape & MLNFeature] = isochrones.reversed().enumerated().compactMap { index, isochrone in
            guard let geometry = try? JSONSerialization.jsonObject(with: isochrone.geometryJSON) else { return nil }
            let feature: [String: Any] = ["type": "Feature", "properties": ["rank": isochrones.count - 1 - index, "label": isochrone.label], "geometry": geometry]
            guard let data = try? JSONSerialization.data(withJSONObject: feature),
                  let shape = try? MLNShape(data: data, encoding: String.Encoding.utf8.rawValue) as? (MLNShape & MLNFeature) else { return nil }
            return shape
        }
        let source = MLNShapeSource(identifier: Self.isochroneSourceId, features: features, options: nil)
        style.addSource(source)
        let fill = MLNFillStyleLayer(identifier: Self.isochroneLayerId, source: source)
        let colors = isochroneColors
        let stops: [NSNumber: UIColor] = Dictionary(uniqueKeysWithValues: (0..<max(colors.count, 1)).map { (NSNumber(value: $0), colors[min($0, colors.count - 1)]) })
        fill.fillColor = NSExpression(format: "mgl_step:from:stops:(rank, %@, %@)", colors.first ?? UIColor.systemBlue.withAlphaComponent(0.2), stops)
        let line = MLNLineStyleLayer(identifier: Self.isochroneLineLayerId, source: source)
        let lineStops: [NSNumber: UIColor] = stops.mapValues { $0.withAlphaComponent(1) }
        line.lineColor = NSExpression(format: "mgl_step:from:stops:(rank, %@, %@)", (colors.first ?? UIColor.systemBlue).withAlphaComponent(1), lineStops)
        line.lineWidth = NSExpression(forConstantValue: 3)
        // Under the labels of the basemap when possible.
        if let firstSymbol = style.layers.first(where: { $0 is MLNSymbolStyleLayer }) {
            style.insertLayer(fill, below: firstSymbol)
            style.insertLayer(line, below: firstSymbol)
        } else {
            style.addLayer(fill)
            style.addLayer(line)
        }
    }

    private func removeIsochroneLayers() {
        guard let style = mapView.style else { return }
        if let layer = style.layer(withIdentifier: Self.isochroneLineLayerId) { style.removeLayer(layer) }
        if let layer = style.layer(withIdentifier: Self.isochroneLayerId) { style.removeLayer(layer) }
        if let source = style.source(withIdentifier: Self.isochroneSourceId) { style.removeSource(source) }
    }

    // MARK: MLNMapViewDelegate

    public func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
        styleLoaded = true
        scheduleLoadPois(delay: 0)
        if let mode = isochroneMode { showIsochrones(mode: mode) }
    }

    public func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
        scheduleLoadPois()
    }

    public func mapView(_ mapView: MLNMapView, viewFor annotation: MLNAnnotation) -> MLNAnnotationView? {
        if let poiAnnotation = annotation as? YatmoPoiAnnotation {
            let reuseId = "yatmo-poi"
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: reuseId) as? YatmoPoiAnnotationView)
                ?? YatmoPoiAnnotationView(reuseIdentifier: reuseId)
            view.configure(poi: poiAnnotation.poi, country: yatmo.configuration.country, size: poiIconSize)
            return view
        }
        if annotation === propertyAnnotation {
            let reuseId = "yatmo-property"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: reuseId) ?? MLNAnnotationView(reuseIdentifier: reuseId)
            if view.subviews.isEmpty {
                view.frame = CGRect(x: 0, y: 0, width: 28, height: 28)
                let pin = UIView(frame: view.bounds)
                pin.backgroundColor = UIColor(red: 0.26, green: 0.55, blue: 1.0, alpha: 1)
                pin.layer.cornerRadius = 14
                pin.layer.borderWidth = 3
                pin.layer.borderColor = UIColor.white.cgColor
                pin.layer.shadowColor = UIColor.black.cgColor
                pin.layer.shadowOpacity = 0.3
                pin.layer.shadowOffset = CGSize(width: 0, height: 2)
                view.addSubview(pin)
            }
            return view
        }
        return nil
    }

    public func mapView(_ mapView: MLNMapView, annotationCanShowCallout annotation: MLNAnnotation) -> Bool { false }

    public func mapView(_ mapView: MLNMapView, didSelect annotation: MLNAnnotation) {
        if let poiAnnotation = annotation as? YatmoPoiAnnotation {
            onPoiSelected?(poiAnnotation.poi)
            mapView.deselectAnnotation(annotation, animated: false)
        }
    }
}

/// Annotation carrying the POI payload.
final class YatmoPoiAnnotation: MLNPointAnnotation {
    let poi: YatmoPoi

    init(poi: YatmoPoi) {
        self.poi = poi
        super.init()
        coordinate = CLLocationCoordinate2D(latitude: poi.latitude, longitude: poi.longitude)
        title = poi.name
        subtitle = poi.type
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

/// Marker view showing the POI icon from the CDN (first icon when several POIs share the spot).
final class YatmoPoiAnnotationView: MLNAnnotationView {
    private let imageView = UIImageView()
    private var currentURL: URL?
    private static let cache = NSCache<NSURL, UIImage>()

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(poi: YatmoPoi, country: YatmoCountry, size: CGFloat) {
        frame = CGRect(x: 0, y: 0, width: size, height: size)
        imageView.frame = bounds
        guard let iconId = poi.iconIds.first else { imageView.image = nil; return }
        let url = YatmoCdn.iconURL(country: country, iconId: iconId, size: size >= 32 ? 32 : 24)
        currentURL = url
        if let cached = Self.cache.object(forKey: url as NSURL) {
            imageView.image = cached
            return
        }
        imageView.image = nil
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = UIImage(data: data, scale: 2) else { return }
            Self.cache.setObject(image, forKey: url as NSURL)
            DispatchQueue.main.async {
                guard let self, self.currentURL == url else { return }
                self.imageView.image = image
            }
        }.resume()
    }
}
