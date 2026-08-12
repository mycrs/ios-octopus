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

    /// Bayi kodunu panele sorar ve kaydeder. `true` → kod bulundu.
    ///
    /// Kapanış olarak alınıyor: feature modülü panel servisini de tema
    /// denetleyicisini de tanımaz, yalnızca "kodu uygula" der.
    public let applyResellerCode: @MainActor (String) async -> Bool

    /// Kayıtlı bayi kodu — alan bununla doldurulur.
    public let savedResellerCode: @MainActor () async -> String?

    /// Bayinin sunucu listesi.
    ///
    /// ⚠️ IPTV desteğinde en sık gelen şikâyet yanlış yazılmış sunucu
    /// adresidir. Bayi kodu girilmişse adres yazdırmak yerine liste sunulur.
    public let resellerServers: @MainActor () async -> [ResellerServer]

    /// Karşılama ekranında gösterilecek marka adı (bayi varsa onunki).
    public let brandName: @MainActor () -> String?
    /// Karşılama ekranındaki logo (bayi varsa onunki).
    public let brandLogoURL: @MainActor () -> URL?

    public init(
        playlists: PlaylistRepository,
        validator: PlaylistValidating,
        activation: ActivationRedeeming,
        sync: ContentSyncing,
        isManualLoginEnabled: @escaping @MainActor () -> Bool = { true },
        onBrandingResolved: @escaping @MainActor (BrandConfiguration) -> Void = { _ in },
        applyResellerCode: @escaping @MainActor (String) async -> Bool = { _ in false },
        savedResellerCode: @escaping @MainActor () async -> String? = { nil },
        resellerServers: @escaping @MainActor () async -> [ResellerServer] = { [] },
        brandName: @escaping @MainActor () -> String? = { nil },
        brandLogoURL: @escaping @MainActor () -> URL? = { nil }
    ) {
        self.resellerServers = resellerServers
        self.brandName = brandName
        self.brandLogoURL = brandLogoURL
        self.onBrandingResolved = onBrandingResolved
        self.applyResellerCode = applyResellerCode
        self.savedResellerCode = savedResellerCode
        self.playlists = playlists
        self.validator = validator
        self.activation = activation
        self.sync = sync
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
    @State private var showsResellerCode = false
    @State private var savedCode: String?

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

                        Spacer(minLength: Theme.Spacing.xl)
                        startButton
                        OnboardingResellerCodeButton(savedCode: savedCode) {
                            showsResellerCode = true
                        }
                    }
                    .padding(Theme.Spacing.xl)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height)
                }
            }
        }
        .task { savedCode = await dependencies.savedResellerCode() }
        .sheet(isPresented: $showsResellerCode) {
            ResellerCodeSheet(currentCode: savedCode) { code in
                let isValid = await dependencies.applyResellerCode(code)
                savedCode = await dependencies.savedResellerCode()
                return isValid
            }
        }
    }

    private var startButton: some View {
        OnboardingSubmitButton(title: "Kuruluma başla", isEnabled: true) {
            showsForm = true
        }
    }
}
