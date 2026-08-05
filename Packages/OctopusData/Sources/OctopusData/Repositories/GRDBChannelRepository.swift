import Foundation
import GRDB
import OctopusCore
import OctopusDomain

/// Canlı TV kanalları — SQLite destekli.
public actor GRDBChannelRepository: ChannelRepository {

    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    // MARK: - Kategoriler

    public func categories(playlistID: Playlist.ID) async throws -> [MediaCategory] {
        let records = try await database.read { db in
            try CategoryRecord
                .filter(Column("playlistId") == playlistID.value)
                .filter(Column("kind") == MediaCategory.Kind.live.rawValue)
                .order(Column("sortOrder"), Column("name"))
                .fetchAll(db)
        }
        return try records.map { try $0.toDomain() }
    }

    // MARK: - Kanallar

    public func channels(
        playlistID: Playlist.ID,
        categoryID: MediaCategory.ID?
    ) async throws -> [Channel] {
        let records = try await database.read { db in
            try Self.channelRequest(playlistID: playlistID, categoryID: categoryID).fetchAll(db)
        }
        return records.map { $0.toDomain() }
    }

    public func channel(id: Channel.ID) async throws -> Channel? {
        let record = try await database.read { db in
            try ChannelRecord.fetchOne(db, key: id.value)
        }
        return record?.toDomain()
    }

    /// Numaraya göre kanal.
    ///
    /// ⚠️ Numara **benzersiz değil**: sağlayıcılar aynı numarayı farklı
    /// kalitelerde (SD/HD) tekrar kullanıyor. Liste sırasındaki ilki
    /// döndürülür — kullanıcının "205" deyince beklediği kanal odur.
    public func channel(number: Int, playlistID: Playlist.ID) async throws -> Channel? {
        let record = try await database.read { db in
            try ChannelRecord
                .filter(Column("playlistId") == playlistID.value)
                .filter(Column("number") == number)
                .order(Column("sortOrder"))
                .fetchOne(db)
        }
        return record?.toDomain()
    }

    // MARK: - Arama

    /// FTS5 destekli ad araması.
    ///
    /// Kullanıcı yazarken sonuç göstermek için **önek** eşleşmesi kullanılır:
    /// "spo" → "Spor Kanalı" bulunur.
    public func search(
        query: String,
        playlistID: Playlist.ID,
        limit: Int
    ) async throws -> [Channel] {
        // Ham kullanıcı metni doğrudan MATCH'e verilirse özel karakterler
        // (tırnak, yıldız) sözdizimi hatası üretir. FTS5Pattern kaçırır.
        guard let pattern = FTS5Pattern(matchingAllPrefixesIn: query) else {
            return []
        }

        let records = try await database.read { db in
            try ChannelRecord.fetchAll(
                db,
                sql: """
                    SELECT channel.* FROM channel
                    JOIN channelSearch ON channelSearch.rowid = channel.rowid
                    WHERE channelSearch MATCH ? AND channel.playlistId = ?
                    ORDER BY channel.sortOrder, channel.name
                    LIMIT ?
                    """,
                arguments: [pattern, playlistID.value, limit]
            )
        }
        return records.map { $0.toDomain() }
    }

    // MARK: - Gözlem
    //
    // Offline-first akışın kalbi: senkronizasyon veritabanına yazdıkça
    // ekran kendini tazeler. UI "yenile" demek zorunda kalmaz.

    public nonisolated func observeChannels(
        playlistID: Playlist.ID,
        categoryID: MediaCategory.ID?
    ) -> AsyncStream<[Channel]> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { db in
                try Self.channelRequest(playlistID: playlistID, categoryID: categoryID)
                    .fetchAll(db)
            }

            let task = Task {
                do {
                    for try await records in observation.values(in: database.writer) {
                        continuation.yield(records.map { $0.toDomain() })
                    }
                } catch {
                    // Gözlem koparsa sessiz kalma — ekran donmuş görünür,
                    // sebebi loglanmazsa teşhis edilemez.
                    Log.database.error("Kanal gözlemi durdu: \(String(describing: error))")
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Sorgu kurucu
    //
    // `static`: hem izole metotlardan hem de `nonisolated` gözlemden
    // aynı sorgunun kullanılabilmesi için.

    private static func channelRequest(
        playlistID: Playlist.ID,
        categoryID: MediaCategory.ID?
    ) -> QueryInterfaceRequest<ChannelRecord> {
        var request = ChannelRecord.filter(Column("playlistId") == playlistID.value)
        if let categoryID {
            request = request.filter(Column("categoryId") == categoryID.value)
        }
        // Sıralama SABİT: sayfalı yükleme sırasında liste kaymasın.
        // (Referans projede "filmler sürekli değişiyor" şikâyetinin sebebi buydu.)
        return request.order(Column("sortOrder"), Column("name"))
    }
}
