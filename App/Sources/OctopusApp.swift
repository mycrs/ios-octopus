import SwiftUI

/// 🎬 Uygulamanın giriş noktası.
///
/// ⚠️ BU DOSYA İNCE KALIR. Kural: **40 satırı geçmez.**
/// Buraya iş mantığı, ekran kurulumu veya bağımlılık ayarı yazılmaz.
/// - Bağlama işi → `Composition/AppContainer.swift`
/// - Ekran yapısı → `Composition/RootView.swift`
/// - Yeni özellik → ilgili `Packages/OctopusFeatures/Sources/FeatureXxx`
@main
struct OctopusApp: App {

    @StateObject private var container = AppContainer()

    init() {
        Appearance.apply()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(container)
                .environmentObject(container.router)
                .preferredColorScheme(.dark)   // IPTV arayüzü koyu temada yaşar
                .task { await container.bootstrap() }
        }
    }
}
