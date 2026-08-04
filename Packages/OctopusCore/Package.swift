// swift-tools-version: 5.9
import PackageDescription

// OctopusCore — altyapı. İş mantığı YOK, bağımlılık YOK.
let package = Package(
    name: "OctopusCore",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "OctopusCore", targets: ["OctopusCore"])
    ],
    targets: [
        .target(name: "OctopusCore")
    ]
)
