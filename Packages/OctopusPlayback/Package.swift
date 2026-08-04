// swift-tools-version: 5.9
import PackageDescription

// OctopusPlayback — PlaybackEngine protokolü + AVPlayer implementasyonu + motor seçici.
// 3rd-party bağımlılığı YOK; VLC ayrı pakette izole.
let package = Package(
    name: "OctopusPlayback",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "OctopusPlayback", targets: ["OctopusPlayback"])
    ],
    dependencies: [
        .package(path: "../OctopusCore"),
        .package(path: "../OctopusDomain")
    ],
    targets: [
        .target(name: "OctopusPlayback", dependencies: ["OctopusCore", "OctopusDomain"]),
        .testTarget(name: "OctopusPlaybackTests", dependencies: ["OctopusPlayback"])
    ]
)
