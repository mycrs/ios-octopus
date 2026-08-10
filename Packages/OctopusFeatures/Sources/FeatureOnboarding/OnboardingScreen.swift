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
    @State private var showsForm = false
    @State private var showsResellerCode = false
    @State private var savedCode: String?

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
                resellerCodeButton
            }
            .padding(Theme.Spacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    /// İkincil eylem — asıl akış kaynak eklemek.
    ///
    /// ⚠️ Bayi kodu **zorunlu değil**: kendi Xtream hesabını elle ekleyen
    /// kullanıcılar da var. Birincil düğme yapılsaydı onlar kod arayıp
    /// akışta tıkanırdı.
    private var resellerCodeButton: some View {
        Button {
            showsResellerCode = true
        } label: {
            Label(
                savedCode == nil ? "Bayi kodum var" : "Bayi kodu: \(savedCode ?? "")",
                systemImage: "person.badge.key"
            )
            .font(Theme.Typography.caption)
            .foregroundColor(Theme.Palette.textSecondary)
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

    /// Marka bloğu — bayi kodu girildiyse **bayinin** kimliğini gösterir.
    ///
    /// ⚠️ Logo panelden çekiliyordu ama hiçbir yerde çizilmiyordu: bayi
    /// logosunu yüklüyor, uygulamada göremiyordu. Marka rengi değişip
    /// logonun aynı kalması "yarım markalama" hissi veriyor.
    private var brand: some View {
        VStack(spacing: Theme.Spacing.md) {
            brandMark

            VStack(spacing: Theme.Spacing.sm) {
                Text(dependencies.brandName() ?? "Octopus")
                    .font(Theme.Typography.screenTitle)
                    .foregroundColor(Theme.Palette.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Xtream hesabını veya M3U bağlantını ekleyerek başla.")
                    .font(Theme.Typography.rowSubtitle)
                    .foregroundColor(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    /// Bayi logosu varsa o, yoksa uygulamanın kendi simgesi.
    ///
    /// Logo indirilemezse (bağlantı kopuk, adres ölü) yer tutucu yine
    /// uygulamanın simgesidir — boş bir kutu markasız görünürdü.
    @ViewBuilder
    private var brandMark: some View {
        if let logoURL = dependencies.brandLogoURL() {
            RemoteImageView(url: logoURL, contentMode: .fit, targetWidth: 160) {
                defaultMark
            }
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        } else {
            defaultMark
        }
    }

    private var defaultMark: some View {
        Image(systemName: "antenna.radiowaves.left.and.right")
            .font(.system(size: 56))
            .foregroundColor(Theme.Palette.accent)
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
