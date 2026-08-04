import Foundation

/// Canlı TV kanalı.
public struct Channel: Identifiable, Hashable, Codable, Sendable {

    public typealias ID = Identifier<Channel>

    public let id: ID
    public let playlistID: Playlist.ID

    public var name: String

    /// Sağlayıcının verdiği ham akış kimliği.
    /// Xtream'de sayısal `stream_id`, M3U'da satırdaki URL'nin kendisi.
    public var streamKey: String

    public var logoURL: URL?
    public var categoryID: MediaCategory.ID?

    /// XMLTV eşleştirmesi için `tvg-id`. EPG bunun üzerinden bağlanır.
    public var epgChannelID: String?

    /// Sağlayıcının verdiği kanal numarası (`tvg-chno`) veya liste sırası.
    public var number: Int?
    public var sortOrder: Int

    /// Yetişkin içerik — ebeveyn kilidi bunu okur.
    public var isAdult: Bool

    public init(
        id: ID,
        playlistID: Playlist.ID,
        name: String,
        streamKey: String,
        logoURL: URL? = nil,
        categoryID: MediaCategory.ID? = nil,
        epgChannelID: String? = nil,
        number: Int? = nil,
        sortOrder: Int = 0,
        isAdult: Bool = false
    ) {
        self.id = id
        self.playlistID = playlistID
        self.name = name
        self.streamKey = streamKey
        self.logoURL = logoURL
        self.categoryID = categoryID
        self.epgChannelID = epgChannelID
        self.number = number
        self.sortOrder = sortOrder
        self.isAdult = isAdult
    }
}
