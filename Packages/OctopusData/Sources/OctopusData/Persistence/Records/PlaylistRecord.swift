import Foundation
import GRDB
import OctopusDomain

/// `playlist` tablosunun satır karşılığı.
///
/// ## Neden ayrı bir tip?
/// Domain entity'sine GRDB uyumluluğu eklenseydi veritabanı şeması ile iş
/// modeli birbirine kilitlenirdi: kolon eklemek entity'yi değiştirmeyi
/// gerektirirdi. Ayrı `Record` tipiyle ikisi bağımsız evrilir.
///
/// `Playlist.Kind` burada **ayrı kolonlara açılır** — tek JSON blob olarak
/// saklansaydı "aktif Xtream kaynakları" gibi sorgular yazılamazdı.
struct PlaylistRecord: Codable, FetchableRecord, PersistableRecord {

    static let databaseTableName = "playlist"

    var id: String
    var name: String
    var kindType: String
    var host: String?
    var username: String?
    var url: String?
    var fileName: String?
    var activationCode: String?
    var epgURL: String?
    var createdAt: Date
    var lastSyncedAt: Date?
    var isActive: Bool

    /// `kindType` kolonunun alabileceği değerler.
    /// Ham dizgi yerine bu tip kullanılır ki yazım hatası derlenmesin.
    enum KindType: String {
        case xtream
        case m3u
        case m3uLocalFile
        case activationCode
    }
}

// MARK: - Domain → Satır

extension PlaylistRecord {

    init(_ playlist: Playlist) {
        self.id = playlist.id.value
        self.name = playlist.name
        self.epgURL = playlist.epgURL?.absoluteString
        self.createdAt = playlist.createdAt
        self.lastSyncedAt = playlist.lastSyncedAt
        self.isActive = playlist.isActive

        // Kullanılmayan alanlar nil kalır; tür ayrımı `kindType` ile yapılır.
        self.host = nil
        self.username = nil
        self.url = nil
        self.fileName = nil
        self.activationCode = nil

        switch playlist.kind {
        case .xtream(let host, let username):
            self.kindType = KindType.xtream.rawValue
            self.host = host.absoluteString
            self.username = username
        case .m3u(let url):
            self.kindType = KindType.m3u.rawValue
            self.url = url.absoluteString
        case .m3uLocalFile(let fileName):
            self.kindType = KindType.m3uLocalFile.rawValue
            self.fileName = fileName
        case .activationCode(let code):
            self.kindType = KindType.activationCode.rawValue
            self.activationCode = code
        }
    }
}

// MARK: - Satır → Domain

extension PlaylistRecord {

    /// - Throws: Satır bozuksa `AppError.storage`. Sessizce `nil` dönmez —
    ///   bozuk veri fark edilmeden kalırsa teşhis edilemez hale gelir.
    func toDomain() throws -> Playlist {
        Playlist(
            id: Playlist.ID(id),
            name: name,
            kind: try decodeKind(),
            epgURL: epgURL.flatMap(URL.init(string:)),
            createdAt: createdAt,
            lastSyncedAt: lastSyncedAt,
            isActive: isActive
        )
    }

    private func decodeKind() throws -> Playlist.Kind {
        guard let type = KindType(rawValue: kindType) else {
            throw AppError.storage(reason: "Bilinmeyen kaynak türü: \(kindType)")
        }

        switch type {
        case .xtream:
            guard let host, let hostURL = URL(string: host), let username else {
                throw AppError.storage(reason: "Xtream kaydında sunucu/kullanıcı eksik: \(id)")
            }
            return .xtream(host: hostURL, username: username)

        case .m3u:
            guard let url, let playlistURL = URL(string: url) else {
                throw AppError.storage(reason: "M3U kaydında adres eksik: \(id)")
            }
            return .m3u(url: playlistURL)

        case .m3uLocalFile:
            guard let fileName else {
                throw AppError.storage(reason: "Yerel M3U kaydında dosya adı eksik: \(id)")
            }
            return .m3uLocalFile(fileName: fileName)

        case .activationCode:
            guard let activationCode else {
                throw AppError.storage(reason: "Aktivasyon kaydında kod eksik: \(id)")
            }
            return .activationCode(code: activationCode)
        }
    }
}
