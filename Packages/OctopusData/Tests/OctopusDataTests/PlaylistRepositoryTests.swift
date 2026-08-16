import XCTest
import GRDB
import OctopusCore
import OctopusDomain
@testable import OctopusData

/// Kaynak deposu ve satır dönüşümleri.
final class PlaylistRepositoryTests: XCTestCase {

    private var database: AppDatabase!
    private var secrets: FakeSecretStore!
    private var repository: GRDBPlaylistRepository!

    override func setUp() async throws {
        database = try AppDatabase.makeInMemory()
        secrets = FakeSecretStore()
        repository = GRDBPlaylistRepository(database: database, secrets: secrets)
    }

    // MARK: - Satır dönüşümü
    //
    // Her kaynak türü ayrı kolonlara açılıyor; gidiş-dönüş kayıpsız olmalı.

    func test_recordRoundTrip_preservesEveryKind() throws {
        let kinds: [Playlist.Kind] = [
            .xtream(host: URL(string: "http://panel.example.com:8080")!, username: "user"),
            .m3u(url: URL(string: "http://example.com/list.m3u")!),
            .m3uLocalFile(fileName: "liste.m3u"),
            .activationCode(code: "ABC-123")
        ]

        for kind in kinds {
            let original = Playlist(
                id: "p1",
                name: "Kaynak",
                kind: kind,
                epgURL: URL(string: "http://example.com/epg.xml"),
                createdAt: Date(timeIntervalSince1970: 1_000),
                isActive: true
            )
            let restored = try PlaylistRecord(original).toDomain()
            XCTAssertEqual(restored, original, "\(kind) türü gidiş-dönüşte bozuldu")
        }
    }

    func test_corruptRow_throwsInsteadOfSilentlyReturningNil() {
        // Xtream kaydında sunucu adresi eksik — sessizce nil dönmek yerine
        // hata fırlatmalı ki bozuk veri fark edilebilsin.
        let record = PlaylistRecord(
            id: "p1", name: "Bozuk", kindType: "xtream",
            host: nil, username: nil, url: nil, fileName: nil,
            activationCode: nil, epgURL: nil,
            createdAt: Date(timeIntervalSince1970: 0),
            lastSyncedAt: nil, isActive: false
        )
        XCTAssertThrowsError(try record.toDomain())
    }

    func test_unknownKindType_throws() {
        let record = PlaylistRecord(
            id: "p1", name: "Gelecekten", kindType: "quantum_stream",
            host: nil, username: nil, url: nil, fileName: nil,
            activationCode: nil, epgURL: nil,
            createdAt: Date(timeIntervalSince1970: 0),
            lastSyncedAt: nil, isActive: false
        )
        XCTAssertThrowsError(try record.toDomain())
    }

    // MARK: - Depo davranışı

    func test_add_storesPasswordInKeychainNotDatabase() async throws {
        let playlist = makePlaylist(id: "p1")
        try await repository.add(playlist, password: "gizli123")

        // Parola Keychain'de
        XCTAssertEqual(try secrets.read(for: playlist.credentialKey), "gizli123")

        // Veritabanının HİÇBİR kolonunda parola geçmemeli
        let dump = try await database.read { db -> String in
            let row = try Row.fetchOne(db, sql: "SELECT * FROM playlist WHERE id = 'p1'")
            return row.map { String(describing: $0) } ?? ""
        }
        XCTAssertFalse(dump.contains("gizli123"), "Parola veritabanına sızmış")
    }

    func test_setActive_leavesExactlyOneActive() async throws {
        try await repository.add(makePlaylist(id: "p1", isActive: true), password: nil)
        try await repository.add(makePlaylist(id: "p2"), password: nil)
        try await repository.add(makePlaylist(id: "p3"), password: nil)

        try await repository.setActive(id: "p3")

        let all = try await repository.all()
        let active = all.filter(\.isActive)
        XCTAssertEqual(active.count, 1, "Aynı anda tek kaynak aktif olabilir")
        XCTAssertEqual(active.first?.id, "p3")

        let fetched = try await repository.activePlaylist()
        XCTAssertEqual(fetched?.id, "p3")
    }

    func test_update_onMissingPlaylist_throwsNotFound() async throws {
        do {
            try await repository.update(makePlaylist(id: "yok"))
            XCTFail("Var olmayan kaydın güncellenmesi hata vermeli")
        } catch let error as AppError {
            XCTAssertEqual(error, .notFound)
        }
    }

    func test_delete_removesPasswordFromKeychain() async throws {
        let playlist = makePlaylist(id: "p1")
        try await repository.add(playlist, password: "gizli123")
        try await repository.delete(id: "p1")

        XCTAssertNil(try secrets.read(for: playlist.credentialKey), "Sahipsiz parola kalmamalı")
        let remaining = try await repository.all()
        XCTAssertTrue(remaining.isEmpty)
    }

    // MARK: - Yardımcılar

    private func makePlaylist(id: String, isActive: Bool = false) -> Playlist {
        Playlist(
            id: Playlist.ID(id),
            name: "Kaynak \(id)",
            kind: .xtream(host: URL(string: "http://panel.example.com")!, username: "u"),
            createdAt: Date(timeIntervalSince1970: 1_000),
            isActive: isActive
        )
    }
}

/// Testlerde gerçek Keychain'e dokunmamak için sahte depo.
///
/// `failingKeys` ile tek tek anahtarlar patlatılabilir: Keychain okuma/yazma
/// hatasının kilidi **açmadığını** doğrulamak için gerekiyor.
final class FakeSecretStore: SecretStore, @unchecked Sendable {

    private var storage: [String: String] = [:]
    private var failingReads: Set<String> = []
    private var failingWrites: Set<String> = []
    private let lock = NSLock()

    /// Bu anahtarların okunması `SecretStoreError` fırlatır.
    func failReads(for keys: String...) {
        lock.lock(); defer { lock.unlock() }
        failingReads.formUnion(keys)
    }

    /// Bu anahtarların yazılması `SecretStoreError` fırlatır.
    func failWrites(for keys: String...) {
        lock.lock(); defer { lock.unlock() }
        failingWrites.formUnion(keys)
    }

    func save(_ secret: String, for key: String) throws {
        lock.lock(); defer { lock.unlock() }
        guard !failingWrites.contains(key) else {
            throw SecretStoreError.keychain(status: -34018)
        }
        storage[key] = secret
    }

    func read(for key: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        guard !failingReads.contains(key) else {
            throw SecretStoreError.keychain(status: -34018)
        }
        return storage[key]
    }

    func delete(for key: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[key] = nil
    }
}
