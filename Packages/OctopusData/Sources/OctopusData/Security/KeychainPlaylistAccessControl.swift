import Foundation
import OctopusCore
import OctopusDomain

/// Liste PIN'ini düz metin yerine tuzlu özet olarak Keychain'de saklar.
public actor KeychainPlaylistAccessControl: PlaylistAccessControlling {

    private let secrets: SecretStore
    private var unlockedIDs: Set<Playlist.ID> = []

    public init(secrets: SecretStore) {
        self.secrets = secrets
    }

    public func isProtected(_ playlistID: Playlist.ID) async -> Bool {
        do {
            let storedHash = try secrets.read(for: hashKey(playlistID))
            return storedHash != nil
        } catch {
            // ⚠️ Okuma hatasında "korumasız" demek kapıyı tamamen açardı:
            // `isUnlocked` true döner, PIN ekranı hiç çizilmez. Şüphede
            // kalınca korumalı sayılır — kilit ancak PIN ile açılır.
            Log.app.error("Liste kilidi okunamadı: \(String(describing: error))")
            return true
        }
    }

    public func isUnlocked(_ playlistID: Playlist.ID) async -> Bool {
        guard await isProtected(playlistID) else { return true }
        return unlockedIDs.contains(playlistID)
    }

    public func configure(_ playlistID: Playlist.ID, pin: String) async throws {
        guard let normalized = Self.normalizePIN(pin) else {
            throw PlaylistAccessError.invalidPIN
        }

        let salt = KeychainParentalControl.makeSalt()
        let hash = KeychainParentalControl.hash(pin: normalized, salt: salt)
        do {
            try secrets.save(hash, for: hashKey(playlistID))
            try secrets.save(salt, for: saltKey(playlistID))
        } catch {
            try? secrets.delete(for: hashKey(playlistID))
            try? secrets.delete(for: saltKey(playlistID))
            throw PlaylistAccessError.storageFailure
        }
        // Kurulumu webde yapan kişi ile uygulamayı açan kişi aynı varsayılmaz.
        // Kod çözüldükten sonra PIN mutlaka uygulamada yeniden sorulur.
        unlockedIDs.remove(playlistID)
    }

    @discardableResult
    public func unlock(_ playlistID: Playlist.ID, with pin: String) async -> Bool {
        guard let normalized = Self.normalizePIN(pin),
              let storedHash = try? secrets.read(for: hashKey(playlistID)),
              let salt = try? secrets.read(for: saltKey(playlistID))
        else { return false }

        let candidate = KeychainParentalControl.hash(pin: normalized, salt: salt)
        guard KeychainParentalControl.constantTimeEquals(candidate, storedHash) else {
            return false
        }
        unlockedIDs.insert(playlistID)
        return true
    }

    public func lockAll() async {
        unlockedIDs.removeAll()
    }

    public func remove(_ playlistID: Playlist.ID) async {
        try? secrets.delete(for: hashKey(playlistID))
        try? secrets.delete(for: saltKey(playlistID))
        unlockedIDs.remove(playlistID)
    }

    private func hashKey(_ id: Playlist.ID) -> String {
        "playlist.lock.\(id.value).hash"
    }

    private func saltKey(_ id: Playlist.ID) -> String {
        "playlist.lock.\(id.value).salt"
    }
}
