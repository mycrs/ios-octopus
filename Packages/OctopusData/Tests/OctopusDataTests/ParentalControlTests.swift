import XCTest
import OctopusDomain
@testable import OctopusData

/// Ebeveyn kilidi: PIN saklama, doğrulama, oturum davranışı.
final class ParentalControlTests: XCTestCase {

    private var secrets: FakeSecretStore!
    private var control: KeychainParentalControl!
    private var preferences: UserDefaults!
    private var preferencesSuiteName: String!

    override func setUp() {
        super.setUp()
        secrets = FakeSecretStore()
        preferencesSuiteName = "ParentalControlTests.\(UUID().uuidString)"
        preferences = UserDefaults(suiteName: preferencesSuiteName)!
        control = KeychainParentalControl(secrets: secrets, preferences: preferences)
    }

    override func tearDown() {
        preferences.removePersistentDomain(forName: preferencesSuiteName)
        preferences = nil
        preferencesSuiteName = nil
        super.tearDown()
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

    func test_defaultPINUnlocksFreshInstallation() async {
        let didUnlock = await control.unlock(with: "0000")
        XCTAssertTrue(didUnlock)
    }

    func test_defaultPINStopsWorkingAfterPINChange() async throws {
        try await control.changePIN(currentPIN: "0000", newPIN: "4821")
        await control.lock()

        let defaultUnlock = await control.unlock(with: "0000")
        let customUnlock = await control.unlock(with: "4821")
        XCTAssertFalse(defaultUnlock)
        XCTAssertTrue(customUnlock)
    }

    func test_changePINRequiresCurrentPIN() async throws {
        try await control.setPIN("4821")

        do {
            try await control.changePIN(currentPIN: "1111", newPIN: "7392")
            XCTFail("Yanlış mevcut PIN ile değişiklik yapılmamalı")
        } catch {
            XCTAssertEqual(error as? ParentalControlError, .wrongPIN)
        }

        await control.lock()
        let oldUnlock = await control.unlock(with: "4821")
        let rejectedNewUnlock = await control.unlock(with: "7392")
        XCTAssertTrue(oldUnlock)
        XCTAssertFalse(rejectedNewUnlock)
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

    // MARK: - Keychain hatası kilidi açmamalı

    func test_keychainReadFailureDoesNotUnlock() async throws {
        // ⚠️ "Okuyamadım" ile "kayıt yok" aynı şey değil. `try?` ikisini de
        // nil'e düzleştiriyordu ve kilit varsayılan 0000'a açılıyordu:
        // kullanıcı kendi PIN'ini kurmuş sanarken kapı açık kalıyordu.
        try await control.setPIN("4821")
        await control.lock()
        secrets.failReads(for: "parental.pin.hash")

        let withDefaultPIN = await control.unlock(with: "0000")
        XCTAssertFalse(withDefaultPIN, "Okuma hatası varsayılan PIN'i geçerli kılmamalı")

        let isUnlocked = await control.isUnlocked()
        XCTAssertFalse(isUnlocked)
    }

    func test_inconsistentRecordDoesNotFallBackToDefaultPIN() async throws {
        // Özet var, tuz yok: yarım kalmış bir yazımın izi. Varsayılana
        // düşmek yine fail-open olurdu.
        try await control.setPIN("4821")
        await control.lock()
        try secrets.delete(for: "parental.pin.salt")

        let withDefaultPIN = await control.unlock(with: "0000")
        XCTAssertFalse(withDefaultPIN, "Tutarsız kayıt varsayılan PIN'i açmamalı")
    }

    func test_partialSaveIsRolledBack() async {
        // Tuz yazılamazsa yetim özet bırakılmamalı; aksi halde depo
        // kalıcı olarak tutarsız kayıtla kalır ve kimse kilidi açamaz.
        secrets.failWrites(for: "parental.pin.salt")

        do {
            try await control.setPIN("4821")
            XCTFail("Yazım başarısızsa hata fırlatılmalı")
        } catch {
            XCTAssertEqual(error as? ParentalControlError, .storageFailure)
        }

        XCTAssertNil(
            try? secrets.read(for: "parental.pin.hash"),
            "Yarım kayıt geri alınmalı"
        )
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
        XCTAssertTrue(isEnabled, "Varsayılan 0000 koruması etkin kalmalı")
        XCTAssertNil(try secrets.read(for: "parental.pin.hash"))
        XCTAssertNil(try secrets.read(for: "parental.pin.salt"), "Tuz da silinmeli")
    }

    func test_disableWithoutCustomPINRequiresDefaultPIN() async {
        do {
            try await control.disable(with: "1234")
            XCTFail("Yanlış PIN kabul edilmemeli")
        } catch {
            XCTAssertEqual(error as? ParentalControlError, .wrongPIN)
        }
    }

    func test_hiddenCategoryPreferencePersists() async {
        let category = MediaCategory(
            id: "sports",
            playlistID: "p1",
            kind: .live,
            name: "Spor"
        )
        await control.setCategory(category, hidden: true)

        let fresh = KeychainParentalControl(secrets: secrets, preferences: preferences)
        let storedKeys = await fresh.hiddenCategoryKeys()
        XCTAssertTrue(storedKeys.contains(ParentalFilter.categoryKey(category)))

        await fresh.setCategory(category, hidden: false)
        let clearedKeys = await fresh.hiddenCategoryKeys()
        XCTAssertTrue(clearedKeys.isEmpty)
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

    func test_manuallyHiddenCategoryStaysHiddenWhenAdultLockIsOpen() {
        let category = makeCategory("Spor")
        let filter = ParentalFilter(
            isEnabled: true,
            isUnlocked: true,
            hiddenCategoryKeys: [ParentalFilter.categoryKey(category)]
        )
        let channel = Channel(
            id: "sport-channel",
            playlistID: "p1",
            name: "Spor Kanalı",
            streamKey: "1",
            categoryID: category.id
        )

        XCTAssertTrue(filter.filter([category]).isEmpty)
        XCTAssertFalse(filter.allows(channel: channel))
    }

    func test_unconfiguredFilterStillHidesProtectedContent() {
        // PIN kurulmamış olması güvenli varsayılanı kapatmamalı.
        let filter = ParentalFilter(isEnabled: false, isUnlocked: false)

        XCTAssertTrue(filter.hidesAdultContent)
        XCTAssertFalse(filter.allows(channel: makeChannel(isAdult: true)))
    }

    func test_freshKeychainControlStartsProtected() async {
        let freshControl = KeychainParentalControl(secrets: FakeSecretStore())
        let filter = await ParentalFilter.current(freshControl)

        XCTAssertTrue(filter.hidesAdultContent)
        XCTAssertFalse(filter.allows(movie: makeMovie(isAdult: true)))
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
