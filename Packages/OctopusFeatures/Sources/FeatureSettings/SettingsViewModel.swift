import Foundation
import Combine
import OctopusDomain
import OctopusDesignSystem

/// Ayarlar: kaynak bilgisi, veri temizleme, uygulama künyesi.
@MainActor
public final class SettingsViewModel: ObservableObject {

    @Published public private(set) var activePlaylistName: String?
    @Published public private(set) var playlistCount = 0
    @Published public private(set) var lastSyncedText: String?
    @Published public private(set) var isBusy = false
    /// Kullanıcıya gösterilecek son işlem sonucu.
    @Published public private(set) var message: String?

    private let dependencies: SettingsDependencies
    private let now: () -> Date

    public init(dependencies: SettingsDependencies, now: @escaping () -> Date = Date.init) {
        self.dependencies = dependencies
        self.now = now
    }

    public func load() async {
        do {
            let all = try await dependencies.playlists.all()
            playlistCount = all.count

            let active = all.first(where: \.isActive)
            activePlaylistName = active?.name
            lastSyncedText = Self.relativeText(active?.lastSyncedAt, now: now())
        } catch {
            message = AppError.wrap(error).userMessage
        }
    }

    // MARK: - Veri temizleme
    //
    // İki ayrı eylem: kullanıcı geçmişini silmek isteyip izleme
    // ilerlemesini korumak isteyebilir (veya tersi).

    public func clearWatchHistory() async {
        await perform("İzleme geçmişi silindi") {
            try await self.dependencies.history.clearAll()
        }
    }

    public func clearPlaybackProgress() async {
        await perform("Kaldığın yer bilgileri silindi") {
            try await self.dependencies.progress.clearAll()
        }
    }

    /// Aktif kaynağı yeniden senkronize eder.
    public func resyncActivePlaylist() async {
        guard let playlist = try? await dependencies.playlists.activePlaylist() else {
            message = "Önce bir kaynak seçmelisin."
            return
        }

        await perform("Kaynak güncellendi") {
            try await self.dependencies.sync.sync(playlistID: playlist.id)
        }
        await load()
    }

    private func perform(_ successMessage: String, action: () async throws -> Void) async {
        isBusy = true
        message = nil
        defer { isBusy = false }

        do {
            try await action()
            message = successMessage
        } catch {
            message = AppError.wrap(error).userMessage
        }
    }

    // MARK: - Künye

    public var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    static func relativeText(_ date: Date?, now: Date) -> String? {
        guard let date else { return "Henüz güncellenmedi" }

        let elapsed = now.timeIntervalSince(date)
        guard elapsed >= 0 else { return "Az önce" }

        let minutes = Int(elapsed / 60)
        if minutes < 1 { return "Az önce" }
        if minutes < 60 { return "\(minutes) dakika önce" }

        let hours = minutes / 60
        if hours < 24 { return "\(hours) saat önce" }
        return "\(hours / 24) gün önce"
    }
}
