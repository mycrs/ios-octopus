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
        .package(path: "../OctopusPlayback"),
        // ⚠️ NEDEN videolan/VLCKit DEĞİL: resmî depoda `Package.swift` yok
        // (4.0.0a21 dahil hiçbir etikette), yani SPM ile çözülemiyor. Resmî
        // dağıtım CocoaPods/tarball üzerinden ve bu proje SPM + XcodeGen.
        // Bu depo aynı VLCKit binary'sini checksum'lı bir XCFramework olarak
        // paketliyor; iOS'ta `MobileVLCKit`'i yeniden dışa aktarır.
        .package(url: "https://github.com/tylerjonesio/vlckit-spm", .upToNextMajor(from: "3.6.0"))
    ],
    targets: [
        .target(
            name: "OctopusPlaybackVLC",
            dependencies: [
                "OctopusCore",
                "OctopusDomain",
                "OctopusPlayback",
                .product(name: "VLCKitSPM", package: "vlckit-spm")
            ]
        )
    ]
)
