import Foundation
import OctopusCore
import OctopusDomain

/// `Playlist.Kind`'a bakıp doğru sağlayıcıyı üretir.
///
/// ⚠️ Kaynak türü dallanmasının **tek** yeri burasıdır.
/// Referans projede `username == "M3U_PLAYLIST" || hostUrl == "ACTIVATION_CODE"
/// || isDemoMode` deseni 10'dan fazla dosyaya yayılmıştı; yeni bir tür eklemek
/// her birini bulup güncellemeyi gerektiriyordu.
///
/// `actor`: üretilen sağlayıcılar önbelleklenir. M3U sağlayıcısı indirdiği
/// listeyi kendi içinde tuttuğu için her çağrıda yenisini kurmak 20 MB'lık
/// listenin tekrar tekrar inmesi demek olurdu.
public actor DefaultContentProviderFactory: ContentProviderFactory {

    private let httpClient: HTTPClient
    private let secrets: SecretStore
    private let liveFormat: XtreamContentProvider.LiveFormat
    private let hostResolver: HostResolving

    /// Önbellek anahtarı **kimlik + kaynak tanımı**.
    ///
    /// ⚠️ Yalnızca `id` ile anahtarlanıyordu. Kullanıcı sunucu adresini ya da
    /// kullanıcı adını değiştirdiğinde önbellekteki sağlayıcı **eski** bilgilerle
    /// çalışmaya devam ediyordu — `invalidate` üretimde hiçbir yerden
    /// çağrılmadığı için oturum boyunca. Anahtara `kind` girince kaynak
    /// değişimi yeni sağlayıcıyı kendiliğinden zorunlu kılar ve unutulabilecek
    /// bir call-site kalmaz. (`Playlist.Kind` zaten `Hashable`.)
    private struct CacheKey: Hashable {
        let id: String
        let kind: Playlist.Kind
        let epgURL: URL?
    }

    private var cache: [CacheKey: ContentProvider] = [:]
    private struct ProviderBuild {
        let id: UUID
        let task: Task<ContentProvider, Error>
    }
    private var providerBuilds: [CacheKey: ProviderBuild] = [:]
    private var requestedKeys: [String: CacheKey] = [:]

    public init(
        httpClient: HTTPClient,
        secrets: SecretStore,
        liveFormat: XtreamContentProvider.LiveFormat = .hls,
        hostResolver: HostResolving = PassthroughHostResolver()
    ) {
        self.httpClient = httpClient
        self.secrets = secrets
        self.liveFormat = liveFormat
        self.hostResolver = hostResolver
    }

    public func makeProvider(for playlist: Playlist) async throws -> ContentProvider {
        try Task.checkCancellation()
        let key = CacheKey(id: playlist.id.value, kind: playlist.kind, epgURL: playlist.epgURL)
        requestedKeys[playlist.id.value] = key
        if let cached = cache[key] { return cached }
        if let building = providerBuilds[key] {
            let provider = try await building.task.value
            try Task.checkCancellation()
            return provider
        }

        // Kaynak düzenlenince eski M3U listesini bellekte süresiz tutma.
        cache = cache.filter { $0.key.id != playlist.id.value }
        let buildID = UUID()
        let task = Task { try await self.buildProvider(for: playlist) }
        providerBuilds[key] = ProviderBuild(id: buildID, task: task)
        defer {
            if providerBuilds[key]?.id == buildID { providerBuilds[key] = nil }
        }
        let provider = try await task.value
        if requestedKeys[playlist.id.value] == key { cache[key] = provider }
        try Task.checkCancellation()
        return provider
    }

    /// Kaynak düzenlendiğinde veya senkronizasyon taze veri istediğinde.
    ///
    /// Kaynak **tanımı** değişince önbellek zaten kendiliğinden ıskalar
    /// (bkz. `CacheKey`); bu yalnızca elle boşaltma gerektiğinde kullanılır.
    public func invalidate(playlistID: Playlist.ID) {
        cache = cache.filter { $0.key.id != playlistID.value }
        requestedKeys[playlistID.value] = nil
        let builds = providerBuilds.filter { $0.key.id == playlistID.value }
        for (key, build) in builds {
            build.task.cancel()
            providerBuilds[key] = nil
        }
    }

    public func invalidateAll() {
        cache.removeAll()
        requestedKeys.removeAll()
        providerBuilds.values.forEach { $0.task.cancel() }
        providerBuilds.removeAll()
    }

    // MARK: - Kurulum

    private func buildProvider(for playlist: Playlist) async throws -> ContentProvider {
        try Task.checkCancellation()
        switch playlist.kind {

        case .xtream(let host, let username):
            // Parola veritabanında değil Keychain'de tutulur.
            guard let password = try readPassword(for: playlist) else {
                throw AppError.unauthorized
            }
            // Sağlayıcılar sunucu adresini değiştirebiliyor; kayıtlı adres
            // ölmüşse panelin yedek listesinden çalışan bulunur.
            let resolvedHost = await hostResolver.resolve(preferring: host)
            try Task.checkCancellation()
            return XtreamContentProvider(
                baseURL: resolvedHost,
                username: username,
                password: password,
                playlistID: playlist.id,
                httpClient: httpClient,
                liveFormat: liveFormat
            )

        case .m3u(let url):
            return M3UContentProvider(
                sourceURL: url,
                epgURL: playlist.epgURL,
                playlistID: playlist.id,
                httpClient: httpClient
            )

        case .m3uLocalFile(let fileName):
            // Aynı M3U sağlayıcısı kullanılır; yalnızca okuma yolu değişir.
            let fileURL = try Self.localPlaylistURL(fileName: fileName)
            return M3UContentProvider(
                sourceURL: fileURL,
                epgURL: playlist.epgURL,
                playlistID: playlist.id,
                httpClient: LocalFileClient()
            )

        case .activationCode:
            // Faz 4: kod panelden çözülüp Xtream bilgilerine dönüştürülecek,
            // ardından XtreamContentProvider kurulacak.
            throw AppError.unknown(reason: "Aktivasyon kodu desteği Faz 4'te eklenecek")
        case .sampleLibrary:
            return SampleLibraryContentProvider(playlistID: playlist.id)
        }
    }

    private func readPassword(for playlist: Playlist) throws -> String? {
        do {
            return try secrets.read(for: playlist.credentialKey)
        } catch {
            Log.app.error("Parola okunamadı: \(String(describing: error))")
            throw AppError.storage(reason: "Kayıtlı parolaya erişilemedi")
        }
    }

    static func localPlaylistURL(fileName: String) throws -> URL {
        let documents = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        return documents.appendingPathComponent(fileName)
    }
}

/// Cihaza aktarılmış M3U dosyalarını okur.
///
/// `URLSession` `file://` şemasını güvenilir biçimde desteklemediği için
/// aynı `HTTPClient` sözleşmesi dosya sistemi üzerinden karşılanır —
/// böylece `M3UContentProvider` kaynağın nereden geldiğini bilmez.
struct LocalFileClient: HTTPClient {

    func get(_ url: URL, headers: [String: String]) async throws -> Data {
        do {
            return try Data(contentsOf: url)
        } catch {
            Log.parser.error("Yerel liste okunamadı: \(String(describing: error))")
            throw AppError.notFound
        }
    }
}
