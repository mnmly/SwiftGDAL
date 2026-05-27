// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftGDAL",
    platforms: [
        .macOS("13.3"),
        .iOS("17.0"),
    ],
    products: [
        .library(
            name: "SwiftGDAL",
            targets: ["SwiftGDAL"]
        ),
        .library(
            name: "SwiftGDAL Dynamic",
            type: .dynamic,
            targets: ["SwiftGDAL"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.3"),
    ],
    targets: [
        // GDAL ships as an xcframework with a macOS dynamic framework and
        // static iOS slices. All three slices carry their own
        // Modules/module.modulemap (set up upstream in
        // gdal-xcframework-builder), so `import gdal` works uniformly.
        //
        // For local iteration, swap each `.binaryTarget` below to
        // `path: "Frameworks/<name>.xcframework"` and rebuild via
        // gdal-xcframework-builder.
        .binaryTarget(
            name: "gdal",
            url: "https://github.com/mnmly/gdal-xcframework-builder/releases/download/gdal-3.12.4-r2/gdal.xcframework.zip",
            checksum: "2d935c5a83f39e7cdde40116bf3fb1531b672911b3d60c785465a84723b9381c"
        ),

        // PROJ is needed on iOS only — the macOS GDAL framework bundles
        // libproj.dylib inside Libraries/. Gated by `.when(platforms:)` below.
        .binaryTarget(
            name: "proj",
            url: "https://github.com/mnmly/gdal-xcframework-builder/releases/download/gdal-3.12.4-r2/proj.xcframework.zip",
            checksum: "13cf2c5ecfad1aee5e7dd333752c44ba13b160ae8e29a08869c3ffbc3bbdda73"
        ),

        .target(
            name: "SwiftGDAL",
            dependencies: [
                "gdal",
                .target(name: "proj", condition: .when(platforms: [.iOS])),
            ],
            resources: [
                .copy("Resources/proj.db"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),

        .testTarget(
            name: "SwiftGDALTests",
            dependencies: ["SwiftGDAL"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .define("SWIFTGDAL_TESTING"),
            ]
        ),

        // Tiny CLI demo. Run with:
        //   swift run gdalinfo <path/to/raster>
        .executableTarget(
            name: "gdalinfo",
            dependencies: ["SwiftGDAL"],
            path: "Examples/gdalinfo",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
