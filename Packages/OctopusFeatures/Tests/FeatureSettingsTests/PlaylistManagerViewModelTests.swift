import XCTest
import OctopusDomain
@testable import FeatureSettings

/// Kaynak yönetimi: listeleme, etkinleştirme, silme sonrası davranış.
@MainActor
final class PlaylistManagerViewModelTests: XCTestCase {

    private var playlists: StubPlaylistRepository!
    private var sync: NoopSync!

    override func setUp() async throws {
        playlists = StubPlaylistRepository()
        sync = NoopSync()
    }

    private func makeViewModel(now: Date = Date(timeIntervalSince1970: 100_000)) -> PlaylistManagerViewModel {
        PlaylistManagerViewModel(
            dependencies: SettingsDependencies(
                playlists: playlists,
                sync: sync,
                progress: NoopProgress(),
                history: NoopHistory()
            ),
            now: { now }
        )
    }

    // MARK: - Listeleme

    func test_load_showsActiveMarker() async {
        playlists.storage = [
            makePlaylist(id: "p1", name: "Ev", isActive: true),
            makePlaylist(id: "p2", name: "Yedek", isActive: false)
        ]

        let viewModel = makeViewModel()
        await viewModel.load()

        XCTAssertEqual(viewModel.rows.map(\.name), ["Ev", "Yedek"])
        XCTAssertEqual(viewModel.rows.filter(\.isActive).count, 1)
        XCTAssertTrue(viewModel.rows[0].isActive)
    }

    func test_detailText_describesEachSourceKind() {
        XCTAssertEqual(
            PlaylistManagerViewModel.detailText(
                for: .xtream(host: URL(string: "http://panel.example.com:8080")!, username: "ali")
            ),
            "ali · panel.example.com"
        )
        XCTAssertEqual(
            PlaylistManagerViewModel.detailText(
                for: .m3u(url: URL(string: "http://liste.example.com/p.m3u")!)
            ),
            "liste.example.com"
        )
        XCTAssertEqual(
            PlaylistManagerViewModel.detailText(for: .activationCode(code: "X")),
            "Aktivasyon kodu"
        )
    }

    // MARK: - Zaman ifadesi

    func test_lastSyncedText_readsNaturally() {
        let now = Date(timeIntervalSince1970: 100_000)
        let viewModel = makeViewModel(now: now)

        XCTAssertEqual(viewModel.lastSyncedText(nil), "Henüz güncellenmedi")
        XCTAssertEqual(
            viewModel.lastSyncedText(now.addingTimeInterval(-30)),
            "Az önce güncellendi"
        )
        XCTAssertEqual(
            viewModel.lastSyncedText(now.addingTimeInterval(-600)),
            "10 dakika önce güncellendi"
        )
        XCTAssertEqual(
            viewModel.lastSyncedText(now.addingTimeInterval(-3 * 3_600)),
            "3 saat önce güncellendi"
        )
        XCTAssertEqual(
            viewModel.lastSyncedText(now.addingTimeInterval(-2 * 86_400)),
            "2 gün önce güncellendi"
        )
    }

    func test_lastSyncedText_handlesFutureDateGracefully() {
        // Cihaz saati geriye alınmışsa negatif fark oluşur; "-5 dakika önce"
        // gibi bir metin gösterilmemeli.
        let now = Date(timeIntervalSince1970: 100_000)
        let viewModel = makeViewModel(now: now)
        XCTAssertEqual(
            viewModel.lastSyncedText(now.addingTimeInterval(300)),
            "Az önce güncellendi"
        )
    }

    // MARK: - Etkinleştirme

    func test_activate_switchesActiveSource() async {
        playlists.storage = [
            makePlaylist(id: "p1", name: "Ev", isActive: true),
            makePlaylist(id: "p2", name: "Yedek", isActive: false)
        ]

        let viewModel = makeViewModel()
        await viewModel.load()
        await viewModel.activate("p2")

        let active = viewModel.rows.filter(\.isActive)
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active.first?.name, "Yedek")
    }

    // MARK: - Silme

    func test_deletingActiveSource_activatesAnotherOne() async {
        // Aktif kaynak silinince uygulama içeriksiz kalmamalı.
        playlists.storage = [
            makePlaylist(id: "p1", name: "Ev", isActive: true),
            makePlaylist(id: "p2", name: "Yedek", isActive: false)
        ]

        let viewModel = makeViewModel()
        await viewModel.load()
        await viewModel.delete("p1")

        XCTAssertEqual(viewModel.rows.count, 1)
        XCTAssertTrue(viewModel.rows[0].isActive, "Kalan kaynak etkinleştirilmeli")
    }

    func test_deletingLastSource_leavesEmptyList() async {
        playlists.storage = [makePlaylist(id: "p1", name: "Tek", isActive: true)]

        let viewModel = makeViewModel()
        await viewModel.load()
        await viewModel.delete("p1")

        XCTAssertTrue(viewModel.rows.isEmpty)
        XCTAssertNil(viewModel.errorMessage, "Son kaynağın silinmesi hata değil")
    }

    // MARK: - Yenileme

    func test_resync_reportsFailureWithoutLosingList() async {
        playlists.storage = [makePlaylist(id: "p1", name: "Ev", isActive: true)]
        sync.error = AppError.network(reason: "kopuk")

        let viewModel = makeViewModel()
        await viewModel.load()
        await viewModel.resync("p1")

        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.rows.count, 1, "Hata listeyi boşaltmamalı")
        XCTAssertNil(viewModel.syncingID, "Gösterge temizlenmeli")
    }

    // MARK: - Yardımcılar

    private func makePlaylist(id: String, name: String, isActive: Bool) -> Playlist {
        Playlist(
            id: Playlist.ID(id),
            name: name,
            kind: .m3u(url: URL(string: "http://liste.example.com/p.m3u")!),
            createdAt: Date(timeIntervalSince1970: 0),
            isActive: isActive
        )
    }
}

// MARK: - Sahteler

private final class StubPlaylistRepository: PlaylistRepository, @unchecked Sendable {

    var storage: [Playlist] = []

    func all() async throws -> [Playlist] { storage }
    func playlist(id: Playlist.ID) async throws -> Playlist? { storage.first { $0.id == id } }
    func activePlaylist() async throws -> Playlist? { storage.first(where: \.isActive) }
    func add(_ playlist: Playlist, password: String?) async throws { storage.append(playlist) }
    func update(_ playlist: Playlist) async throws {}

    func setActive(id: Playlist.ID) async throws {
        for index in storage.indices {
            storage[index].isActive = (storage[index].id == id)
        }
    }

    func delete(id: Playlist.ID) async throws {
        storage.removeAll { $0.id == id }
    }
}

private final class NoopSync: ContentSyncing, @unchecked Sendable {
    var error: Error?
    func sync(playlistID: Playlist.ID) async throws { if let error { throw error } }
    func syncEPG(playlistID: Playlist.ID) async throws {}
    func observeProgress(playlistID: Playlist.ID) -> AsyncStream<SyncStage> {
        AsyncStream { $0.finish() }
    }
}

private struct NoopProgress: PlaybackProgressRepository {
    func progress(for source: PlaybackItem.Source) async throws -> PlaybackProgress? { nil }
    func save(_ progress: PlaybackProgress, for source: PlaybackItem.Source) async throws {}
    func continueWatching(playlistID: Playlist.ID, limit: Int) async throws -> [PlaybackProgress] { [] }
    func clear(for source: PlaybackItem.Source) async throws {}
    func clearAll() async throws {}
}

private struct NoopHistory: WatchHistoryRepository {
    func record(_ source: PlaybackItem.Source, at date: Date) async throws {}
    func recentChannels(playlistID: Playlist.ID, limit: Int) async throws -> [Channel] { [] }
    func clearAll() async throws {}
}
