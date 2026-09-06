// swift-tools-version: 5.9
import PackageDescription

// OctopusDomain — projenin kalbi.
// ⚠️ Buraya ASLA bağımlılık eklenmez. Sadece Foundation.
let package = Package(
    name: "OctopusDomain",
    // ⚠️ macOS yalnızca `swift test` için. Paket sadece iOS'a hedeflenince
    // testler macOS varsayılanıyla (10.13) derleniyor ve AsyncStream
    // bulunamıyordu; şemada da test hedefi olmadığı için Domain testleri
    // **hiçbir yerden** koşmuyordu. Uygulama derlemesini etkilemez.
    //
    // Yalnızca burada yapılabiliyor: diğer paketler UIKit'e bağlı, macOS'ta
    // hiç derlenemezler. Domain'in saflığı (yalnız Foundation) bunu mümkün
    // kılan şey — demir kural 1'in beklenmedik bir kazancı.
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "OctopusDomain", targets: ["OctopusDomain"])
    ],
    targets: [
        .target(name: "OctopusDomain"),
        .testTarget(name: "OctopusDomainTests", dependencies: ["OctopusDomain"])
    ]
)
