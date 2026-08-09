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

    public init(
        playlists: PlaylistRepository,
        validator: PlaylistValidating,
        activation: ActivationRedeeming,
        sync: ContentSyncing
    ) {
        self.playlists = playlists
        self.validator = validator
        self.activation = activation
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
        ZStack {
            ambientGlow

            VStack(spacing: Theme.Spacing.xl) {
                // ⚠️ Üstteki boşluk **sınırlı**: iki serbest `Spacer` alanı
                // eşit paylaşınca içerik ekranın tam ortasına toplanıyor ve
                // tepede kocaman bir boşluk kalıyordu (kareyle görüldü).
                // Sınırlanınca içerik yukarı çekiliyor, düğme altta kalıyor —
                // gözün doğal okuma sırası.
                Spacer(minLength: 0)
                    .frame(maxHeight: 72)

                brand
                capabilities

                Spacer(minLength: Theme.Spacing.xl)
                startButton
            }
            .padding(Theme.Spacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Marka renginden gelen yumuşak parıltı.
    ///
    /// Referanstaki ambiyans katmanının karşılığı. Düz koyu bir zemin
    /// uygulamayı "yarım kalmış" gösteriyordu; parıltı marka rengini
    /// içerik gelmeden önce de hissettiriyor.
    private var ambientGlow: some View {
        RadialGradient(
            colors: [Theme.Palette.accent.opacity(0.22), .clear],
            center: .top,
            startRadius: 0,
            endRadius: 420
        )
        .ignoresSafeArea()
    }

    private var brand: some View {
        VStack(spacing: Theme.Spacing.md) {
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
        }
    }

    /// Ne alacağını baştan söyler.
    ///
    /// Kullanıcı kimlik bilgilerini girmeden önce karşılığını bilmeli —
    /// boş bir form "bu uygulama ne yapıyor?" sorusunu cevapsız bırakıyordu.
    private var capabilities: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            capability("tv", "Canlı TV", "Kategoriler, favoriler ve yayın akışı")
            capability("film", "Film ve dizi", "Kaldığın yerden devam et")
            capability("lock.shield", "Ebeveyn kilidi", "Yetişkin içeriği gizle")
        }
        .padding(.horizontal, Theme.Spacing.sm)
    }

    private func capability(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(Theme.Palette.accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(title)
                    .font(Theme.Typography.rowTitle)
                    .foregroundColor(Theme.Palette.textPrimary)
                Text(detail)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Palette.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var startButton: some View {
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
}
