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
    /// Bayi aktivasyon kodunu gerçek erişim bilgilerine çevirir.
    public let activation: ActivationRedeeming
    public let sync: ContentSyncing
    /// Kaynağı etkinleştirir ve varsa hızlı kurulum liste PIN'ini güvenli saklar.
    public let activatePlaylist: @MainActor (Playlist.ID, String?) async throws -> Void
    /// Açık örnek içeriği ayrı bir kaynağa kurar ve etkinleştirir.
    public let installSampleLibrary: (@MainActor () async throws -> Void)?

    /// Panel elle girişe (Xtream/M3U formu) izin veriyor mu?
    ///
    /// ⚠️ Kapanış olarak alınıyor, düz `Bool` olarak değil: panel
    /// yapılandırması ekran açıldıktan **sonra** gelebiliyor. Sabit bir
    /// değer kopyalansaydı ilk açılışta hep varsayılan görünürdü.
    public let isManualLoginEnabled: @MainActor () -> Bool

    /// Aktivasyon kodu bayinin markasını da getiriyor (renk, ad, logo).
    ///
    /// ⚠️ Bu bilgi ayrıştırılıyordu ama **hiçbir yere uygulanmıyordu**:
    /// bayinin rengi yalnızca `app-config` üzerinden gelirse geçerliydi,
    /// koda gömülü marka yok sayılıyordu. Kapanış olarak alınıyor ki
    /// feature modülü tema denetleyicisini tanımak zorunda kalmasın.
    public let onBrandingResolved: @MainActor (BrandConfiguration) -> Void

    /// Karşılama ekranında gösterilecek marka adı (bayi varsa onunki).
    public let brandName: @MainActor () -> String?
    /// Karşılama ekranındaki logo (bayi varsa onunki).
    public let brandLogoURL: @MainActor () -> URL?

    public init(
        playlists: PlaylistRepository,
        validator: PlaylistValidating,
        activation: ActivationRedeeming,
        sync: ContentSyncing,
        activatePlaylist: (@MainActor (Playlist.ID, String?) async throws -> Void)? = nil,
        isManualLoginEnabled: @escaping @MainActor () -> Bool = { true },
        onBrandingResolved: @escaping @MainActor (BrandConfiguration) -> Void = { _ in },
        brandName: @escaping @MainActor () -> String? = { nil },
        brandLogoURL: @escaping @MainActor () -> URL? = { nil },
        installSampleLibrary: (@MainActor () async throws -> Void)? = nil
    ) {
        self.brandName = brandName
        self.brandLogoURL = brandLogoURL
        self.onBrandingResolved = onBrandingResolved
        self.playlists = playlists
        self.validator = validator
        self.activation = activation
        self.sync = sync
        self.activatePlaylist = activatePlaylist ?? { id, _ in
            try await playlists.setActive(id: id)
        }
        self.installSampleLibrary = installSampleLibrary
        self.isManualLoginEnabled = isManualLoginEnabled
    }
}

/// Kaynak ekleme akışının giriş noktası.
///
/// İlk açılışta karşılama gösterilir; kullanıcı başlayınca forma geçilir.
public struct OnboardingScreen: View {

    private let dependencies: OnboardingDependencies
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var theme: ThemeController
    @State private var showsForm = false
    @State private var showsSampleLibrary = false

    public init(dependencies: OnboardingDependencies) {
        self.dependencies = dependencies
#if DEBUG
        _showsForm = State(initialValue: OnboardingDebugLaunch.opensForm)
#endif
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
        .sheet(isPresented: $showsSampleLibrary) {
            if let install = dependencies.installSampleLibrary {
                NavigationStack {
                    SampleLibraryOnboardingScreen(install: install) {
                        showsSampleLibrary = false
                        router.needsOnboarding = false
                    }
                }
            }
        }
    }

    private var welcome: some View {
        ZStack {
            OnboardingBackgroundGlow(opacity: 0.22, center: .top, endRadius: 420)

            GeometryReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: Theme.Spacing.xl) {
                        Spacer(minLength: 0)
                            .frame(maxHeight: 72)

                        OnboardingWelcomeBrand(
                            brandName: theme.resellerName ?? dependencies.brandName() ?? "Octopus",
                            logoURL: theme.logoURL ?? dependencies.brandLogoURL()
                        )
                        OnboardingCapabilities()
                        OnboardingContentDisclaimer()
                        AppPolicyLinks()

                        Spacer(minLength: Theme.Spacing.xl)
                    }
                    .padding(Theme.Spacing.xl)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height)
                }
            }
        }
        .safeAreaInset(edge: .bottom) { welcomeActions }
    }

    private var welcomeActions: some View {
        VStack(spacing: Theme.Spacing.sm) {
            startButton
            if dependencies.installSampleLibrary != nil {
                Button {
                    showsSampleLibrary = true
                } label: {
                    Label("Örnek kütüphaneyi keşfet", systemImage: "books.vertical")
                        .font(Theme.Typography.rowSubtitle)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .tint(theme.accent)
                .accessibilityIdentifier("sample-library.open")
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .background(Theme.Palette.background.opacity(0.96))
    }

    private var startButton: some View {
        OnboardingSubmitButton(title: "Kuruluma başla", isEnabled: true) {
            showsForm = true
        }
    }
}
