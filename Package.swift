// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "YatmoSDK",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(name: "YatmoSDK", targets: ["YatmoSDK"])
    ],
    dependencies: [
        // MapLibre Native for iOS: reads the same Mapbox / MapLibre style JSON as the Yatmo web plugin.
        .package(url: "https://github.com/maplibre/maplibre-gl-native-distribution", from: "6.0.0")
    ],
    targets: [
        .target(
            name: "YatmoSDK",
            dependencies: [
                .product(name: "MapLibre", package: "maplibre-gl-native-distribution")
            ],
            path: "Sources/YatmoSDK"
        )
    ]
)
