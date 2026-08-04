// swift-tools-version: 5.9
import PackageDescription

// OctopusNavigation — Route + Router. Feature'ların birbirini görmeden geçiş yapmasını sağlar.
let package = Package(
    name: "OctopusNavigation",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "OctopusNavigation", targets: ["OctopusNavigation"])
    ],
    dependencies: [
        .package(path: "../OctopusDomain")
    ],
    targets: [
        .target(name: "OctopusNavigation", dependencies: ["OctopusDomain"])
    ]
)
