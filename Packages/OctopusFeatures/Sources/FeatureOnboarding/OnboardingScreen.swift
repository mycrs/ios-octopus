import SwiftUI
import OctopusDomain
import OctopusDesignSystem
import OctopusNavigation

/// Bu feature'ın ihtiyaç duyduğu her şey.
///
/// ⚠️ KALIP: Her feature bağımlılıklarını **protokol** olarak burada beyan eder.
/// Somut tipleri (`XtreamContentProvider`, `GRDBPlaylistRepository`…) görmez.
/// Bağlama işi yalnızca `AppContainer`'da yapılır.
public struct OnboardingDependencies {
    public let playlists: PlaylistRepository
    /// Kaynağı **kaydetmeden önce** doğrular — hatalı bilgiyle kayıt oluşmasın.
    public let validator: PlaylistValidating
    public let sync: ContentSyncing

    public init(
        playlists: PlaylistRepository,
        validator: PlaylistValidating,
        sync: ContentSyncing
    ) {
        self.playlists = playlists
        self.validator = validator
        self.sync = sync
    }
}

/// Kaynak ekleme akışının giriş noktası.
///
/// İlk açılışta karşılama gösterilir; kullanıcı başlayınca forma geçilir.
public struct OnboardingScreen: View {

    private let dependencies: OnboardingDependencies
    @EnvironmentObject private var router: AppRouter
    @State private var showsForm = false

    public init(dependencies: OnboardingDependencies) {
        self.dependencies = dependencies
    }

    public var body: some View {
        ZStack {
            // ⚠️ `ignoresSafeArea()` şart: yalnızca `.background(...)` verilirse
            // renk güvenli alanla sınırlı kalır ve durum çubuğu ile ana ekran
            // göstergesi bölgesi sistem siyahında görünür — ekran ortada
            // "kutu içinde" duruyormuş gibi olur.
            Theme.Palette.background.ignoresSafeArea()

            if showsForm {
                AddPlaylistView(dependencies: dependencies) {
                    // Kaynak eklendi ve senkronize oldu; ana ekrana geç.
                    router.needsOnboarding = false
                }
            } else {
                welcome
            }
        }
    }

    private var welcome: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()

            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 56))
                .foregroundColor(Theme.Palette.accent)

            VStack(spacing: Theme.Spacing.sm) {
                Text("Octopus")
                    .font(Theme.Typography.screenTitle)
                    .foregroundColor(Theme.Palette.textPrimary)

                Text("Xtream hesabını veya M3U bağlantını ekleyerek başla.")
                    .font(Theme.Typography.rowSubtitle)
                    .foregroundColor(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Button {
                showsForm = true
            } label: {
                Text("Kaynak ekle")
                    .font(Theme.Typography.rowTitle)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.md)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.Palette.accent)
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
