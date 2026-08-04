import XCTest
@testable import Octopus

/// Uygulama kabuğu testleri.
///
/// Asıl mantık testleri paketlerin kendi test hedeflerindedir
/// (`OctopusDomainTests`, `OctopusPlaybackTests`) ve simülatör gerektirmez.
/// Burada yalnızca bağlama (composition) doğrulanır.
@MainActor
final class AppSmokeTests: XCTestCase {

    func test_container_buildsWithoutCrashing() {
        let container = AppContainer()
        XCTAssertFalse(container.router.needsOnboarding, "Başlangıç durumu false olmalı")
    }

    func test_container_producesDependenciesForEveryFeature() {
        let container = AppContainer()

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

    func test_bootstrap_withoutPlaylistRequestsOnboarding() async {
        let container = AppContainer()
        await container.bootstrap()
        XCTAssertTrue(
            container.router.needsOnboarding,
            "Kayıtlı kaynak yokken onboarding gösterilmeli"
        )
    }
}
