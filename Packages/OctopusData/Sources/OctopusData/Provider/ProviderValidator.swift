import Foundation
import OctopusCore
import OctopusDomain

/// Kaynağı kaydetmeden önce sunucuya bağlanıp doğrular.
///
/// Kullanıcının az önce yazdığı parolayla çalışır — Keychain'e henüz
/// yazılmamıştır. Hatalı bilgiyle kaynak kaydedilmesini önler.
///
/// Kullanıcı beklerken çalıştığı için tek deneme yapılır: yanlış parolayı
/// üç kez denemek hem anlamsızdır hem de bazı paneller tekrarlanan başarısız
/// girişte hesabı geçici olarak kilitler.
public struct ProviderValidator: PlaylistValidating {

    private let httpClient: HTTPClient
    private let now: @Sendable () -> Date

    public init(
        session: URLSession = .octopusDefault,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.httpClient = URLSessionHTTPClient(session: session, retryPolicy: .single)
        self.now = now
    }

    /// Test enjeksiyonu için.
    init(httpClient: HTTPClient, now: @escaping @Sendable () -> Date = { Date() }) {
        self.httpClient = httpClient
        self.now = now
    }

    public func validate(
        _ playlist: Playlist,
        password: String?
    ) async throws -> ProviderAccount {
        let provider = try makeProvider(for: playlist, password: password)
        let account = try await provider.authenticate()

        // Abonelik süresi dolmuşsa bağlantı kurulsa bile kaynak kullanılamaz;
        // kullanıcı bunu kaydettikten sonra değil, şimdi öğrenmeli.
        if let block = account.subscriptionBlock(at: now()) {
            throw AppError.subscriptionUnavailable(block)
        }

        Log.network.info("Kaynak doğrulandı: \(account.username)")
        return account
    }

    private func makeProvider(
        for playlist: Playlist,
        password: String?
    ) throws -> ContentProvider {
        switch playlist.kind {

        case .xtream(let host, let username):
            guard let password, !password.isEmpty else {
                throw AppError.unauthorized
            }
            return XtreamContentProvider(
                baseURL: host,
                username: username,
                password: password,
                playlistID: playlist.id,
                httpClient: httpClient,
                now: now
            )

        case .m3u(let url):
            return M3UContentProvider(
                sourceURL: url,
                epgURL: playlist.epgURL,
                playlistID: playlist.id,
                httpClient: httpClient
            )

        case .m3uLocalFile(let fileName):
            let fileURL = try DefaultContentProviderFactory.localPlaylistURL(fileName: fileName)
            return M3UContentProvider(
                sourceURL: fileURL,
                epgURL: playlist.epgURL,
                playlistID: playlist.id,
                httpClient: LocalFileClient()
            )

        case .activationCode:
            throw AppError.unknown(reason: "Aktivasyon kodu desteği Faz 4'te eklenecek")
        case .sampleLibrary:
            return SampleLibraryContentProvider(playlistID: playlist.id)
        }
    }
}
