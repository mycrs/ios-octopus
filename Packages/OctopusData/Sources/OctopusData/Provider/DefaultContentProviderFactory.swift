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

    private var cache: [String: ContentProvider] = [:]

    public init(
        httpClient: HTTPClient,
        secrets: SecretStore,
        liveFormat: XtreamContentProvider.LiveFormat = .hls
    ) {
        self.httpClient = httpClient
        self.secrets = secrets
        self.liveFormat = liveFormat
    }

    public func makeProvider(for playlist: Playlist) async throws -> ContentProvider {
        if let cached = cache[playlist.id.value] { return cached }

        let provider = try buildProvider(for: playlist)
        cache[playlist.id.value] = provider
        return provider
    }

    /// Kaynak düzenlendiğinde veya senkronizasyon taze veri istediğinde.
    public func invalidate(playlistID: Playlist.ID) {
        cache[playlistID.value] = nil
    }

    public func invalidateAll() {
        cache.removeAll()
    }

    // MARK: - Kurulum

    private func buildProvider(for playlist: Playlist) throws -> ContentProvider {
        switch playlist.kind {

        case .xtream(let host, let username):
            // Parola veritabanında değil Keychain'de tutulur.
            guard let password = try readPassword(for: playlist) else {
                throw AppError.unauthorized
            }
            return XtreamContentProvider(
                baseURL: host,
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
