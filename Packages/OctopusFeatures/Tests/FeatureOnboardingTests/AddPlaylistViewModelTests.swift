import XCTest
import OctopusDomain
@testable import FeatureOnboarding

/// Kaynak ekleme akışı: form doğrulaması, sunucu doğrulaması, kayıt sırası.
@MainActor
final class AddPlaylistViewModelTests: XCTestCase {

    private var playlists: SpyPlaylistRepository!
    private var validator: StubValidator!
    private var activation: StubActivation!
    private var sync: SpySync!

    override func setUp() async throws {
        playlists = SpyPlaylistRepository()
        validator = StubValidator()
        activation = StubActivation()
        sync = SpySync()
    }

    private func makeViewModel() -> AddPlaylistViewModel {
        AddPlaylistViewModel(
            dependencies: OnboardingDependencies(
                playlists: playlists,
                validator: validator,
                activation: activation,
                sync: sync
            ),
            makeID: { "p1" },
            now: { Date(timeIntervalSince1970: 0) },
            completionDelayNanoseconds: 0
        )
    }

    // MARK: - Gönderilebilirlik

    func test_canSubmit_requiresMandatoryFieldsPerSourceKind() {
        let viewModel = makeViewModel()

        viewModel.sourceKind = .xtream
        XCTAssertFalse(viewModel.canSubmit)
        viewModel.host = "panel.example.com"
        viewModel.username = "u"
        XCTAssertFalse(viewModel.canSubmit, "Parola olmadan gönderilememeli")
        viewModel.password = "p"
        XCTAssertTrue(viewModel.canSubmit)

        viewModel.sourceKind = .m3u
        XCTAssertFalse(viewModel.canSubmit, "M3U için bağlantı gerekli")
        viewModel.m3uURL = "http://example.com/l.m3u"
        XCTAssertTrue(viewModel.canSubmit)
    }

    func test_resellerCode_resolvesAndTriesDNSInOrder() async {
        let first = ResellerServer(
            code: "TR1", name: "Birinci",
            baseURL: URL(string: "https://first.example.com")!
        )
        let second = ResellerServer(
            code: "TR2", name: "İkinci",
            baseURL: URL(string: "https://second.example.com")!
        )
        var appliedCodes: [String] = []
        let viewModel = AddPlaylistViewModel(
            dependencies: OnboardingDependencies(
                playlists: playlists,
                validator: validator,
                activation: activation,
                sync: sync,
                applyResellerCode: { code in
                    appliedCodes.append(code)
                    return true
                },
                resellerServers: { [first, second] }
            ),
            completionDelayNanoseconds: 0
        )

        validator.queuedResults = [
            .failure(AppError.unauthorized),
            .success(validator.successAccount)
        ]
        viewModel.host = "8811"
        viewModel.username = "u"
        viewModel.password = "p"

        XCTAssertTrue(viewModel.canSubmit)
        await viewModel.submit()

        XCTAssertEqual(appliedCodes, ["8811"])
        XCTAssertEqual(validator.receivedHosts, ["first.example.com", "second.example.com"])
        XCTAssertEqual(playlists.addedPlaylists.count, 1)
        XCTAssertEqual(viewModel.host, "8811", "Çözülen DNS form alanına sızmamalı")
        XCTAssertEqual(viewModel.step, .done)
    }

    func test_longDNSConnectsDirectlyWithoutResellerLookup() async {
        var appliedCodes: [String] = []
        let viewModel = AddPlaylistViewModel(
            dependencies: OnboardingDependencies(
                playlists: playlists,
                validator: validator,
                activation: activation,
                sync: sync,
                applyResellerCode: { code in
                    appliedCodes.append(code)
                    return false
                }
            ),
            completionDelayNanoseconds: 0
        )
        viewModel.host = "http://xyz.example.com:8080//"
        viewModel.username = "u"
        viewModel.password = "p"

        await viewModel.submit()

        XCTAssertTrue(appliedCodes.isEmpty)
        XCTAssertEqual(validator.receivedHosts, ["xyz.example.com"])
        XCTAssertEqual(playlists.addedPlaylists.count, 1)
        XCTAssertEqual(viewModel.step, .done)
    }

    func test_onlyFourDigitsAreRecognizedAsResellerCode() {
        XCTAssertEqual(AddPlaylistViewModel.resellerCode(from: "8811"), "8811")
        XCTAssertEqual(AddPlaylistViewModel.resellerCode(from: " 3622 "), "3622")
        XCTAssertEqual(AddPlaylistViewModel.resellerCode(from: "88 11"), "8811")
        XCTAssertNil(AddPlaylistViewModel.resellerCode(from: "881"))
        XCTAssertNil(AddPlaylistViewModel.resellerCode(from: "88111"))
        XCTAssertNil(AddPlaylistViewModel.resellerCode(from: "88A1"))
        XCTAssertNil(AddPlaylistViewModel.resellerCode(from: "http://xyz.example.com"))
    }

    // MARK: - Form doğrulaması ağa çıkmadan

    func test_invalidHost_showsErrorWithoutTouchingNetwork() async {
        let viewModel = makeViewModel()
        viewModel.sourceKind = .xtream
        viewModel.host = "gecersiz"
        viewModel.username = "u"
        viewModel.password = "p"

        await viewModel.submit()

        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertEqual(validator.callCount, 0, "Form hatalıyken sunucuya gidilmemeli")
        XCTAssertEqual(playlists.addedPlaylists.count, 0)
        XCTAssertEqual(viewModel.step, .form)
    }

    // MARK: - Kaydetmeden önce doğrulama

    func test_validationFailure_doesNotSavePlaylist() async {
        // ⚠️ EN KRİTİK DAVRANIŞ: hatalı bilgiyle kaynak kaydedilmemeli,
        // yoksa kullanıcı onu silmek zorunda kalır.
        validator.result = .failure(AppError.unauthorized)

        let viewModel = makeViewModel()
        viewModel.sourceKind = .xtream
        viewModel.host = "panel.example.com"
        viewModel.username = "u"
        viewModel.password = "yanlis"

        await viewModel.submit()

        XCTAssertEqual(validator.callCount, 1)
        XCTAssertTrue(playlists.addedPlaylists.isEmpty, "Doğrulama başarısızken kayıt olmamalı")
        XCTAssertEqual(viewModel.step, .form, "Kullanıcı forma dönüp düzeltebilmeli")
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func test_validationReceivesPasswordButPlaylistDoesNot() async {
        let viewModel = makeViewModel()
        viewModel.sourceKind = .xtream
        viewModel.host = "panel.example.com"
        viewModel.username = "kullanici"
        viewModel.password = "gizli123"

        await viewModel.submit()

        // Parola doğrulamaya gitmeli...
        XCTAssertEqual(validator.receivedPassword, "gizli123")
        // ...ama entity'de bulunmamalı.
        let saved = try? XCTUnwrap(playlists.addedPlaylists.first)
        XCTAssertFalse(String(describing: saved).contains("gizli123"))
        // Depoya ayrı parametre olarak verilmeli (Keychain'e yazılmak üzere).
        XCTAssertEqual(playlists.addedPasswords.first, "gizli123")
    }

    // MARK: - Başarılı akış

    func test_successfulFlow_savesActivatesAndSyncs() async {
        let viewModel = makeViewModel()
        viewModel.sourceKind = .m3u
        viewModel.m3uURL = "http://liste.example.com/p.m3u"

        await viewModel.submit()

        XCTAssertEqual(playlists.addedPlaylists.count, 1)
        XCTAssertEqual(playlists.activatedIDs, ["p1"], "Yeni kaynak etkinleştirilmeli")
        XCTAssertEqual(sync.syncedIDs, ["p1"], "İlk senkronizasyon başlatılmalı")
        XCTAssertEqual(viewModel.step, .done)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(
            viewModel.syncCounts,
            SyncContentCounts(channels: 24, movies: 12, series: 3)
        )
    }

    func test_syncFailure_stillCompletesButWarns() async {
        // Kaynak kaydedildi ama içerik çekilemedi. Kullanıcı ana ekrana
        // geçebilmeli; yenileme sonra tekrar denenir.
        sync.error = AppError.network(reason: "kopuk")

        let viewModel = makeViewModel()
        viewModel.sourceKind = .m3u
        viewModel.m3uURL = "http://liste.example.com/p.m3u"

        await viewModel.submit()

        XCTAssertEqual(playlists.addedPlaylists.count, 1, "Kaynak kaydedilmiş olmalı")
        XCTAssertEqual(viewModel.step, .done)
        XCTAssertNotNil(viewModel.errorMessage, "Kullanıcı sorunu bilmeli")
    }

    // MARK: - Aktivasyon kodu ile giriş

    func test_activationCode_resolvesCredentialsFromPanel() async {
        // Kullanıcı sunucu adresi veya parola girmiyor; panel çözüyor.
        activation.result = .success(
            ActivationResult(
                kind: .xtream(
                    host: URL(string: "http://panel.example.com")!,
                    username: "cozulmus_kullanici"
                ),
                password: "cozulmus_parola",
                displayName: "Bayi Listesi",
                customerName: "Ali Veli"
            )
        )

        let viewModel = makeViewModel()
        viewModel.sourceKind = .activationCode
        viewModel.activationCode = "abc-123"

        await viewModel.submit()

        XCTAssertEqual(activation.receivedCodes, ["abc-123"])
        XCTAssertEqual(playlists.addedPlaylists.first?.name, "Bayi Listesi")
        XCTAssertEqual(playlists.addedPasswords.first, "cozulmus_parola")
        XCTAssertEqual(viewModel.customerName, "Ali Veli")
        XCTAssertEqual(viewModel.step, .done)
    }

    func test_activationCode_isStillValidatedAgainstServer() async {
        // Panel bilgileri doğru olsa bile yayın sunucusuna gerçekten
        // bağlanılabildiği kanıtlanmalı.
        activation.result = .success(
            ActivationResult(
                kind: .m3u(url: URL(string: "http://liste.example.com/p.m3u")!),
                password: nil,
                displayName: "Liste"
            )
        )

        let viewModel = makeViewModel()
        viewModel.sourceKind = .activationCode
        viewModel.activationCode = "ABC-123"

        await viewModel.submit()

        XCTAssertEqual(validator.callCount, 1, "Kod ile girişte de sunucu doğrulanmalı")
    }

    func test_activationFailure_showsActionableMessage() async {
        // Süresi dolmuş kod için "tekrar dene" demek yanlış olur.
        activation.result = .failure(ActivationError.expired)

        let viewModel = makeViewModel()
        viewModel.sourceKind = .activationCode
        viewModel.activationCode = "ABC-123"

        await viewModel.submit()

        XCTAssertEqual(viewModel.step, .form)
        XCTAssertTrue(playlists.addedPlaylists.isEmpty)
        let message = viewModel.errorMessage ?? ""
        XCTAssertTrue(message.contains("süresi dolmuş"), "Beklenen mesaj gelmedi: \(message)")
        XCTAssertTrue(
            message.contains("hizmet sağlayıcın"),
            "Kullanıcı ne yapacağını bilmeli: \(message)"
        )
    }

    func test_activationCode_requiresMinimumLength() {
        let viewModel = makeViewModel()
        viewModel.sourceKind = .activationCode

        viewModel.activationCode = "AB"
        XCTAssertFalse(viewModel.canSubmit)

        viewModel.activationCode = "ABC-123"
        XCTAssertTrue(viewModel.canSubmit)
    }

    // MARK: - Ad üretimi

    func test_emptyName_fallsBackToHost() async {
        let viewModel = makeViewModel()
        viewModel.sourceKind = .m3u
        viewModel.m3uURL = "http://liste.example.com/p.m3u"
        viewModel.name = ""

        await viewModel.submit()

        XCTAssertEqual(playlists.addedPlaylists.first?.name, "liste.example.com")
    }
}

// MARK: - Sahte bağımlılıklar

@MainActor
private final class SpyPlaylistRepository: PlaylistRepository {

    nonisolated(unsafe) var addedPlaylists: [Playlist] = []
    nonisolated(unsafe) var addedPasswords: [String?] = []
    nonisolated(unsafe) var activatedIDs: [Playlist.ID] = []

    nonisolated func all() async throws -> [Playlist] { addedPlaylists }
    nonisolated func playlist(id: Playlist.ID) async throws -> Playlist? {
        addedPlaylists.first { $0.id == id }
    }
    nonisolated func activePlaylist() async throws -> Playlist? { nil }

    nonisolated func add(_ playlist: Playlist, password: String?) async throws {
        addedPlaylists.append(playlist)
        addedPasswords.append(password)
    }

    nonisolated func update(_ playlist: Playlist) async throws {}

    nonisolated func setActive(id: Playlist.ID) async throws {
        activatedIDs.append(id)
    }

    nonisolated func delete(id: Playlist.ID) async throws {}
}

private final class StubValidator: PlaylistValidating, @unchecked Sendable {

    let successAccount =
        ProviderAccount(
            username: "u", expiresAt: nil, isTrial: false,
            maxConnections: 1, activeConnections: 0
        )
    lazy var result: Result<ProviderAccount, Error> = .success(successAccount)
    var queuedResults: [Result<ProviderAccount, Error>] = []
    private(set) var callCount = 0
    private(set) var receivedPassword: String?
    private(set) var receivedHosts: [String] = []

    func validate(_ playlist: Playlist, password: String?) async throws -> ProviderAccount {
        callCount += 1
        receivedPassword = password
        if case .xtream(let host, _) = playlist.kind {
            receivedHosts.append(host.host ?? host.absoluteString)
        }
        if !queuedResults.isEmpty {
            return try queuedResults.removeFirst().get()
        }
        return try result.get()
    }
}

private final class StubActivation: ActivationRedeeming, @unchecked Sendable {

    var result: Result<ActivationResult, Error> = .failure(ActivationError.notFound)
    private(set) var receivedCodes: [String] = []

    func redeem(code: String) async throws -> ActivationResult {
        receivedCodes.append(code)
        return try result.get()
    }
}

private final class SpySync: ContentSyncing, @unchecked Sendable {

    var error: Error?
    private(set) var syncedIDs: [Playlist.ID] = []

    func sync(playlistID: Playlist.ID) async throws {
        syncedIDs.append(playlistID)
        try await Task.sleep(nanoseconds: 20_000_000)
        if let error { throw error }
    }

    func syncEPG(playlistID: Playlist.ID) async throws {}

    func observeProgress(playlistID: Playlist.ID) -> AsyncStream<SyncStage> {
        AsyncStream { continuation in
            let counts = SyncContentCounts(channels: 24, movies: 12, series: 3)
            continuation.yield(.fetchingChannels(done: 24, total: 24))
            continuation.yield(.fetchingMovies(done: 12, total: 12))
            continuation.yield(.fetchingSeries(done: 3, total: 3))
            continuation.yield(.finished(at: Date(), counts: counts))
            continuation.finish()
        }
    }
}
