import Foundation

/// İçerik kategorisi (ör. "Ulusal", "Spor", "Aksiyon").
///
/// `Category` yerine `MediaCategory`: Objective-C'nin "category" kavramıyla
/// ve SwiftUI isimleriyle karışmasın diye.
public struct MediaCategory: Identifiable, Hashable, Codable, Sendable {

    public typealias ID = Identifier<MediaCategory>

    /// Kategorinin hangi içerik türüne ait olduğu.
    /// Xtream'de canlı/film/dizi kategorileri ayrı listelerdir ve
    /// id'leri çakışabilir — bu yüzden tür ayrımı zorunlu.
    public enum Kind: String, Codable, Hashable, Sendable, CaseIterable {
        case live
        case movie
        case series
    }

    public let id: ID
    public let playlistID: Playlist.ID
    public let kind: Kind
    public var name: String
    public var sortOrder: Int

    public init(
        id: ID,
        playlistID: Playlist.ID,
        kind: Kind,
        name: String,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.playlistID = playlistID
        self.kind = kind
        self.name = name
        self.sortOrder = sortOrder
    }
}
