import XCTest
import OctopusDomain
@testable import OctopusData

final class PlaylistAccessControlTests: XCTestCase {

    private var secrets: FakeSecretStore!
    private var control: KeychainPlaylistAccessControl!
    private let playlistID: Playlist.ID = "protected-list"

    override func setUp() {
        super.setUp()
        secrets = FakeSecretStore()
        control = KeychainPlaylistAccessControl(secrets: secrets)
    }

    func test_configuredPlaylistStartsLockedAndPINIsNotPlainText() async throws {
        try await control.configure(playlistID, pin: "4821")

        let isProtected = await control.isProtected(playlistID)
        let isUnlocked = await control.isUnlocked(playlistID)
        XCTAssertTrue(isProtected)
        XCTAssertFalse(isUnlocked)
        XCTAssertNotEqual(
            try secrets.read(for: "playlist.lock.protected-list.hash"),
            "4821"
        )
    }

    func test_readFailureKeepsPlaylistProtected() async throws {
        // ⚠️ Okuma hatasında "korumasız" demek kapıyı tamamen açardı:
        // `isUnlocked` true döner, PIN ekranı hiç çizilmezdi.
        try await control.configure(playlistID, pin: "4821")
        secrets.failReads(for: "playlist.lock.protected-list.hash")

        let isProtected = await control.isProtected(playlistID)
        let isUnlocked = await control.isUnlocked(playlistID)

        XCTAssertTrue(isProtected, "Şüphede kalınca korumalı sayılmalı")
        XCTAssertFalse(isUnlocked, "PIN kapısı atlanmamalı")
    }

    func test_onlyCorrectPINUnlocks() async throws {
        try await control.configure(playlistID, pin: "4821")

        let wrongPIN = await control.unlock(playlistID, with: "0000")
        let correctPIN = await control.unlock(playlistID, with: "4821")
        let isUnlocked = await control.isUnlocked(playlistID)
        XCTAssertFalse(wrongPIN)
        XCTAssertTrue(correctPIN)
        XCTAssertTrue(isUnlocked)
    }

    func test_backgroundLockRequiresPINAgain() async throws {
        try await control.configure(playlistID, pin: "4821")
        _ = await control.unlock(playlistID, with: "4821")

        await control.lockAll()

        let isUnlocked = await control.isUnlocked(playlistID)
        XCTAssertFalse(isUnlocked)
    }

    func test_unprotectedPlaylistDoesNotPrompt() async {
        let isProtected = await control.isProtected("open-list")
        let isUnlocked = await control.isUnlocked("open-list")
        XCTAssertFalse(isProtected)
        XCTAssertTrue(isUnlocked)
    }

    func test_removingPlaylistDeletesLock() async throws {
        try await control.configure(playlistID, pin: "4821")
        await control.remove(playlistID)

        let isProtected = await control.isProtected(playlistID)
        let isUnlocked = await control.isUnlocked(playlistID)
        XCTAssertFalse(isProtected)
        XCTAssertTrue(isUnlocked)
    }

    func test_PINMustBeExactlyFourDigits() async {
        for pin in ["", "123", "12345", "12a4"] {
            do {
                try await control.configure(playlistID, pin: pin)
                XCTFail("Geçersiz PIN kabul edildi: \(pin)")
            } catch {
                XCTAssertEqual(error as? PlaylistAccessError, .invalidPIN)
            }
        }
    }
}
