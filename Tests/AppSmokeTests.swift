import XCTest
import OctopusCore
import OctopusData
import OctopusDomain
import OctopusNavigation
@testable import Octopus

/// Uygulama kabuğu testleri.
///
/// Asıl mantık testleri paketlerin kendi test hedeflerindedir
/// (`OctopusDomainTests`, `OctopusDataTests`, `OctopusPlaybackTests`).
/// Burada yalnızca bağlama (composition) doğrulanır.
///
/// ⚠️ Veritabanı **enjekte edilir**: aksi halde testler cihazdaki gerçek
/// dosyayı açar, birbirini kirletir ve sıraya bağımlı hale gelir.
@MainActor
final class AppSmokeTests: XCTestCase {

    private func makeContainer() throws -> AppContainer {
        AppContainer(database: try AppDatabase.makeInMemory())
    }

    func test_container_buildsWithWorkingStorage() throws {
        let container = try makeContainer()
        XCTAssertNil(container.startupFailure, "Depolama kurulmalıydı")
        XCTAssertFalse(container.router.needsOnboarding, "Başlangıç durumu false olmalı")
    }

    func test_container_producesDependenciesForEveryFeature() throws {
        let container = try makeContainer()

        // Her feature'ın bağımlılık paketi üretilebilmeli.
        // Bir feature yeni bir depo isterse bu test derlenmez → eksik bağlama fark edilir.
        _ = container.makeOnboardingDependencies()
        _ = container.makeHomeDependencies()
        _ = container.makeLiveDependencies()
        _ = container.makeVODDependencies()
        _ = container.makeSeriesDependencies()
        _ = container.makeSearchDependencies()
        _ = container.makePlayerDependencies()
        _ = container.makeSettingsDependencies()
    }

    func test_bootstrap_withoutPlaylistRequestsOnboarding() async throws {
        let container = try makeContainer()
        await container.bootstrap()
        XCTAssertTrue(
            container.router.needsOnboarding,
            "Kayıtlı kaynak yokken onboarding gösterilmeli"
        )
    }

    /// Faz 1'in asıl sınavı: uygulama artık gerçek veritabanına bağlı.
    /// Kaynak eklenince açılış onboarding'e değil ana ekrana gitmeli.
    func test_bootstrap_withStoredPlaylist_skipsOnboarding() async throws {
        let database = try AppDatabase.makeInMemory()
        let repository = GRDBPlaylistRepository(
            database: database,
            secrets: KeychainlessSecretStore()
        )
        try await repository.add(
            Playlist(
                id: "p1",
                name: "Test",
                kind: .m3u(url: URL(string: "http://example.com/list.m3u")!),
                createdAt: Date(timeIntervalSince1970: 0),
                isActive: true
            ),
            password: nil
        )

        let container = AppContainer(database: database)
        await container.bootstrap()

        XCTAssertFalse(
            container.router.needsOnboarding,
            "Kayıtlı aktif kaynak varken onboarding gösterilmemeli"
        )
    }

    func test_sourceTransitionClosesOldRoutesAndRebuildsFeatureRoots() async throws {
        let database = try AppDatabase.makeInMemory()
        let repository = GRDBPlaylistRepository(database: database, secrets: KeychainlessSecretStore())
        let first = Playlist(id: "p1", name: "First", kind: .m3u(url: URL(string: "https://example.com/first.m3u")!), createdAt: Date(), isActive: true)
        let second = Playlist(id: "p2", name: "Second", kind: .m3u(url: URL(string: "https://example.com/second.m3u")!), createdAt: Date())
        try await repository.add(first, password: nil)
        try await repository.add(second, password: nil)
        let container = AppContainer(database: database)
        let settings = container.makeSettingsDependencies()
        await settings.notifyPlaylistChanged()
        let revision = container.contentProtectionRevision
        container.router.push(.movieDetail("old-movie"), in: .movies)
        container.router.presentPlayer(.movie("old-movie"))
        try await repository.setActive(id: "p2")

        await settings.notifyPlaylistChanged()

        XCTAssertGreaterThan(container.contentProtectionRevision, revision)
        XCTAssertTrue(container.router.paths.isEmpty)
        XCTAssertNil(container.router.player)
        XCTAssertEqual(container.activePlaylistName, "Second")
        XCTAssertFalse(container.router.needsOnboarding)
    }

    func test_removingLastSourceReturnsToOnboarding() async throws {
        let database = try AppDatabase.makeInMemory()
        let repository = GRDBPlaylistRepository(database: database, secrets: KeychainlessSecretStore())
        try await repository.add(Playlist(id: "only", name: "Only", kind: .m3u(url: URL(string: "https://example.com/list.m3u")!), createdAt: Date(), isActive: true), password: nil)
        let container = AppContainer(database: database)
        let settings = container.makeSettingsDependencies()
        await settings.notifyPlaylistChanged()
        try await repository.delete(id: "only")

        await settings.notifyPlaylistChanged()

        XCTAssertTrue(container.router.needsOnboarding)
        XCTAssertNil(container.activePlaylistName)
        XCTAssertFalse(container.isActivePlaylistLocked)
    }

    func test_publicSampleInstallationUsesNormalCatalogAndPreservesPersonalSource() async throws {
        let database = try AppDatabase.makeInMemory()
        let repository = GRDBPlaylistRepository(database: database, secrets: KeychainlessSecretStore())
        try await repository.add(Playlist(id: "personal", name: "Personal", kind: .m3u(url: URL(string: "https://example.com/list.m3u")!), createdAt: Date(), isActive: true), password: nil)
        let container = AppContainer(database: database)
        let settings = container.makeSettingsDependencies()
        await settings.notifyPlaylistChanged()
        let install = try XCTUnwrap(settings.installSampleLibrary)

        try await install()

        let active = try await repository.activePlaylist()
        XCTAssertEqual(active?.id, SampleLibraryCatalog.playlistID)
        let personal = try await repository.playlist(id: "personal")
        XCTAssertNotNil(personal)
        let vod = container.makeVODDependencies().vod
        let movies = try await vod.movies(playlistID: SampleLibraryCatalog.playlistID, categoryID: nil, limit: 20, offset: 0)
        XCTAssertFalse(movies.isEmpty)
        let live = container.makeLiveDependencies()
        let channels = try await live.channels.channels(playlistID: SampleLibraryCatalog.playlistID, categoryID: nil)
        let channel = try XCTUnwrap(channels.first)
        let epgID = try XCTUnwrap(channel.epgChannelID)
        let guide = try await live.epg.nowPlaying(playlistID: SampleLibraryCatalog.playlistID, epgChannelID: epgID, at: Date())
        XCTAssertNotNil(guide)
        let series = try await container.makeSeriesDependencies().series.series(playlistID: SampleLibraryCatalog.playlistID, categoryID: nil, limit: 20, offset: 0)
        XCTAssertFalse(series.isEmpty)

        try await install()
        let all = try await repository.all()
        XCTAssertEqual(all.count, 2, "Örnek kurulumu kişisel listeyi silmemeli veya aynı örnek kaynağı çoğaltmamalı")
    }

    func test_sourceAccessRemainsGatedUntilProtectedLookupCompletes() async throws {
        let database = try AppDatabase.makeInMemory()
        let repository = GRDBPlaylistRepository(database: database, secrets: KeychainlessSecretStore())
        try await repository.add(Playlist(id: "first", name: "First", kind: .sampleLibrary, createdAt: Date(), isActive: true), password: nil)
        try await repository.add(Playlist(id: "protected", name: "Protected", kind: .sampleLibrary, createdAt: Date()), password: nil)
        let access = DelayedProtectedAccess()
        let container = AppContainer(database: database, playlistAccessOverride: access)
        let settings = container.makeSettingsDependencies()
        await settings.notifyPlaylistChanged()
        XCTAssertFalse(container.isResolvingPlaylistAccess)
        try await repository.setActive(id: "protected")
        let transition = Task { await settings.notifyPlaylistChanged() }
        await access.waitUntilLookupStarted()

        XCTAssertTrue(container.isResolvingPlaylistAccess, "Yeni katalog PIN durumu çözülmeden görünür olmamalı")
        XCTAssertEqual(container.activePlaylistName, "Protected")
        await access.completeLookup()
        await transition.value

        XCTAssertFalse(container.isResolvingPlaylistAccess)
        XCTAssertTrue(container.isActivePlaylistLocked)
    }

}

/// Açılış sekmesi tercihi — kalıcılık ve bozuk değere dayanıklılık.
@MainActor
final class StartupTabTests: XCTestCase {

    /// Her test kendi kutusunda çalışır; `.standard` kirlenmemeli.
    private func makeStore(_ name: String = UUID().uuidString) throws -> UserDefaults {
        try XCTUnwrap(UserDefaults(suiteName: name))
    }

    func test_defaultsToHome() throws {
        let router = AppRouter(store: try makeStore())
        XCTAssertEqual(router.startupTab, .home)
        XCTAssertEqual(router.selectedTab, .home)
    }

    func test_savedPreferenceIsRestored() throws {
        let store = try makeStore()

        let first = AppRouter(store: store)
        first.startupTab = .live

        let second = AppRouter(store: store)
        XCTAssertEqual(second.startupTab, .live)
        XCTAssertEqual(second.selectedTab, .live, "Uygulama seçilen sekmeyle açılmalı")
    }

    func test_removedTabFallsBackToHome() throws {
        // "settings" ve "search" bir zamanlar birer sekmeydi, artık
        // AppTab case'i değiller — eski sürümden kalmış bir kayıt olabilir.
        let store = try makeStore()
        store.set("settings", forKey: "startup.tab")

        let router = AppRouter(store: store)
        XCTAssertEqual(router.startupTab, .home)
    }

    func test_garbageValueFallsBackToHome() throws {
        let store = try makeStore()
        store.set("bozuk", forKey: "startup.tab")

        XCTAssertEqual(AppRouter(store: store).startupTab, .home)
    }

    func test_clearOpenScreensKeepsTabButClosesStacks() throws {
        // Ebeveyn kilidi kurulunca çağrılır: kullanıcı bulunduğu sekmede
        // kalmalı ama yığında duran içerik ekranları kapanmalı.
        let router = AppRouter(store: try makeStore())
        router.selectedTab = .favorites
        router.push(.movieDetail("m1"), in: .movies)
        router.presentPlayer(.movie("m1"))

        router.clearOpenScreens()

        XCTAssertEqual(router.selectedTab, .favorites, "Sekme korunmalı")
        XCTAssertNil(router.player)
        XCTAssertTrue(router.paths.isEmpty, "Yığınlar temizlenmeli")
    }

    func test_playlistChangeReturnsToStartupTab() throws {
        let router = AppRouter(store: try makeStore())
        router.startupTab = .movies
        router.selectedTab = .favorites

        router.resetAfterPlaylistChange()

        XCTAssertEqual(router.selectedTab, .movies, "Ana sayfaya değil, tercihe dönmeli")
    }
}

/// Testte Keychain'e dokunmamak için boş depo.
private struct KeychainlessSecretStore: SecretStore {
    func save(_ secret: String, for key: String) throws {}
    func read(for key: String) throws -> String? { nil }
    func delete(for key: String) throws {}
}

private actor DelayedProtectedAccess: PlaylistAccessControlling {
    private var started = false
    private var arrival: CheckedContinuation<Void, Never>?
    private var lookup: CheckedContinuation<Bool, Never>?

    func isProtected(_ id: Playlist.ID) async -> Bool {
        guard id == "protected" else { return false }
        started = true
        arrival?.resume()
        arrival = nil
        return await withCheckedContinuation { lookup = $0 }
    }
    func waitUntilLookupStarted() async {
        if started { return }
        await withCheckedContinuation { arrival = $0 }
    }
    func completeLookup() { lookup?.resume(returning: true); lookup = nil }
    func isUnlocked(_ id: Playlist.ID) async -> Bool { false }
    func configure(_ id: Playlist.ID, pin: String) async throws {}
    func unlock(_ id: Playlist.ID, with pin: String) async -> Bool { false }
    func lockAll() async {}
    func remove(_ id: Playlist.ID) async {}
}
