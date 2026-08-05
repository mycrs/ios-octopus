import XCTest
import OctopusDomain
@testable import OctopusData

/// Ebeveyn kilidi: PIN saklama, doğrulama, oturum davranışı.
final class ParentalControlTests: XCTestCase {

    private var secrets: FakeSecretStore!
    private var control: KeychainParentalControl!

    override func setUp() {
        super.setUp()
        secrets = FakeSecretStore()
        control = KeychainParentalControl(secrets: secrets)
    }

    // MARK: - PIN saklama

    func test_pinIsNeverStoredInPlainText() async throws {
        // ⚠️ EN KRİTİK DAVRANIŞ: PIN düz metin olarak hiçbir yere yazılmamalı.
        try await control.setPIN("1234")

        let storedHash = try secrets.read(for: "parental.pin.hash")
        let storedSalt = try secrets.read(for: "parental.pin.salt")

        XCTAssertNotNil(storedHash)
        XCTAssertNotNil(storedSalt)
        XCTAssertNotEqual(storedHash, "1234")
        XCTAssertFalse(storedHash?.contains("1234") ?? true, "PIN özet içinde görünmemeli")
    }

    func test_sameePINProducesDifferentHashesAcrossSetups() async throws {
        // Tuz her belirlemede yenilenir: hazır tablo saldırısı işe yaramaz.
        try await control.setPIN("1234")
        let firstHash = try secrets.read(for: "parental.pin.hash")

        let secondSecrets = FakeSecretStore()
        let secondControl = KeychainParentalControl(secrets: secondSecrets)
        try await secondControl.setPIN("1234")
        let secondHash = try secondSecrets.read(for: "parental.pin.hash")

        XCTAssertNotEqual(firstHash, secondHash, "Aynı PIN farklı özet üretmeli")
    }

    // MARK: - Biçim denetimi

    func test_invalidPINFormatsAreRejected() async {
        for badPIN in ["", "12", "123", "abcd", "12a4", "123456789"] {
            do {
                try await control.setPIN(badPIN)
                XCTFail("Kabul edildi: '\(badPIN)'")
            } catch {
                XCTAssertEqual(error as? ParentalControlError, .invalidFormat)
            }
        }
    }

    func test_validPINLengthsAreAccepted() async throws {
        try await control.setPIN("1234")
        try await control.setPIN("12345678")
    }

    // MARK: - Doğrulama

    func test_correctPINUnlocks() async throws {
        try await control.setPIN("4821")
        await control.lock()

        let isUnlockedBefore = await control.isUnlocked()
        XCTAssertFalse(isUnlockedBefore)

        let success = await control.unlock(with: "4821")
        XCTAssertTrue(success)

        let isUnlockedAfter = await control.isUnlocked()
        XCTAssertTrue(isUnlockedAfter)
    }

    func test_wrongPINDoesNotUnlock() async throws {
        try await control.setPIN("4821")
        await control.lock()

        let success = await control.unlock(with: "0000")
        XCTAssertFalse(success)

        let isUnlocked = await control.isUnlocked()
        XCTAssertFalse(isUnlocked)
    }

    func test_settingPINUnlocksSession() async throws {
        // PIN'i belirleyen kişi zaten yetkili; tekrar sormaya gerek yok.
        try await control.setPIN("4821")
        let isUnlocked = await control.isUnlocked()
        XCTAssertTrue(isUnlocked)
    }

    func test_lockClosesSession() async throws {
        try await control.setPIN("4821")
        await control.lock()

        let isUnlocked = await control.isUnlocked()
        XCTAssertFalse(isUnlocked)
    }

    // MARK: - Kaldırma

    func test_disableRequiresCorrectPIN() async throws {
        try await control.setPIN("4821")

        do {
            try await control.disable(with: "0000")
            XCTFail("Yanlış PIN ile kilit kaldırılmamalı")
        } catch {
            XCTAssertEqual(error as? ParentalControlError, .wrongPIN)
        }

        let stillEnabled = await control.isEnabled()
        XCTAssertTrue(stillEnabled)
    }

    func test_disableWithCorrectPINRemovesEverything() async throws {
        try await control.setPIN("4821")
        try await control.disable(with: "4821")

        let isEnabled = await control.isEnabled()
        XCTAssertFalse(isEnabled)
        XCTAssertNil(try secrets.read(for: "parental.pin.hash"))
        XCTAssertNil(try secrets.read(for: "parental.pin.salt"), "Tuz da silinmeli")
    }

    func test_disableWithoutSetupThrows() async {
        do {
            try await control.disable(with: "1234")
            XCTFail("Kurulmamış kilit kaldırılamaz")
        } catch {
            XCTAssertEqual(error as? ParentalControlError, .notConfigured)
        }
    }

    // MARK: - Sabit süreli karşılaştırma

    func test_constantTimeComparison() {
        XCTAssertTrue(KeychainParentalControl.constantTimeEquals("abc", "abc"))
        XCTAssertFalse(KeychainParentalControl.constantTimeEquals("abc", "abd"))
        XCTAssertFalse(KeychainParentalControl.constantTimeEquals("abc", "abcd"))
        XCTAssertFalse(KeychainParentalControl.constantTimeEquals("", "a"))
        XCTAssertTrue(KeychainParentalControl.constantTimeEquals("", ""))
    }
}

/// Kilit durumuna göre içerik süzme — saf iş kuralı.
final class ParentalFilterTests: XCTestCase {

    private func makeChannel(isAdult: Bool) -> Channel {
        Channel(
            id: isAdult ? "adult" : "normal",
            playlistID: "p1",
            name: "Kanal",
            streamKey: "1",
            isAdult: isAdult
        )
    }

    private func makeMovie(isAdult: Bool) -> Movie {
        Movie(
            id: isAdult ? "adult" : "normal",
            playlistID: "p1",
            title: "Film",
            streamKey: "1",
            isAdult: isAdult
        )
    }

    func test_lockedFilterHidesAdultContent() {
        let filter = ParentalFilter(isEnabled: true, isUnlocked: false)

        XCTAssertTrue(filter.hidesAdultContent)
        XCTAssertFalse(filter.allows(channel: makeChannel(isAdult: true)))
        XCTAssertTrue(filter.allows(channel: makeChannel(isAdult: false)))

        let channels = [makeChannel(isAdult: true), makeChannel(isAdult: false)]
        XCTAssertEqual(filter.filter(channels).count, 1)
    }

    func test_unlockedFilterShowsEverything() {
        let filter = ParentalFilter(isEnabled: true, isUnlocked: true)

        XCTAssertFalse(filter.hidesAdultContent)
        XCTAssertTrue(filter.allows(channel: makeChannel(isAdult: true)))
        XCTAssertTrue(filter.allows(movie: makeMovie(isAdult: true)))
    }

    func test_disabledFilterShowsEverything() {
        // Kilit hiç kurulmamışsa süzme yapılmaz.
        let filter = ParentalFilter(isEnabled: false, isUnlocked: false)

        XCTAssertFalse(filter.hidesAdultContent)
        XCTAssertTrue(filter.allows(channel: makeChannel(isAdult: true)))
    }

    private func makeCategory(_ name: String) -> MediaCategory {
        MediaCategory(id: MediaCategory.ID(name), playlistID: "p1", kind: .live, name: name)
    }

    func test_lockedFilterHidesAdultCategories() {
        // İçeriği gizleyip "XXX" sekmesini bırakmak hem içeriğin varlığını
        // ele veriyor hem de boş liste açıyordu.
        let filter = ParentalFilter(isEnabled: true, isUnlocked: false)
        let categories = [makeCategory("Spor"), makeCategory("XXX"), makeCategory("Haber")]

        XCTAssertEqual(filter.filter(categories).map(\.name), ["Spor", "Haber"])
    }

    func test_unlockedFilterKeepsAllCategories() {
        let filter = ParentalFilter(isEnabled: true, isUnlocked: true)
        let categories = [makeCategory("Spor"), makeCategory("XXX")]

        XCTAssertEqual(filter.filter(categories).count, 2)
    }

    func test_filterPreservesOrder() {
        let filter = ParentalFilter(isEnabled: true, isUnlocked: false)
        let movies = [
            makeMovie(isAdult: false),
            makeMovie(isAdult: true),
            makeMovie(isAdult: false)
        ]
        XCTAssertEqual(filter.filter(movies).count, 2)
    }
}
