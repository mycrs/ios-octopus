import XCTest
@testable import OctopusDomain

/// Bayi marka rengi kuralları.
///
/// Android sürümünden taşınan en incelikli kural burada: panel gerçekten
/// renk seçmemişse eski varsayılanı (doygun kırmızı) gönderiyor ve bu,
/// uygulamanın mavi kimliğini eziyor.
final class BrandConfigurationTests: XCTestCase {

    private func brand(_ hex: String?) -> BrandConfiguration {
        BrandConfiguration(primaryColorHex: hex, resellerName: nil, logoURL: nil)
    }

    // MARK: - Geçerli renkler

    func test_validColorsAreApplied() {
        XCTAssertEqual(brand("#00B0FF").effectiveColorHex, "#00B0FF")
        XCTAssertEqual(brand("00E676").effectiveColorHex, "#00E676", "Diyez olmadan da kabul edilmeli")
        XCTAssertEqual(brand("#E040FB").effectiveColorHex, "#E040FB")
        XCTAssertEqual(brand("#FF9100").effectiveColorHex, "#FF9100", "Turuncu kırmızı sayılmamalı")
        XCTAssertEqual(brand("#FF3B30").effectiveColorHex, "#FF3B30", "Seçilmiş kırmızı uygulanmalı")
        XCTAssertEqual(brand("#FF0000").effectiveColorHex, "#FF0000", "Saf kırmızı uygulanmalı")
    }

    // MARK: - Panel varsayılanı kırmızı yok sayılır

    func test_onlyLegacyPanelRedIsIgnoredAsDefault() {
        XCTAssertNil(brand("#E50914").effectiveColorHex)
        XCTAssertNil(brand("e50914").effectiveColorHex)
        XCTAssertEqual(brand("#E53935").effectiveColorHex, "#E53935")
        XCTAssertEqual(brand("#D32F2F").effectiveColorHex, "#D32F2F")
        XCTAssertEqual(brand("#B3261E").effectiveColorHex, "#B3261E")
    }

    func test_desaturatedOrDarkRedsAreNotTreatedAsDefault() {
        // Bayi bilinçli olarak soluk veya koyu bir kırmızı seçmiş olabilir.
        XCTAssertNotNil(brand("#8B5A5A").effectiveColorHex, "Soluk kırmızı kullanıcı seçimi olabilir")
        XCTAssertNotNil(brand("#3D1010").effectiveColorHex, "Çok koyu kırmızı kullanıcı seçimi olabilir")
    }

    func test_pinkAndPurpleAreNotRed() {
        XCTAssertNotNil(brand("#E91E63").effectiveColorHex, "Pembe kırmızı sayılmamalı")
        XCTAssertNotNil(brand("#9C27B0").effectiveColorHex, "Mor kırmızı sayılmamalı")
    }

    // MARK: - Geçersiz girdiler

    func test_invalidHexIsIgnored() {
        XCTAssertNil(brand(nil).effectiveColorHex)
        XCTAssertNil(brand("").effectiveColorHex)
        XCTAssertNil(brand("mavi").effectiveColorHex)
        XCTAssertNil(brand("#XYZ123").effectiveColorHex)
        XCTAssertNil(brand("#FFF").effectiveColorHex, "Kısa biçim desteklenmiyor")
        XCTAssertNil(brand("#00B0FF00").effectiveColorHex, "Alfa kanallı biçim desteklenmiyor")
    }

    func test_whitespaceIsTolerated() {
        XCTAssertEqual(brand("  #00B0FF  ").effectiveColorHex, "#00B0FF")
    }

    // MARK: - Duyuru

    func test_emptyAnnouncementIsRejected() {
        XCTAssertNil(Announcement(message: ""))
        XCTAssertNil(Announcement(message: "   \n  "))
        XCTAssertNotNil(Announcement(message: "Bakım yapılacak"))
    }

    func test_announcementIdentityChangesWithMessage() {
        // Aynı duyuru tekrar gösterilmemeli; panel yeni metin yayınlarsa
        // kimlik de değişip yeniden gösterilmeli.
        let first = Announcement(message: "Duyuru A")
        let same = Announcement(message: "Duyuru A")
        let other = Announcement(message: "Duyuru B")

        XCTAssertEqual(first?.id, same?.id)
        XCTAssertNotEqual(first?.id, other?.id)
    }

    func test_announcementTrimsWhitespace() {
        XCTAssertEqual(Announcement(message: "  Merhaba  ")?.message, "Merhaba")
    }

    // MARK: - Servis kapısı

    func test_maintenanceBlocksAccess() {
        XCTAssertFalse(ServiceGate.open.isBlocking)
        XCTAssertTrue(ServiceGate.maintenance(message: nil).isBlocking)
        XCTAssertTrue(ServiceGate.maintenance(message: "Bakımdayız").isBlocking)
    }

    // MARK: - İletişim kanalları

    func test_contactChannelsReportAvailability() {
        XCTAssertFalse(ContactChannels.empty.hasAny)
        XCTAssertTrue(
            ContactChannels(
                whatsAppURL: URL(string: "https://wa.me/123"),
                telegramURL: nil,
                websiteURL: nil
            ).hasAny
        )
    }
}
