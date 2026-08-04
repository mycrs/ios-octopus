// swift-tools-version: 5.9
import PackageDescription

// OctopusData — Xtream/M3U provider'ları, parser'lar, kalıcılık, Repository impl'leri.
// GRDB burada hapsedilir; başka hiçbir modül SQLite görmez.
let package = Package(
    name: "OctopusData",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "OctopusData", targets: ["OctopusData"])
    ],
    dependencies: [
        .package(path: "../OctopusCore"),
        .package(path: "../OctopusDomain"),
        // SQLite katmanı. Bu bağımlılık YALNIZCA bu modülde bulunur —
        // hiçbir Feature, Domain veya App dosyası GRDB görmez.
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0")
    ],
    targets: [
        .target(
            name: "OctopusData",
            dependencies: [
                "OctopusCore",
                "OctopusDomain",
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .testTarget(name: "OctopusDataTests", dependencies: ["OctopusData"])
    ]
)
