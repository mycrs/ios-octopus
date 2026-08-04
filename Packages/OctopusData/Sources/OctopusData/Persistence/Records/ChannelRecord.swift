import Foundation
import GRDB
import OctopusDomain

/// `channel` tablosunun satır karşılığı.
struct ChannelRecord: Codable, FetchableRecord, PersistableRecord {

    static let databaseTableName = "channel"

    var id: String
    var playlistId: String
    var name: String
    /// Sağlayıcının verdiği ham kimlik — akış URL'si bundan kurulur.
    var streamKey: String
    var logoURL: String?
    var categoryId: String?
    var epgChannelId: String?
    var number: Int?
    var sortOrder: Int
    var isAdult: Bool

    init(_ channel: Channel) {
        self.id = channel.id.value
        self.playlistId = channel.playlistID.value
        self.name = channel.name
        self.streamKey = channel.streamKey
        self.logoURL = channel.logoURL?.absoluteString
        self.categoryId = channel.categoryID?.value
        self.epgChannelId = channel.epgChannelID
        self.number = channel.number
        self.sortOrder = channel.sortOrder
        self.isAdult = channel.isAdult
    }

    /// Satır → entity. Kanal kaydı için zorunlu alanlar zaten `NOT NULL`
    /// olduğundan bu dönüşüm hata fırlatmaz.
    func toDomain() -> Channel {
        Channel(
            id: Channel.ID(id),
            playlistID: Playlist.ID(playlistId),
            name: name,
            streamKey: streamKey,
            logoURL: logoURL.flatMap(URL.init(string:)),
            categoryID: categoryId.map(MediaCategory.ID.init),
            epgChannelID: epgChannelId,
            number: number,
            sortOrder: sortOrder,
            isAdult: isAdult
        )
    }
}

/// `category` tablosunun satır karşılığı.
struct CategoryRecord: Codable, FetchableRecord, PersistableRecord {

    static let databaseTableName = "category"

    var id: String
    var playlistId: String
    var kind: String
    var name: String
    var sortOrder: Int

    init(_ category: MediaCategory) {
        self.id = category.id.value
        self.playlistId = category.playlistID.value
        self.kind = category.kind.rawValue
        self.name = category.name
        self.sortOrder = category.sortOrder
    }

    func toDomain() throws -> MediaCategory {
        guard let categoryKind = MediaCategory.Kind(rawValue: kind) else {
            throw AppError.storage(reason: "Bilinmeyen kategori türü: \(kind)")
        }
        return MediaCategory(
            id: MediaCategory.ID(id),
            playlistID: Playlist.ID(playlistId),
            kind: categoryKind,
            name: name,
            sortOrder: sortOrder
        )
    }
}
