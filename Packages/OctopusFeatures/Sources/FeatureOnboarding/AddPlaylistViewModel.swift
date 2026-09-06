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
        /// ⚠️ Sıra ekrandaki seçicinin sırasıdır (`allCases`): önce elle
        /// giriş (Xtream → M3U), en sonda kod. Varsayılan seçim `xtream`
        /// olduğundan kodun başa alınması seçiciyi ortadan başlatıyordu.
        case xtream
        case m3u
        case activationCode

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

    /// Xtream sekmesinde adres nasıl girilecek — **açık kullanıcı seçimi.**
    ///
    /// ⚠️ Önceki sürümde tek bir alan (dört rakamsa kod, değilse adres diye)
    /// içeriğine bakarak kendi kendine karar veriyordu. App Review bunu
    /// "gizlenmiş özellik" saydı (guideline 5.6): kullanıcı adres yazan bir
    /// alanın aslında belgelenmemiş başka sunuculara yönlendirebildiğini
    /// bilemiyordu. Artık ayrım **etiketli bir seçicide**: hangi mod
    /// seçiliyse hangi alan gösteriliyorsa davranış tam olarak odur.
    public enum XtreamEntryMode: String, CaseIterable, Identifiable, Sendable {
        case dns
        case code

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .dns: return "DNS ile giriş"
            case .code: return "Kısa kodla giriş"
            }
        }

        var icon: String {
            switch self {
            case .dns: return "network"
            case .code: return "number"
            }
        }
    }

    /// Akışın hangi adımda olduğu.
    public enum Step: Equatable {
        case form
        /// Kısa kodun bağlı olduğu sunucular sırayla deneniyor (kaçıncısı /
        /// toplam). Ayrı bir durum: bu adım uzun sürebiliyor (her sunucu
        /// için bir ağ turu) ve kullanıcı "donmuş mu?" diye düşünmemeli.
        case searchingServer(index: Int, total: Int)
        case validating
        case syncing(SyncStage)
        case done

        public var isBusy: Bool {
            switch self {
            case .form, .done: return false
            case .searchingServer, .validating, .syncing: return true
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

    /// Xtream sekmesinde hangi giriş biçimi seçili. Varsayılan DNS: bu,
    /// ürünün asıl anlattığı yol (bkz. App Review notları — "generic IPTV
    /// player"). Kısa kod, hizmet sağlayıcısından öyle bir kod almış
    /// kullanıcı için **ayrı ve açık** bir seçenek olarak duruyor.
    @Published public var xtreamEntryMode: XtreamEntryMode = .dns
    /// Kısa kod alanı — `host`'tan tamamen ayrı. İki farklı anlam tek
    /// alanda birleşmiyor ki hiçbir davranış içerikten çıkarılmasın.
    @Published public var resellerCode = ""
    /// Kısa kod bir sunucuya çözüldüğünde sırayla denenecek liste.
    @Published public private(set) var resellerServers: [ResellerServer] = []

    // MARK: - Durum

    @Published public private(set) var step: Step = .form
    @Published public private(set) var errorMessage: String?
    /// İlk kurulum boyunca tamamlanan katalogların gerçek öğe adetleri.
    @Published public private(set) var syncCounts = SyncContentCounts.empty
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
            let addressProvided = xtreamEntryMode == .code
                ? !resellerCode.trimmed.isEmpty
                : !host.trimmed.isEmpty
            return addressProvided
                && !username.trimmed.isEmpty
                && !password.isEmpty
        case .m3u:
            return !m3uURL.trimmed.isEmpty
        }
    }

    private let dependencies: OnboardingDependencies
    private let makeID: () -> Playlist.ID
    private let now: () -> Date
    private let completionDelayNanoseconds: UInt64
    private var progressTask: Task<Void, Never>?
    /// Kısa kod bir sunucuya çözüldüğünde gerçek adres burada tutulur.
    private var resolvedHost = ""

    public init(
        dependencies: OnboardingDependencies,
        makeID: @escaping () -> Playlist.ID = { Playlist.ID(UUID().uuidString) },
        now: @escaping () -> Date = Date.init,
        completionDelayNanoseconds: UInt64 = 1_600_000_000
    ) {
        self.dependencies = dependencies
        self.makeID = makeID
        self.now = now
        self.completionDelayNanoseconds = completionDelayNanoseconds
    }

    deinit {
        progressTask?.cancel()
    }

    // MARK: - Akış

    public func submit() async {
        errorMessage = nil

        // Kısa kod modu açıkça seçilmişse önce sunucu listesi çözülür.
        // ⚠️ Sırf bu mod seçiliyken devreye girer — `host` alanına ne
        // yazıldığına bakılmıyor, iki alan birbirinin yerine geçmiyor.
        if sourceKind == .xtream, xtreamEntryMode == .code {
            guard await resolveResellerCode(resellerCode.trimmed),
                  let first = resellerServers.first
            else { return }
            select(server: first)
        }

        // 1. Erişim bilgilerini elde et.
        //    Kod ile girişte bunlar panelden gelir; diğerlerinde kullanıcı yazar.
        guard let resolved = await resolveCredentials() else { return }
        // Doğrulama başka bir sunucuda tutabilir; liste değişebilir olmalı.
        var playlist = resolved.0
        let password = resolved.1
        let playlistPIN = resolved.2

        // 2. Sunucu doğrulaması — kaydetmeden önce.
        //    Kod ile girişte de yapılır: panel bilgileri doğru olsa bile
        //    yayın sunucusuna gerçekten bağlanılabildiği kanıtlanmalı.
        step = .validating
        do {
            account = try await dependencies.validator.validate(playlist, password: password)
        } catch {
            let validationError = AppError.wrap(error)

            // M3U bağlantısı Xtream'e çevrilmişti ama panel kabul etmedi:
            // düz M3U olarak yeniden denenir.
            //
            // ⚠️ Bazı paneller `get.php` ile listeyi verir, `player_api.php`
            // ucunu kapatır. Dönüştürmeyi tek yol saymak, çalışan bir
            // kaynağı kurulamaz hâle getiriyordu — kullanıcı "M3U
            // çalışmıyor" diyor, oysa M3U hiç denenmiyordu.
            if sourceKind == .m3u, case .xtream = playlist.kind,
               let fallback = await validateAsPlainM3U() {
                playlist = fallback.0
                account = fallback.1
            } else if sourceKind == .xtream, xtreamEntryMode == .code {
                // Kısa kodun ilk sunucusu kabul etmedi. Aynı hesap koda
                // bağlı diğer sunucularda geçerli olabilir — kullanıcı
                // hangisinin kendisine ait olduğunu bilmiyor, sırayla denenir.
                guard let found = await findWorkingServer(
                    failedWith: validationError,
                    username: username,
                    password: self.password
                ) else { return }
                playlist = found
            } else {
                step = .form
                errorMessage = validationError.userMessage
                return
            }
        }

        // 3. Kayıt ve etkinleştirme.
        do {
            try await dependencies.playlists.add(playlist, password: password)
            do {
                try await dependencies.activatePlaylist(playlist.id, playlistPIN)
            } catch {
                // PIN güvenli alana yazılamadıysa erişim kapısı olmayan korumalı
                // bir kaynak bırakma; ekleme işlemini geri al.
                try? await dependencies.playlists.delete(id: playlist.id)
                throw error
            }
        } catch {
            step = .form
            errorMessage = AppError.wrap(error).userMessage
            return
        }

        // 4. İlk senkronizasyon.
        await runInitialSync(playlistID: playlist.id)
    }

    private func runInitialSync(playlistID: Playlist.ID) async {
        syncCounts = .empty
        step = .syncing(.idle)
        observeProgress(playlistID: playlistID)

        do {
            try await dependencies.sync.sync(playlistID: playlistID)
            // Son adetlerin animasyonla yerleşmesi ve kullanıcının sonucu
            // okuyabilmesi için başarı yüzeyi kısa süre ekranda kalır.
            step = .syncing(.finished(at: now(), counts: syncCounts))
            try? await Task.sleep(nanoseconds: completionDelayNanoseconds)
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
                self.syncCounts.record(stage)
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
    /// Xtream'e çevrilmiş M3U bağlantısını **düz M3U olarak** dener.
    ///
    /// `nil` dönerse ikisi de olmadı demektir; çağıran asıl (Xtream)
    /// hatasını gösterir — kullanıcıya "M3U de denedim" ayrıntısı
    /// yardımcı olmaz, adresin kendisi yanlıştır.
    private func validateAsPlainM3U() async -> (Playlist, ProviderAccount)? {
        guard
            let plain = try? makeDraft().build(
                id: makeID(),
                createdAt: now(),
                convertingXtreamLinks: false
            )
        else { return nil }

        guard let account = try? await dependencies.validator.validate(
            plain.playlist,
            password: plain.password
        ) else { return nil }

        return (plain.playlist, account)
    }

    private func resolveCredentials() async -> (Playlist, String?, String?)? {
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
                return (
                    playlist,
                    result.password,
                    result.isProtected ? result.playlistPIN : nil
                )
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
                let resolved = try makeDraft().build(id: makeID(), createdAt: now())
                return (resolved.0, resolved.1, nil)
            } catch let error as PlaylistDraftError {
                errorMessage = error.userMessage
                return nil
            } catch {
                errorMessage = AppError.wrap(error).userMessage
                return nil
            }
        }
    }

    /// Kısa kodu doğrular ve o koda tanımlı sunucu listesini alır.
    ///
    /// ⚠️ Yalnızca kullanıcı **açıkça** "Kısa kodla giriş" seçtiğinde
    /// çağrılır — `host` alanının içeriğine bakılarak tetiklenmez.
    private func resolveResellerCode(_ code: String) async -> Bool {
        step = .validating
        let isValid = await dependencies.applyResellerCode(code)
        guard isValid else {
            step = .form
            errorMessage = "Kod doğrulanamadı. Girdiğini kontrol edip tekrar dene."
            return false
        }

        resellerServers = await dependencies.resellerServers()
        guard !resellerServers.isEmpty else {
            step = .form
            errorMessage = "Bağlantı hazırlanamadı. Hizmet sağlayıcınla iletişime geç."
            return false
        }
        return true
    }

    /// Seçilen sunucuyu kullanıcıya göstermeden bağlantı için saklar.
    ///
    /// Şema (`http://`) burada eklenmiyor: `PlaylistDraft` eksik şemayı
    /// zaten tamamlıyor ve iki yerde yapmak çift `http://` üretirdi.
    private func select(server: ResellerServer) {
        resolvedHost = server.baseURL.absoluteString
    }

    /// Kısa koda bağlı sunucuları sırayla dener; kabul edeni döndürür.
    ///
    /// - Returns: Çalışan sunucuyla kurulmuş liste; hiçbiri olmazsa `nil`
    ///   (hata mesajı ayarlanmış olur).
    private func findWorkingServer(
        failedWith firstError: AppError,
        username: String,
        password: String
    ) async -> Playlist? {
        // İlk sunucu zaten denendi; listede ikinci kez denenmesin.
        let candidates = resellerServers.filter {
            $0.baseURL.absoluteString != resolvedHost
        }

        guard !candidates.isEmpty else {
            step = .form
            errorMessage = firstError.userMessage
            return nil
        }

        for (index, server) in candidates.enumerated() {
            step = .searchingServer(index: index + 1, total: candidates.count)

            let draft = PlaylistDraft(
                name: name,
                kind: .xtream(
                    host: server.baseURL.absoluteString,
                    username: username,
                    password: password
                )
            )

            guard let (candidate, candidatePassword) =
                try? draft.build(id: makeID(), createdAt: now())
            else { continue }

            do {
                account = try await dependencies.validator.validate(
                    candidate,
                    password: candidatePassword
                )
                resolvedHost = server.baseURL.absoluteString
                return candidate
            } catch {
                // Hesap yalnızca belirli bir sunucuda tanımlı olabilir.
                // Hata türünden bağımsız olarak sıradaki adres denenir.
                continue
            }
        }

        step = .form
        errorMessage = "Bağlantı kurulamadı. Bilgilerini kontrol et veya hizmet sağlayıcınla iletişime geç."
        return nil
    }

    private func makeDraft() -> PlaylistDraft {
        switch sourceKind {
        case .xtream, .activationCode:
            return PlaylistDraft(
                name: name,
                kind: .xtream(
                    host: sourceKind == .xtream && xtreamEntryMode == .code ? resolvedHost : host,
                    username: username,
                    password: password
                )
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
            return "Bu kod bulunamadı. Kodu kontrol et veya hizmet sağlayıcınla iletişime geç."
        case .expired:
            return "Bu kodun süresi dolmuş. Yeni kod için hizmet sağlayıcınla iletişime geç."
        case .alreadyUsed:
            return "Bu kod daha önce kullanılmış. Yeni kod için hizmet sağlayıcınla iletişime geç."
        case .tooManyAttempts:
            return "Çok fazla deneme yapıldı. Bir süre bekleyip tekrar dene."
        case .rateLimited:
            return "Sunucu şu an yoğun. Birkaç dakika sonra tekrar dene."
        case .invalidFormat:
            // ⚠️ Eskiden "Harf, rakam ve tire kullanılır." yazıyordu —
            // uygulamada böyle bir kural **yok** (yerel karakter süzgeci
            // bilerek kaldırıldı, bkz. BRAIN.md § 11.1). Var olmayan bir
            // kuralı anlatan hata, doğru kodu yazan kullanıcıyı kodunu
            // "düzeltmeye" iterek büsbütün yanıltıyordu. Panel bu yanıtı
            // okuyamadığı gövdeler için de döndürüyor.
            return "Kod doğrulanamadı. Kodu kontrol edip tekrar dene."
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
