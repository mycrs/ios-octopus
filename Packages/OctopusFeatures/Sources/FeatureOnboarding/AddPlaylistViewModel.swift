import Foundation
import Combine
import OctopusDomain
import OctopusDesignSystem   // AppError.userMessage sunum uzantısı

/// Kaynak ekleme akışı: form → doğrulama → kayıt → ilk senkronizasyon.
///
/// ⚠️ Sıra bilinçli: **önce doğrula, sonra kaydet.** Tersi olsaydı hatalı
/// bilgiyle kaynak kaydedilir, kullanıcı onu silmek zorunda kalırdı.
@MainActor
public final class AddPlaylistViewModel: ObservableObject {

    public enum SourceKind: String, CaseIterable, Identifiable, Sendable {
        case xtream
        case m3u

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .xtream: return "Xtream Codes"
            case .m3u: return "M3U Bağlantısı"
            }
        }
    }

    /// Akışın hangi adımda olduğu.
    public enum Step: Equatable {
        case form
        case validating
        case syncing(SyncStage)
        case done

        public var isBusy: Bool {
            switch self {
            case .form, .done: return false
            case .validating, .syncing: return true
            }
        }
    }

    // MARK: - Form alanları

    @Published public var sourceKind: SourceKind = .xtream
    @Published public var name = ""
    @Published public var host = ""
    @Published public var username = ""
    @Published public var password = ""
    @Published public var m3uURL = ""
    @Published public var epgURL = ""

    // MARK: - Durum

    @Published public private(set) var step: Step = .form
    @Published public private(set) var errorMessage: String?
    /// Doğrulama başarılıysa hesap bilgisi (abonelik bitişi vb.).
    @Published public private(set) var account: ProviderAccount?

    /// Kaydet butonunun etkin olup olmadığı — ağ isteği yapmadan, anında.
    public var canSubmit: Bool {
        guard !step.isBusy else { return false }
        switch sourceKind {
        case .xtream:
            return !host.trimmed.isEmpty && !username.trimmed.isEmpty && !password.isEmpty
        case .m3u:
            return !m3uURL.trimmed.isEmpty
        }
    }

    private let dependencies: OnboardingDependencies
    private let makeID: () -> Playlist.ID
    private let now: () -> Date
    private var progressTask: Task<Void, Never>?

    public init(
        dependencies: OnboardingDependencies,
        makeID: @escaping () -> Playlist.ID = { Playlist.ID(UUID().uuidString) },
        now: @escaping () -> Date = Date.init
    ) {
        self.dependencies = dependencies
        self.makeID = makeID
        self.now = now
    }

    deinit {
        progressTask?.cancel()
    }

    // MARK: - Akış

    public func submit() async {
        errorMessage = nil

        let draft = makeDraft()
        let playlist: Playlist
        let password: String?

        // 1. Form doğrulaması — ağa çıkmadan.
        do {
            (playlist, password) = try draft.build(id: makeID(), createdAt: now())
        } catch let error as PlaylistDraftError {
            errorMessage = error.userMessage
            return
        } catch {
            errorMessage = AppError.wrap(error).userMessage
            return
        }

        // 2. Sunucu doğrulaması — kaydetmeden önce.
        step = .validating
        do {
            account = try await dependencies.validator.validate(playlist, password: password)
        } catch {
            step = .form
            errorMessage = AppError.wrap(error).userMessage
            return
        }

        // 3. Kayıt ve etkinleştirme.
        do {
            try await dependencies.playlists.add(playlist, password: password)
            try await dependencies.playlists.setActive(id: playlist.id)
        } catch {
            step = .form
            errorMessage = AppError.wrap(error).userMessage
            return
        }

        // 4. İlk senkronizasyon.
        await runInitialSync(playlistID: playlist.id)
    }

    private func runInitialSync(playlistID: Playlist.ID) async {
        step = .syncing(.idle)
        observeProgress(playlistID: playlistID)

        do {
            try await dependencies.sync.sync(playlistID: playlistID)
            progressTask?.cancel()
            step = .done
        } catch {
            progressTask?.cancel()
            // Kaynak kaydedildi ama içerik çekilemedi. Kullanıcı ana ekrana
            // geçebilmeli; yenileme daha sonra tekrar denenir.
            step = .done
            errorMessage = AppError.wrap(error).userMessage
        }
    }

    private func observeProgress(playlistID: Playlist.ID) {
        progressTask?.cancel()
        progressTask = Task { [weak self, dependencies] in
            for await stage in dependencies.sync.observeProgress(playlistID: playlistID) {
                guard let self, !Task.isCancelled else { return }
                // Bitiş ve hata ayrı ele alınır; burada yalnızca ara aşamalar.
                if case .syncing = self.step {
                    self.step = .syncing(stage)
                }
            }
        }
    }

    public func cancelSync() {
        progressTask?.cancel()
        step = .form
    }

    private func makeDraft() -> PlaylistDraft {
        switch sourceKind {
        case .xtream:
            return PlaylistDraft(
                name: name,
                kind: .xtream(host: host, username: username, password: password)
            )
        case .m3u:
            return PlaylistDraft(
                name: name,
                kind: .m3u(url: m3uURL, epgURL: epgURL)
            )
        }
    }
}

// MARK: - Hata metinleri

extension PlaylistDraftError {
    /// Form hataları kullanıcının düzeltebileceği eksikliklerdir;
    /// teknik hata gibi sunulmamalı.
    var userMessage: String {
        switch self {
        case .emptyUsername: return "Kullanıcı adını gir."
        case .emptyPassword: return "Parolayı gir."
        case .invalidHost: return "Sunucu adresi geçersiz. Örnek: panel.example.com:8080"
        case .invalidURL: return "Bağlantı geçersiz. Örnek: http://example.com/liste.m3u"
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
