import Foundation
import GRDB
import OctopusDomain

// Kullanıcıya ait kayıtlar.
//
// Bu tablolar kaynağa yabancı anahtarla bağlı DEĞİL: kullanıcı bir kaynağı
// silip yeniden eklediğinde favorileri ve izleme ilerlemesi yerinde kalır.
// Kimlikler global benzersiz olduğu için eşleşme bozulmaz (bkz. EntityID).

struct FavoriteRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "favorite"

    var itemKey: String
    var addedAt: Date
}

struct PlaybackProgressRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "playbackProgress"

    var itemKey: String
    var positionSeconds: Double
    var durationSeconds: Double
    var updatedAt: Date

    init(_ progress: PlaybackProgress) {
        self.itemKey = progress.itemKey
        self.positionSeconds = progress.positionSeconds
        self.durationSeconds = progress.durationSeconds
        self.updatedAt = progress.updatedAt
    }

    func toDomain() -> PlaybackProgress {
        PlaybackProgress(
            itemKey: itemKey,
            positionSeconds: positionSeconds,
            durationSeconds: durationSeconds,
            updatedAt: updatedAt
        )
    }
}

struct WatchHistoryRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "watchHistory"

    var itemKey: String
    var playedAt: Date
}

// MARK: - Anahtar yardımcıları

extension PlaybackItem.Source {

    /// `live:` gibi tür önekini ayırıp ham kimliği döndürür.
    /// Favori listelerini kanal/film tablolarıyla eşlemek için kullanılır.
    static func entityID(fromStorageKey key: String) -> String? {
        guard let separatorIndex = key.firstIndex(of: ":") else { return nil }
        return String(key[key.index(after: separatorIndex)...])
    }
}
