import OctopusDomain
import OctopusPlayback

public struct SettingsDependencies {
    public let playlists: PlaylistRepository
    public let sync: ContentSyncing
    public let progress: PlaybackProgressRepository
    public let history: WatchHistoryRepository
    /// Bayinin destek kanalları (panelden gelir).
    public let contact: ContactChannels
    public let parental: ParentalControlling
    /// Kategori görünürlük yönetimi için katalog depoları.
    public let channels: ChannelRepository?
    public let vod: VODRepository?
    public let series: SeriesRepository?
    public let playlistAccess: PlaylistAccessControlling
    public let sourceHealth: SourceHealthReading?
    public let playerDiagnostics: (@MainActor () -> PlaybackDiagnosticSnapshot?)?
    public let installSampleLibrary: (@MainActor () async throws -> Void)?
    public let activatePlaylist: @MainActor (Playlist.ID, String?) async throws -> Bool
    public let removePlaylistLock: @MainActor (Playlist.ID) async -> Void
    public let notifyPlaylistChanged: @MainActor () async -> Void
    /// Kilit durumu değişince açık katalog ekranlarını güvenle yeniler.
    public let notifyProtectionChanged: @MainActor () -> Void

    public init(
        playlists: PlaylistRepository,
        sync: ContentSyncing,
        progress: PlaybackProgressRepository,
        history: WatchHistoryRepository,
        contact: ContactChannels = .empty,
        parental: ParentalControlling = OpenParentalControl(),
        channels: ChannelRepository? = nil,
        vod: VODRepository? = nil,
        series: SeriesRepository? = nil,
        playlistAccess: PlaylistAccessControlling = OpenPlaylistAccessControl(),
        sourceHealth: SourceHealthReading? = nil,
        playerDiagnostics: (@MainActor () -> PlaybackDiagnosticSnapshot?)? = nil,
        activatePlaylist: (@MainActor (Playlist.ID, String?) async throws -> Bool)? = nil,
        removePlaylistLock: @escaping @MainActor (Playlist.ID) async -> Void = { _ in },
        notifyPlaylistChanged: @escaping @MainActor () async -> Void = {},
        notifyProtectionChanged: @escaping @MainActor () -> Void = {},
        installSampleLibrary: (@MainActor () async throws -> Void)? = nil
    ) {
        self.playlists = playlists
        self.sync = sync
        self.progress = progress
        self.history = history
        self.contact = contact
        self.parental = parental
        self.channels = channels
        self.vod = vod
        self.series = series
        self.playlistAccess = playlistAccess
        self.sourceHealth = sourceHealth
        self.playerDiagnostics = playerDiagnostics
        self.installSampleLibrary = installSampleLibrary
        self.activatePlaylist = activatePlaylist ?? { id, pin in
            if await playlistAccess.isProtected(id),
               !(await playlistAccess.isUnlocked(id)) {
                guard let pin, await playlistAccess.unlock(id, with: pin) else {
                    return false
                }
            }
            try await playlists.setActive(id: id)
            return true
        }
        self.removePlaylistLock = removePlaylistLock
        self.notifyPlaylistChanged = notifyPlaylistChanged
        self.notifyProtectionChanged = notifyProtectionChanged
    }
}
