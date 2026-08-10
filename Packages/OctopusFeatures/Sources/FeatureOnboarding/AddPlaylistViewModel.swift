import Foundation
import Combine
import OctopusDomain
import OctopusDesignSystem   // AppError.userMessage sunum uzantısı

/// Kaynak ekleme akışı: form → doğrulama → kayıt → ilk senkronizasyon.
///
/// ⚠️ Sıra bilinçli: **önce doğrula, sonra kaydet.** Tersi olsaydı hatalı
/// bilgiyle kaynak kaydedilir, kullanıcı onu silmek zorunda kalırdı.
@MainActor
public final class AddPlaylistViewModel: ObservableObject {

    public enum SourceKind: String, CaseIterable, Identifiable, Sendable {
        /// Bayi kodu en başta: müşterilerin çoğu sunucu adresi değil kod alıyor.
        case activationCode
        case xtream
        case m3u

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .activationCode: return "Kod"
            case .xtream: return "Xtream"
            case .m3u: return "M3U"
            }
        }

        /// Panelin "elle giriş" bayrağı bu türü kapsıyor mu?
        ///
        /// Bayi kapattığında kullanıcı yalnızca aktivasyon koduyla
        /// girebilir; sunucu bilgileri elden ele dolaşmasın diye.
        var requiresManualLogin: Bool {
            self != .activationCode
        }
    }

    /// Panel elle girişe izin veriyor mu?
    public var isManualLoginEnabled: Bool {
        dependencies.isManualLoginEnabled()
    }

    /// Seçilebilecek kaynak türleri.
    ///
    /// ⚠️ Panel `xtream_login_enabled: false` derse elle giriş türleri
    /// listeden **çıkarılır**. Bu bayrak okunmuyordu: bayi kapatsa bile
    /// uygulama Xtream ve M3U formlarını göstermeye devam ediyordu.
    public var availableSourceKinds: [SourceKind] {
        isManualLoginEnabled
            ? SourceKind.allCases
            : SourceKind.allCases.filter { !$0.requiresManualLogin }
    }

    /// Seçili tür artık sunulmuyorsa aktivasyon koduna döner.
    ///
    /// Ekran açıkken panel yapılandırması gelebilir; kapatılmış bir formda
    /// kullanıcı yazmaya devam ederse doğrulama sırasında reddedilirdi.
    public func reconcileSourceKind() {
        guard !availableSourceKinds.contains(sourceKind) else { return }
        sourceKind = .activationCode
    }

    /// Bayi sunucularını yükler.
    ///
    /// Tek sunucu varsa **kendiliğinden seçilir**: kullanıcıya tek seçenekli
    /// bir liste sunup "seç" demek gereksiz bir adım.
    public func loadResellerServers() async {
        resellerServers = await dependencies.resellerServers()

        guard host.isEmpty, let only = resellerServers.first, resellerServers.count == 1 else { return }
        select(server: only)
    }

    /// Seçilen sunucunun adresini forma yazar.
    ///
    /// Şema (`http://`) burada eklenmiyor: `PlaylistDraft` eksik şemayı
    /// zaten tamamlıyor ve iki yerde yapmak çift `http://` üretirdi.
    public func select(server: ResellerServer) {
        host = server.baseURL.absoluteString
        selectedServerID = server.id
    }

    /// Akışın hangi adımda olduğu.
    public enum Step: Equatable {
        case form
        case validating
        case syncing(SyncStage)
        case done

        public var isBusy: Bool {
            switch self {
            case .form, .done: return false
            case .validating, .syncing: return true
            }
        }
    }

    // MARK: - Form alanları

    @Published public var sourceKind: SourceKind = .xtream
    @Published public var name = ""
    @Published public var host = ""
    @Published public var username = ""
    @Published public var password = ""
    @Published public var m3uURL = ""
    @Published public var epgURL = ""
    @Published public var activationCode = ""

    /// Bayinin sunucuları — boşsa seçici hiç çizilmez.
    @Published public private(set) var resellerServers: [ResellerServer] = []
    /// Kullanıcının listeden seçtiği sunucu (işaretli göstermek için).
    @Published public var selectedServerID: String?

    // MARK: - Durum

    @Published public private(set) var step: Step = .form
    @Published public private(set) var errorMessage: String?
    /// Doğrulama başarılıysa hesap bilgisi (abonelik bitişi vb.).
    @Published public private(set) var account: ProviderAccount?
    /// Kod ile girişte bayinin müşteri kaydındaki ad — karşılamada gösterilir.
    @Published public private(set) var customerName: String?

    /// Kaydet butonunun etkin olup olmadığı — ağ isteği yapmadan, anında.
    public var canSubmit: Bool {
        guard !step.isBusy else { return false }
        switch sourceKind {
        case .activationCode:
            return activationCode.trimmed.count >= 4
        case .xtream:
            return !host.trimmed.isEmpty && !username.trimmed.isEmpty && !password.isEmpty
        case .m3u:
            return !m3uURL.trimmed.isEmpty
        }
    }

    private let dependencies: OnboardingDependencies
    private let makeID: () -> Playlist.ID
    private let now: () -> Date
    private var progressTask: Task<Void, Never>?

    public init(
        dependencies: OnboardingDependencies,
        makeID: @escaping () -> Playlist.ID = { Playlist.ID(UUID().uuidString) },
        now: @escaping () -> Date = Date.init
    ) {
        self.dependencies = dependencies
        self.makeID = makeID
        self.now = now
    }

    deinit {
        progressTask?.cancel()
    }

    // MARK: - Akış

    public func submit() async {
        errorMessage = nil

        // 1. Erişim bilgilerini elde et.
        //    Kod ile girişte bunlar panelden gelir; diğerlerinde kullanıcı yazar.
        guard let resolved = await resolveCredentials() else { return }
        let (playlist, password) = resolved

        // 2. Sunucu doğrulaması — kaydetmeden önce.
        //    Kod ile girişte de yapılır: panel bilgileri doğru olsa bile
        //    yayın sunucusuna gerçekten bağlanılabildiği kanıtlanmalı.
        step = .validating
        do {
            account = try await dependencies.validator.validate(playlist, password: password)
        } catch {
            step = .form
            errorMessage = AppError.wrap(error).userMessage
            return
        }

        // 3. Kayıt ve etkinleştirme.
        do {
            try await dependencies.playlists.add(playlist, password: password)
            try await dependencies.playlists.setActive(id: playlist.id)
        } catch {
            step = .form
            errorMessage = AppError.wrap(error).userMessage
            return
        }

        // 4. İlk senkronizasyon.
        await runInitialSync(playlistID: playlist.id)
    }

    private func runInitialSync(playlistID: Playlist.ID) async {
        step = .syncing(.idle)
        observeProgress(playlistID: playlistID)

        do {
            try await dependencies.sync.sync(playlistID: playlistID)
            progressTask?.cancel()
            step = .done
        } catch {
            progressTask?.cancel()
            // Kaynak kaydedildi ama içerik çekilemedi. Kullanıcı ana ekrana
            // geçebilmeli; yenileme daha sonra tekrar denenir.
            step = .done
            errorMessage = AppError.wrap(error).userMessage
        }
    }

    private func observeProgress(playlistID: Playlist.ID) {
        progressTask?.cancel()
        progressTask = Task { [weak self, dependencies] in
            for await stage in dependencies.sync.observeProgress(playlistID: playlistID) {
                guard let self, !Task.isCancelled else { return }
                // Bitiş ve hata ayrı ele alınır; burada yalnızca ara aşamalar.
                if case .syncing = self.step {
                    self.step = .syncing(stage)
                }
            }
        }
    }

    public func cancelSync() {
        progressTask?.cancel()
        step = .form
    }

    /// Kaynak türüne göre erişim bilgilerini hazırlar.
    ///
    /// - Returns: Başarısızsa `nil` — hata mesajı zaten ayarlanmış olur.
    private func resolveCredentials() async -> (Playlist, String?)? {
        switch sourceKind {

        case .activationCode:
            step = .validating
            do {
                let result = try await dependencies.activation.redeem(code: activationCode)
                customerName = result.customerName

                // Bayinin markası (renk, ad, logo) koddan geliyor; hemen
                // uygulanır ki kullanıcı daha kurulum biterken kendi
                // bayisinin rengini görsün.
                if let branding = result.branding {
                    dependencies.onBrandingResolved(branding)
                }
                let playlist = Playlist(
                    id: makeID(),
                    name: result.displayName,
                    kind: result.kind,
                    createdAt: now()
                )
                return (playlist, result.password)
            } catch let error as ActivationError {
                step = .form
                errorMessage = error.userMessage
                return nil
            } catch {
                step = .form
                errorMessage = AppError.wrap(error).userMessage
                return nil
            }

        case .xtream, .m3u:
            // Form doğrulaması ağa çıkmadan yapılır.
            do {
                return try makeDraft().build(id: makeID(), createdAt: now())
            } catch let error as PlaylistDraftError {
                errorMessage = error.userMessage
                return nil
            } catch {
                errorMessage = AppError.wrap(error).userMessage
                return nil
            }
        }
    }

    private func makeDraft() -> PlaylistDraft {
        switch sourceKind {
        case .xtream, .activationCode:
            return PlaylistDraft(
                name: name,
                kind: .xtream(host: host, username: username, password: password)
            )
        case .m3u:
            return PlaylistDraft(
                name: name,
                kind: .m3u(url: m3uURL, epgURL: epgURL)
            )
        }
    }
}

// MARK: - Aktivasyon hata metinleri

extension ActivationError {
    /// Her durum farklı bir eylem öneriyor — "tekrar dene" ile
    /// "bayine başvur" aynı şey değil.
    var userMessage: String {
        switch self {
        case .notFound:
            return "Bu kod bulunamadı. Kodu kontrol et veya bayinle iletişime geç."
        case .expired:
            return "Bu kodun süresi dolmuş. Yeni kod için bayinle iletişime geç."
        case .alreadyUsed:
            return "Bu kod daha önce kullanılmış. Yeni kod için bayinle iletişime geç."
        case .tooManyAttempts:
            return "Çok fazla deneme yapıldı. Bir süre bekleyip tekrar dene."
        case .rateLimited:
            return "Sunucu şu an yoğun. Birkaç dakika sonra tekrar dene."
        case .invalidFormat:
            return "Kod biçimi geçersiz. Harf, rakam ve tire kullanılır."
        case .unknown:
            return "Kod doğrulanamadı. Tekrar dene."
        }
    }
}

// MARK: - Hata metinleri

extension PlaylistDraftError {
    /// Form hataları kullanıcının düzeltebileceği eksikliklerdir;
    /// teknik hata gibi sunulmamalı.
    var userMessage: String {
        switch self {
        case .emptyUsername: return "Kullanıcı adını gir."
        case .emptyPassword: return "Parolayı gir."
        case .invalidHost: return "Sunucu adresi geçersiz. Örnek: panel.example.com:8080"
        case .invalidURL: return "Bağlantı geçersiz. Örnek: http://example.com/liste.m3u"
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
