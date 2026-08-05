import XCTest
import OctopusDomain
@testable import FeatureSettings

/// Ayarlar: kaynak bilgisi, veri temizleme, yeniden senkronizasyon.
@MainActor
final class SettingsViewModelTests: XCTestCase {

    private var playlists: SettingsStubPlaylists!
    private var sync: SettingsStubSync!
    private var progress: SettingsStubProgress!
    private var history: SettingsStubHistory!

    private let now = Date(timeIntervalSince1970: 100_000)

    override func setUp() async throws {
        playlists = SettingsStubPlaylists()
        sync = SettingsStubSync()
        progress = SettingsStubProgress()
        history = SettingsStubHistory()
    }

    private func makeViewModel() -> SettingsViewModel {
        SettingsViewModel(
            dependencies: SettingsDependencies(
                playlists: playlists,
                sync: sync,
                progress: progress,
                history: history
            ),
            now: { self.now }
        )
    }

    private func makePlaylist(
        id: String,
        name: String,
        isActive: Bool,
        syncedAt: Date? = nil
    ) -> Playlist {
        Playlist(
            id: Playlist.ID(id),
            name: name,
            kind: .m3u(url: URL(string: "http://example.com/p.m3u")!),
            createdAt: Date(timeIntervalSince1970: 0),
            lastSyncedAt: syncedAt,
            isActive: isActive
        )
    }

    // MARK: - Kaynak bilgisi

    func test_loadShowsActivePlaylistAndCount() async {
        playlists.storage = [
            makePlaylist(id: "p1", name: "Ev", isActive: true, syncedAt: now.addingTimeInterval(-7_200)),
            makePlaylist(id: "p2", name: "Yedek", isActive: false)
        ]

        let viewModel = makeViewModel()
        await viewModel.load()

        XCTAssertEqual(viewModel.activePlaylistName, "Ev")
        XCTAssertEqual(viewModel.playlistCount, 2)
        XCTAssertEqual(viewModel.lastSyncedText, "2 saat önce")
    }

    func test_noPlaylistShowsPlaceholder() async {
        let viewModel = makeViewModel()
        await viewModel.load()

        XCTAssertNil(viewModel.activePlaylistName)
        XCTAssertEqual(viewModel.playlistCount, 0)
    }

    func test_relativeTextCoversRanges() {
        XCTAssertEqual(SettingsViewModel.relativeText(nil, now: now), "Henüz güncellenmedi")
        XCTAssertEqual(
            SettingsViewModel.relativeText(now.addingTimeInterval(-30), now: now),
            "Az önce"
        )
        XCTAssertEqual(
            SettingsViewModel.relativeText(now.addingTimeInterval(-900), now: now),
            "15 dakika önce"
        )
        XCTAssertEqual(
            SettingsViewModel.relativeText(now.addingTimeInterval(-3 * 86_400), now: now),
            "3 gün önce"
        )
        // Cihaz saati ileri alınmışsa negatif fark oluşur.
        XCTAssertEqual(
            SettingsViewModel.relativeText(now.addingTimeInterval(600), now: now),
            "Az önce"
        )
    }

    // MARK: - Veri temizleme

    func test_clearWatchHistory() async {
        let viewModel = makeViewModel()
        await viewModel.clearWatchHistory()

        XCTAssertTrue(history.wasCleared)
        XCTAssertFalse(progress.wasCleared, "İlerleme bilgileri korunmalı")
        XCTAssertNotNil(viewModel.message)
    }

    func test_clearPlaybackProgress() async {
        let viewModel = makeViewModel()
        await viewModel.clearPlaybackProgress()

        XCTAssertTrue(progress.wasCleared)
        XCTAssertFalse(history.wasCleared, "Geçmiş korunmalı")
    }

    func test_clearFailureShowsMessage() async {
        history.error = AppError.storage(reason: "disk")

        let viewModel = makeViewModel()
        await viewModel.clearWatchHistory()

        XCTAssertNotNil(viewModel.message)
        XCTAssertFalse(viewModel.isBusy, "Hata sonrası gösterge kapanmalı")
    }

    // MARK: - Yeniden senkronizasyon

    func test_resyncUsesActivePlaylist() async {
        playlists.storage = [makePlaylist(id: "p1", name: "Ev", isActive: true)]

        let viewModel = makeViewModel()
        await viewModel.resyncActivePlaylist()

        XCTAssertEqual(sync.syncedIDs, ["p1"])
    }

    func test_resyncWithoutActivePlaylistWarns() async {
        let viewModel = makeViewModel()
        await viewModel.resyncActivePlaylist()

        XCTAssertTrue(sync.syncedIDs.isEmpty)
        XCTAssertNotNil(viewModel.message)
    }
}

// MARK: - Sahteler

private final class SettingsStubPlaylists: PlaylistRepository, @unchecked Sendable {

    var storage: [Playlist] = []

    func all() async throws -> [Playlist] { storage }
    func playlist(id: Playlist.ID) async throws -> Playlist? { storage.first { $0.id == id } }
    func activePlaylist() async throws -> Playlist? { storage.first(where: \.isActive) }
    func add(_ playlist: Playlist, password: String?) async throws {}
    func update(_ playlist: Playlist) async throws {}
    func setActive(id: Playlist.ID) async throws {}
    func delete(id: Playlist.ID) async throws {}
}

private final class SettingsStubSync: ContentSyncing, @unchecked Sendable {

    private(set) var syncedIDs: [Playlist.ID] = []

    func sync(playlistID: Playlist.ID) async throws { syncedIDs.append(playlistID) }
    func syncEPG(playlistID: Playlist.ID) async throws {}
    func observeProgress(playlistID: Playlist.ID) -> AsyncStream<SyncStage> {
        AsyncStream { $0.finish() }
    }
}

private final class SettingsStubProgress: PlaybackProgressRepository, @unchecked Sendable {

    private(set) var wasCleared = false

    func progress(for source: PlaybackItem.Source) async throws -> PlaybackProgress? { nil }
    func save(_ progress: PlaybackProgress, for source: PlaybackItem.Source) async throws {}
    func continueWatching(playlistID: Playlist.ID, limit: Int) async throws -> [PlaybackProgress] { [] }
    func clear(for source: PlaybackItem.Source) async throws {}
    func clearAll() async throws { wasCleared = true }
}

private final class SettingsStubHistory: WatchHistoryRepository, @unchecked Sendable {

    private(set) var wasCleared = false
    var error: Error?

    func record(_ source: PlaybackItem.Source, at date: Date) async throws {}
    func recentChannels(playlistID: Playlist.ID, limit: Int) async throws -> [Channel] { [] }

    func clearAll() async throws {
        if let error { throw error }
        wasCleared = true
    }
}
