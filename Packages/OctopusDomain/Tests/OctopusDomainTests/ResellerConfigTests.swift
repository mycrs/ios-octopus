import XCTest
@testable import OctopusDomain

/// Bayi yapılandırmasının global yapılandırmayla birleşmesi.
///
/// Bu birleşme sessizce yanlış olursa fark edilmesi zor: uygulama açılır,
/// çalışır, yalnızca **yanlış bayinin markasını** taşır. Bu yüzden
/// öncelik kuralı tek tek doğrulanıyor.
final class ResellerConfigTests: XCTestCase {

    private func makeGlobal(
        gate: ServiceGate = .open,
        branding: BrandConfiguration = .default,
        announcement: String? = nil
    ) -> RemoteAppConfig {
        RemoteAppConfig(
            announcement: announcement.flatMap(Announcement.init(message:)),
            gate: gate,
            branding: branding,
            fetchedAt: Date(timeIntervalSince1970: 0)
        )
    }

    // MARK: - Öncelik

    func test_resellerBrandingWinsOverGlobal() {
        let global = makeGlobal(
            branding: BrandConfiguration(
                primaryColorHex: "#111111",
                resellerName: "Global",
                logoURL: nil
            )
        )
        let reseller = ResellerConfig(appName: "Bayi A", primaryColorHex: "#22AA33")

        let merged = global.applying(reseller)

        XCTAssertEqual(merged.branding.primaryColorHex, "#22AA33")
        XCTAssertEqual(merged.branding.resellerName, "Bayi A")
    }

    /// Bayi bir alanı boş bıraktıysa global değer korunmalı — aksi hâlde
    /// eksik doldurulmuş bir bayi kaydı uygulamayı markasız bırakırdı.
    func test_globalSurvivesWhereResellerIsSilent() {
        let global = makeGlobal(
            branding: BrandConfiguration(
                primaryColorHex: "#111111",
                resellerName: "Global",
                logoURL: URL(string: "https://example.com/logo.png")
            )
        )
        let merged = global.applying(ResellerConfig())

        XCTAssertEqual(merged.branding.primaryColorHex, "#111111")
        XCTAssertEqual(merged.branding.resellerName, "Global")
        XCTAssertNotNil(merged.branding.logoURL)
    }

    func test_resellerAnnouncementReplacesGlobal() {
        let merged = makeGlobal(announcement: "Genel duyuru")
            .applying(ResellerConfig(announcement: "Bayi duyurusu"))

        XCTAssertEqual(merged.announcement?.message, "Bayi duyurusu")
    }

    /// Bayi duyuru yazmadıysa genel duyuru görünmeye devam etmeli.
    func test_globalAnnouncementSurvivesEmptyResellerAnnouncement() {
        let merged = makeGlobal(announcement: "Genel duyuru")
            .applying(ResellerConfig(announcement: nil))

        XCTAssertEqual(merged.announcement?.message, "Genel duyuru")
    }

    // MARK: - Kapılar

    /// ⚠️ En kritik davranış: bayi iOS'u açmadıysa uygulama içeriğe girmemeli.
    func test_iosDisabledBlocksAccess() {
        let merged = makeGlobal().applying(ResellerConfig(isIOSEnabled: false))

        XCTAssertEqual(merged.gate, .platformUnavailable)
        XCTAssertTrue(merged.gate.isBlocking)
    }

    /// Platform kapalıyken bakım mesajı gösterilmemeli: kullanıcı beklerse
    /// hiçbir şey değişmez, bayisine başvurması gerekir.
    func test_platformBlockOutranksMaintenance() {
        let merged = makeGlobal(gate: .maintenance(message: "Bakım"))
            .applying(ResellerConfig(isUnderMaintenance: true, isIOSEnabled: false))

        XCTAssertEqual(merged.gate, .platformUnavailable)
    }

    func test_resellerMaintenanceBlocksAccess() {
        let merged = makeGlobal().applying(ResellerConfig(isUnderMaintenance: true))

        XCTAssertTrue(merged.gate.isBlocking)
    }

    /// Global bakım mesajı, bayi de bakımdayken korunmalı — daha bilgilendirici.
    func test_globalMaintenanceMessageIsKept() {
        let merged = makeGlobal(gate: .maintenance(message: "Sunucu bakımı"))
            .applying(ResellerConfig(isUnderMaintenance: true))

        XCTAssertEqual(merged.gate, .maintenance(message: "Sunucu bakımı"))
    }

    func test_openStaysOpen() {
        let merged = makeGlobal().applying(ResellerConfig())

        XCTAssertEqual(merged.gate, .open)
        XCTAssertFalse(merged.gate.isBlocking)
    }

    // MARK: - Kod normalleştirme

    func test_normalizeCode_trimsAndRejectsTooShort() {
        XCTAssertEqual(ResellerConfig.normalizeCode("  4321 "), "4321")
        XCTAssertEqual(ResellerConfig.normalizeCode("TR 1"), "TR1")
        XCTAssertNil(ResellerConfig.normalizeCode(""))
        XCTAssertNil(ResellerConfig.normalizeCode("   "))
        XCTAssertNil(ResellerConfig.normalizeCode("7"), "Tek karakter kazara dokunuştur")
    }

    /// ⚠️ Büyük/küçük harfe dokunulmuyor: eşleştirmeyi panel harf duyarsız
    /// yapıyor, burada ayrıca dönüştürmek yeni bir hata kaynağı olurdu.
    func test_normalizeCode_preservesCase() {
        XCTAssertEqual(ResellerConfig.normalizeCode("tR1"), "tR1")
    }

    // MARK: - Sunucu listesi

    func test_serverDisplayNameFallsBackThroughNameCodeHost() {
        let url = URL(string: "http://sunucu.example.com:8080")
        let named = ResellerServer(code: "TR1", name: "Türkiye", baseURL: url ?? URL(fileURLWithPath: "/"))
        let coded = ResellerServer(code: "TR1", name: "", baseURL: url ?? URL(fileURLWithPath: "/"))
        let bare = ResellerServer(code: "", name: "", baseURL: url ?? URL(fileURLWithPath: "/"))

        XCTAssertEqual(named.displayName, "Türkiye")
        XCTAssertEqual(coded.displayName, "TR1")
        XCTAssertEqual(bare.displayName, "sunucu.example.com")
    }

    /// ⚠️ Kod boş olabilir; kimlik adrese düşmezse kodsuz iki sunucu
    /// listede tek satırmış gibi birleşir.
    func test_serverIdentityFallsBackToURL() {
        let first = ResellerServer(code: "", name: "A", baseURL: URL(fileURLWithPath: "/a"))
        let second = ResellerServer(code: "", name: "B", baseURL: URL(fileURLWithPath: "/b"))

        XCTAssertNotEqual(first.id, second.id)
    }
}
