// swift-tools-version: 5.9
import PackageDescription

// OctopusFeatures — her ekran ailesi AYRI target.
//
// ⚠️ DİKKAT: Bu pakette `OctopusData` bağımlılığı YOK ve asla eklenmeyecek.
// "Feature, Data'yı import edemez" kuralının fiziksel karşılığı budur.
// Feature'lar yalnızca Domain protokollerini görür; somut sınıfları App bağlar.
// Ayrıca hiçbir feature target'ı başka bir feature target'ına bağımlı değildir.

let shared: [Target.Dependency] = [
    .product(name: "OctopusCore", package: "OctopusCore"),
    .product(name: "OctopusDomain", package: "OctopusDomain"),
    .product(name: "OctopusDesignSystem", package: "OctopusDesignSystem"),
    .product(name: "OctopusNavigation", package: "OctopusNavigation")
]

let sharedWithPlayback: [Target.Dependency] = shared + [
    .product(name: "OctopusPlayback", package: "OctopusPlayback")
]

let package = Package(
    name: "OctopusFeatures",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "FeatureOnboarding", targets: ["FeatureOnboarding"]),
        .library(name: "FeatureHome", targets: ["FeatureHome"]),
        .library(name: "FeatureLive", targets: ["FeatureLive"]),
        .library(name: "FeatureVOD", targets: ["FeatureVOD"]),
        .library(name: "FeatureSeries", targets: ["FeatureSeries"]),
        .library(name: "FeatureSearch", targets: ["FeatureSearch"]),
        .library(name: "FeatureFavorites", targets: ["FeatureFavorites"]),
        .library(name: "FeaturePlayer", targets: ["FeaturePlayer"]),
        .library(name: "FeatureSettings", targets: ["FeatureSettings"])
    ],
    dependencies: [
        .package(path: "../OctopusCore"),
        .package(path: "../OctopusDomain"),
        .package(path: "../OctopusDesignSystem"),
        .package(path: "../OctopusNavigation"),
        .package(path: "../OctopusPlayback")
    ],
    targets: [
        .target(name: "FeatureOnboarding", dependencies: shared),
        .target(name: "FeatureHome", dependencies: shared),
        .target(name: "FeatureLive", dependencies: shared),
        .target(name: "FeatureVOD", dependencies: shared),
        .target(name: "FeatureSeries", dependencies: shared),
        .target(name: "FeatureSearch", dependencies: shared),
        .target(name: "FeatureFavorites", dependencies: shared),
        .target(name: "FeaturePlayer", dependencies: sharedWithPlayback),
        .target(name: "FeatureSettings", dependencies: shared),

        // ⚠️ Yeni bir feature'a test eklenirse .github/workflows/ci.yml
        // içindeki paket listesine de eklenmeli — aksi halde test yazılmış
        // ama hiç koşmamış olur. Bkz. Docs/BRAIN.md § 10.
        .testTarget(name: "FeatureOnboardingTests", dependencies: ["FeatureOnboarding"]),
        .testTarget(name: "FeatureSettingsTests", dependencies: ["FeatureSettings"]),
        .testTarget(name: "FeatureLiveTests", dependencies: ["FeatureLive"]),
        .testTarget(name: "FeatureVODTests", dependencies: ["FeatureVOD"]),
        .testTarget(name: "FeatureSeriesTests", dependencies: ["FeatureSeries"]),
        .testTarget(name: "FeatureFavoritesTests", dependencies: ["FeatureFavorites"]),
        .testTarget(name: "FeatureHomeTests", dependencies: ["FeatureHome"]),
        .testTarget(name: "FeatureSearchTests", dependencies: ["FeatureSearch"]),
        .testTarget(name: "FeaturePlayerTests", dependencies: ["FeaturePlayer"])
    ]
)
