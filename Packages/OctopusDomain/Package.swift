// swift-tools-version: 5.9
import PackageDescription

// OctopusDomain — projenin kalbi.
// ⚠️ Buraya ASLA bağımlılık eklenmez. Sadece Foundation.
let package = Package(
    name: "OctopusDomain",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "OctopusDomain", targets: ["OctopusDomain"])
    ],
    targets: [
        .target(name: "OctopusDomain"),
        .testTarget(name: "OctopusDomainTests", dependencies: ["OctopusDomain"])
    ]
)
