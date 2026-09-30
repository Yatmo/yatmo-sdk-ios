import SwiftUI
import YatmoSDK

struct ContentView: View {
    @ObservedObject private var testLog = TestLog.shared

    var body: some View {
        VStack(spacing: 0) {
            // UIKit view hosted by hand (the SwiftUI wrapper YatmoMap was checked on 2026-09-30 too) so the test can
            // select a POI annotation programmatically: the simulator offers no touch injection from the command line.
            if CommandLine.arguments.contains("-webview") {
                WebHost() // launched with `simctl launch <sim> com.yatmo.test.ios -webview`
            } else {
                MapHost()
                    .frame(height: 420)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(testLog.lines.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.system(size: 10, design: .monospaced))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
        }
        .task { await runCalls() }
    }

    private func step(_ name: String, _ block: () async throws -> String) async {
        do {
            testLog.log("OK \(name): \(try await block())")
        } catch {
            testLog.log("FAIL \(name): \(error)")
        }
    }

    private func runCalls() async {
        let client = yatmo.client
        testLog.log("appId=\(yatmo.configuration.appId) key=\(yatmo.configuration.licenseKey.prefix(6))...")
        await step("summary") {
            let s = try await client.summary(latitude: testLatitude, longitude: testLongitude)
            let first = s.categories.first
            let place = first?.subCategories.first?.places.first
            return "\(s.categories.count) categories, \(s.closeCities.count) cities, street=\(s.placeInformation?.streetName ?? "-"), first=\(first?.label ?? "-")/\(place?.name ?? "-") walk=\(place?.travel(.walking)?.travelTimeShortLabel ?? "-")"
        }
        await step("summaryText") {
            let t = try await client.summaryText(latitude: testLatitude, longitude: testLongitude)
            return "\(t.paragraphs.count) paragraphs, \(t.text.count) chars: \(t.text.prefix(80))"
        }
        await step("scores") {
            try await client.scores(latitude: testLatitude, longitude: testLongitude).scores.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
        }
        await step("enrichment") {
            let e = try await client.enrichment(latitude: testLatitude, longitude: testLongitude)
            let c = e.categories.first
            return "\(e.categories.count) categories, \(c?.key ?? "-") -> \(c?.nearest?.name ?? "-") \(c?.nearest?.walking?.durationMinutes ?? 0) min"
        }
        await step("geocode") {
            let p = try await client.geocode(query: "Rue Neuve", latitude: testLatitude, longitude: testLongitude)
            return "\(p.count) places, first=\(p.first?.label ?? "-")"
        }
        await step("simplifiedCategories") {
            try await client.simplifiedCategories().map { "\($0.name):\($0.poiTypeIds.count)" }.joined(separator: ", ")
        }
        await step("points") {
            let p = try await client.points(southWest: (50.848, 4.338), northEast: (50.856, 4.350))
            return "\(p.count) pois, first=\(p.first?.name ?? "-") icon=\(p.first?.iconIds ?? [])"
        }
        await step("isochrones") {
            try await client.isochrones(mode: .walking, latitude: testLatitude, longitude: testLongitude).map { "\($0.label):\($0.geometry?["type"] ?? "?")" }.joined(separator: ", ")
        }
        await step("pluginUrl") {
            YatmoWebViewOptions(latitude: testLatitude, longitude: testLongitude).url(configuration: yatmo.configuration).absoluteString
        }
        testLog.log("ALL CLIENT CALLS DONE")
    }
}

struct MapHost: UIViewRepresentable {
    func makeUIView(context: Context) -> YatmoMapView {
        let view = YatmoMapView(yatmo: yatmo, style: .liberty)
        view.onError = { error in TestLog.shared.log("MAP ERROR: \(error)") }
        view.onPoiSelected = { poi in TestLog.shared.log("POI TAP: \(poi.name) (\(poi.type))") }
        view.showProperty(latitude: testLatitude, longitude: testLongitude, zoom: 15)
        view.showIsochrones(mode: .walking)
        DispatchQueue.main.asyncAfter(deadline: .now() + 45) {
            let pois = (view.mapView.annotations ?? []).filter { $0.title != "property" }
            TestLog.shared.log("annotations on map: \(pois.count) pois")
            if let first = pois.first { view.mapView.selectAnnotation(first, animated: false, completionHandler: nil) }
            let layers = view.mapView.style?.layers.map(\.identifier).filter { $0.hasPrefix("yatmo") } ?? []
            TestLog.shared.log("yatmo layers: \(layers)")
        }
        return view
    }

    func updateUIView(_ uiView: YatmoMapView, context: Context) {}
}

struct WebHost: UIViewRepresentable {
    func makeUIView(context: Context) -> YatmoWebView {
        TestLog.shared.log("webview url: " + YatmoWebViewOptions(latitude: testLatitude, longitude: testLongitude, mode: .mapTop, zoom: 15, accentColor: "#428BFF").url(configuration: yatmo.configuration).absoluteString.components(separatedBy: "?")[0])
        return YatmoWebView(yatmo: yatmo, options: YatmoWebViewOptions(latitude: testLatitude, longitude: testLongitude, mode: .mapTop, zoom: 15, accentColor: "#428BFF"))
    }

    func updateUIView(_ uiView: YatmoWebView, context: Context) {}
}
