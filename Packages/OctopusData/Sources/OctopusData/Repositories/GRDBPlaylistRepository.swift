import Foundation
import GRDB
import OctopusCore
import OctopusDomain

/// Kaynak (playlist) deposu — SQLite destekli.
///
/// ⚠️ Parolalar bu depoda **tutulmaz**. Veritabanına yalnızca kaynak
/// tanımı yazılır; parola `SecretStore` (Keychain) üzerinden yönetilir.
public actor GRDBPlaylistRepository: PlaylistRepository {

    private let database: AppDatabase
    private let secrets: SecretStore

    public init(database: AppDatabase, secrets: SecretStore) {
        self.database = database
        self.secrets = secrets
    }

    // MARK: - Okuma

    public func all() async throws -> [Playlist] {
        let records = try await database.read { db in
            try PlaylistRecord.order(Column("createdAt").desc).fetchAll(db)
        }
        return try records.map { try $0.toDomain() }
    }

    public func playlist(id: Playlist.ID) async throws -> Playlist? {
        let record = try await database.read { db in
            try PlaylistRecord.fetchOne(db, key: id.value)
        }
        return try record?.toDomain()
    }

    public func activePlaylist() async throws -> Playlist? {
        let record = try await database.read { db in
            try PlaylistRecord.filter(Column("isActive") == true).fetchOne(db)
        }
        return try record?.toDomain()
    }

    // MARK: - Yazma

    public func add(_ playlist: Playlist, password: String?) async throws {
        // Önce parola: veritabanına yazıp Keychain'de başarısız olursak
        // parolasız bir kaynak kalırdı ve kullanıcı sebebini anlayamazdı.
        if let password {
            try storePassword(password, for: playlist)
        }

        do {
            try await database.write { db in
                try PlaylistRecord(playlist).insert(db)
            }
        } catch {
            // Veritabanı yazımı başarısızsa Keychain'de yetim kayıt bırakma.
            try? secrets.delete(for: playlist.credentialKey)
            throw error
        }
    }

    public func update(_ playlist: Playlist) async throws {
        let updated = try await database.write { db -> Bool in
            let record = PlaylistRecord(playlist)
            guard try PlaylistRecord.exists(db, key: record.id) else { return false }
            try record.update(db)
            return true
        }
        guard updated else { throw AppError.notFound }
    }

    /// Tek kaynak aktif olabilir.
    ///
    /// Referans projede bu işlem tüm kayıtları tek tek güncelliyordu;
    /// burada iki hedefli sorgu yeterli.
    public func setActive(id: Playlist.ID) async throws {
        try await database.write { db in
            try db.execute(
                sql: "UPDATE playlist SET isActive = 0 WHERE isActive = 1"
            )
            try db.execute(
                sql: "UPDATE playlist SET isActive = 1 WHERE id = ?",
                arguments: [id.value]
            )
        }
    }

    /// Kaynağı ve ona ait tüm içeriği siler.
    ///
    /// Kategori/kanal/film/dizi satırları yabancı anahtar cascade ile gider.
    /// Favoriler ve izleme ilerlemesi **bilinçli olarak korunur** —
    /// kullanıcı kaynağı yeniden eklerse verisi yerinde bulunur.
    public func delete(id: Playlist.ID) async throws {
        try await database.write { db in
            _ = try PlaylistRecord.deleteOne(db, key: id.value)
        }
        // Parola artık sahipsiz; Keychain'de bırakılmaz.
        try? secrets.delete(for: "playlist.\(id.value)")
    }

    // MARK: - Doğrulama

    public func validate(_ playlist: Playlist, password: String?) async throws -> ProviderAccount {
        // Faz 2: ContentProvider üzerinden gerçek kimlik doğrulaması yapılacak.
        throw AppError.unknown(reason: "Kaynak doğrulama Faz 2'de eklenecek")
    }

    // MARK: - Yardımcılar

    private func storePassword(_ password: String, for playlist: Playlist) throws {
        do {
            try secrets.save(password, for: playlist.credentialKey)
        } catch {
            Log.database.error("Parola Keychain'e yazılamadı: \(String(describing: error))")
            throw AppError.storage(reason: "Parola güvenli alana kaydedilemedi")
        }
    }
}
