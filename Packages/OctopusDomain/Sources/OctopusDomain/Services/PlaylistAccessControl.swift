import Foundation

/// Hızlı kurulumda korunan bir listenin uygulama içi erişim kapısı.
///
/// Bu PIN, +18 içerik PIN'inden ayrıdır: biri bütün listeyi açar, diğeri
/// yalnızca hassas içerik görünürlüğünü yönetir.
public protocol PlaylistAccessControlling: Sendable {
    func isProtected(_ playlistID: Playlist.ID) async -> Bool
    func isUnlocked(_ playlistID: Playlist.ID) async -> Bool
    func configure(_ playlistID: Playlist.ID, pin: String) async throws
    @discardableResult
    func unlock(_ playlistID: Playlist.ID, with pin: String) async -> Bool
    func lockAll() async
    func remove(_ playlistID: Playlist.ID) async
}

public enum PlaylistAccessError: Error, Equatable, Sendable {
    case invalidPIN
    case storageFailure
}

extension PlaylistAccessControlling {
    /// Hızlı kurulum formu tam dört rakam üretir.
    public static func normalizePIN(_ raw: String) -> String? {
        PlaylistAccessPIN.normalize(raw)
    }
}

public enum PlaylistAccessPIN {
    public static func normalize(_ raw: String) -> String? {
        let pin = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard pin.count == 4, pin.allSatisfy(\.isNumber) else { return nil }
        return pin
    }
}

/// Önizleme ve bağımsız feature testlerinde liste kilidi yoktur.
public actor OpenPlaylistAccessControl: PlaylistAccessControlling {
    public init() {}
    public func isProtected(_ playlistID: Playlist.ID) async -> Bool { false }
    public func isUnlocked(_ playlistID: Playlist.ID) async -> Bool { true }
    public func configure(_ playlistID: Playlist.ID, pin: String) async throws {}
    @discardableResult
    public func unlock(_ playlistID: Playlist.ID, with pin: String) async -> Bool { true }
    public func lockAll() async {}
    public func remove(_ playlistID: Playlist.ID) async {}
}
