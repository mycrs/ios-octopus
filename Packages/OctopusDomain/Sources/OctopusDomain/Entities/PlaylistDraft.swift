import Foundation

/// Kullanıcının kaynak ekleme formunda girdiği ham veriler.
///
/// Form alanları ile `Playlist` entity'si arasında bilinçli bir ayrım var:
/// kullanıcı "panel.example.com:8080" yazar, entity ise geçerli bir `URL`
/// ister. Bu dönüşüm ve doğrulama **saf mantıktır** — ekran olmadan,
/// simülatörsüz, milisaniyeler içinde test edilir.
public struct PlaylistDraft: Equatable, Sendable {

    public enum Kind: Equatable, Sendable {
        case xtream(host: String, username: String, password: String)
        case m3u(url: String, epgURL: String)
    }

    public var name: String
    public var kind: Kind

    public init(name: String, kind: Kind) {
        self.name = name
        self.kind = kind
    }

    /// Doğrulanmış entity ve (varsa) Keychain'e yazılacak parola.
    ///
    /// - Returns: Parola yalnızca Xtream kaynaklarında döner; entity'ye
    ///   hiçbir zaman girmez.
    public func build(
        id: Playlist.ID,
        createdAt: Date
    ) throws -> (playlist: Playlist, password: String?) {

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        switch kind {

        case .xtream(let rawHost, let rawUsername, let password):
            let username = rawUsername.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !username.isEmpty else { throw PlaylistDraftError.emptyUsername }
            guard !password.isEmpty else { throw PlaylistDraftError.emptyPassword }
            guard let host = Self.normalizedURL(rawHost) else {
                throw PlaylistDraftError.invalidHost
            }

            // Ad boş bırakıldıysa sunucu adı kullanılır — kullanıcıyı
            // zorunlu bir alanla uğraştırmaya gerek yok.
            let displayName = trimmedName.isEmpty
                ? (host.host ?? "Xtream")
                : trimmedName

            return (
                Playlist(
                    id: id,
                    name: displayName,
                    kind: .xtream(host: host, username: username),
                    createdAt: createdAt
                ),
                password
            )

        case .m3u(let rawURL, let rawEPG):
            guard let url = Self.normalizedURL(rawURL) else {
                throw PlaylistDraftError.invalidURL
            }
            let epgURL = rawEPG.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : Self.normalizedURL(rawEPG)

            let displayName = trimmedName.isEmpty
                ? (url.host ?? "M3U")
                : trimmedName

            return (
                Playlist(
                    id: id,
                    name: displayName,
                    kind: .m3u(url: url),
                    epgURL: epgURL,
                    createdAt: createdAt
                ),
                nil
            )
        }
    }

    /// Kullanıcı adresi çoğu zaman şemasız yazar ("panel.example.com:8080").
    /// Eksik şema `http://` olarak tamamlanır — IPTV panellerinin çoğu
    /// HTTPS sunmuyor.
    static func normalizedURL(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if !text.contains("://") {
            text = "http://" + text
        }

        // Sondaki eğik çizgi adres kurulumunda çift eğik çizgiye yol açar.
        while text.hasSuffix("/") {
            text.removeLast()
        }

        guard let url = URL(string: text),
              let host = url.host,
              !host.isEmpty,
              host.contains(".") || host == "localhost"
        else { return nil }

        return url
    }
}

/// Form doğrulama hataları. `AppError`'dan ayrı tutulur: bunlar sunucu
/// veya depolama sorunu değil, kullanıcının düzeltebileceği eksikliklerdir.
public enum PlaylistDraftError: Error, Equatable, Sendable {
    case emptyUsername
    case emptyPassword
    case invalidHost
    case invalidURL
}
