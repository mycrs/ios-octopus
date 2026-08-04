import XCTest
import OctopusCore
import OctopusData
import OctopusDomain
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
}

/// Testte Keychain'e dokunmamak için boş depo.
private struct KeychainlessSecretStore: SecretStore {
    func save(_ secret: String, for key: String) throws {}
    func read(for key: String) throws -> String? { nil }
    func delete(for key: String) throws {}
}
