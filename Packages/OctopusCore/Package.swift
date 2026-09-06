// swift-tools-version: 5.9
import PackageDescription

// OctopusCore — altyapı. İş mantığı YOK, bağımlılık YOK.
let package = Package(
    name: "OctopusCore",
    // macOS yalnızca `swift test` için — bkz. OctopusDomain/Package.swift.
    // Bu paket UIKit'e bağlı olmadığı için mümkün; testleri başka türlü
    // hiçbir yerden koşmuyordu.
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "OctopusCore", targets: ["OctopusCore"])
    ],
    targets: [
        .target(name: "OctopusCore")
    ]
)
