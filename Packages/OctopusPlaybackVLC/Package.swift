// swift-tools-version: 5.9
import PackageDescription

// OctopusPlaybackVLC — VLCKit tabanlı motor. MPEG-TS / RTSP / UDP yayınlar için.
//
// ⚠️ VLCKit KASITLI OLARAK AYRI PAKETTE.
// Binary ~60MB ve SPM entegrasyonu kırılgan. Burada patlarsa uygulamanın
// geri kalanı etkilenmez; App bu modülü bağlamaktan vazgeçse bile derlenir.
let package = Package(
    name: "OctopusPlaybackVLC",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "OctopusPlaybackVLC", targets: ["OctopusPlaybackVLC"])
    ],
    dependencies: [
        .package(path: "../OctopusCore"),
        .package(path: "../OctopusDomain"),
        .package(path: "../OctopusPlayback")
        // Faz 5'te Mac'te eklenecek. Sürümü orada doğrula:
        // .package(url: "https://github.com/videolan/VLCKit", from: "4.0.0")
    ],
    targets: [
        .target(
            name: "OctopusPlaybackVLC",
            dependencies: [
                "OctopusCore",
                "OctopusDomain",
                "OctopusPlayback"
                // .product(name: "VLCKit", package: "VLCKit")
            ]
        )
    ]
)
