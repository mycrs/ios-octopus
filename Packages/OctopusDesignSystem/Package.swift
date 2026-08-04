// swift-tools-version: 5.9
import PackageDescription

// OctopusDesignSystem — renk/tipografi/aralık + tekrar eden UI bileşenleri.
// İş mantığı YOK. ViewModel bilmez. Domain'i yalnızca hata/entity SUNUMU için görür.
let package = Package(
    name: "OctopusDesignSystem",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "OctopusDesignSystem", targets: ["OctopusDesignSystem"])
    ],
    dependencies: [
        .package(path: "../OctopusCore"),
        .package(path: "../OctopusDomain")
        // Faz 4'te eklenecek (poster grid'leri gelince):
        // .package(url: "https://github.com/kean/Nuke", from: "12.0.0")
    ],
    targets: [
        .target(
            name: "OctopusDesignSystem",
            dependencies: [
                "OctopusCore",
                "OctopusDomain"
                // .product(name: "NukeUI", package: "Nuke")
            ]
        )
    ]
)
