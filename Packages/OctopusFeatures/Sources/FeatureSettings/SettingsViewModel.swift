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
    @Published public private(set) var isParentalEnabled = false
    @Published public private(set) var isProtectedContentUnlocked = false
    @Published public private(set) var contentCategories: [MediaCategory] = []
    @Published public private(set) var hiddenCategoryKeys: Set<String> = []

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
            isParentalEnabled = await dependencies.parental.isEnabled()
            isProtectedContentUnlocked = await dependencies.parental.isUnlocked()
            hiddenCategoryKeys = await dependencies.parental.hiddenCategoryKeys()
            if let active {
                contentCategories = try await loadCategories(playlistID: active.id)
            } else {
                contentCategories = []
            }
        } catch {
            message = AppError.wrap(error).userMessage
        }
    }

    // MARK: - Ebeveyn kilidi

    public func setParentalPIN(_ pin: String) async {
        do {
            try await dependencies.parental.setPIN(pin)
            isParentalEnabled = true
            isProtectedContentUnlocked = await dependencies.parental.isUnlocked()
            message = "PIN kaydedildi. İçerik koruması bu oturum için açıldı."
            dependencies.notifyProtectionChanged()
            Haptics.success()
        } catch {
            message = Self.parentalMessage(for: error)
            // Yanlış PIN parmakta da karşılık bulsun; ekrana bakmadan anlaşılır.
            Haptics.warning()
        }
    }

    public func changeParentalPIN(
        currentPIN: String,
        newPIN: String,
        confirmation: String
    ) async {
        guard newPIN == confirmation else {
            message = "Yeni PIN'ler eşleşmiyor."
            Haptics.warning()
            return
        }

        do {
            try await dependencies.parental.changePIN(
                currentPIN: currentPIN,
                newPIN: newPIN
            )
            isParentalEnabled = true
            isProtectedContentUnlocked = await dependencies.parental.isUnlocked()
            message = "PIN değiştirildi."
            dependencies.notifyProtectionChanged()
            Haptics.success()
        } catch {
            message = Self.parentalMessage(for: error)
            Haptics.warning()
        }
    }

    @discardableResult
    public func unlockProtectedContent(with pin: String) async -> Bool {
        if await dependencies.parental.unlock(with: pin) {
            isProtectedContentUnlocked = true
            message = "İçerik kilidi bu oturum için açıldı."
            dependencies.notifyProtectionChanged()
            Haptics.success()
            return true
        } else {
            message = "PIN hatalı."
            Haptics.warning()
            return false
        }
    }

    public func lockProtectedContent() async {
        await dependencies.parental.lock()
        isProtectedContentUnlocked = false
        message = "İçerik kilidi etkin."
        dependencies.notifyProtectionChanged()
        Haptics.success()
    }

    static func parentalMessage(for error: Error) -> String {
        switch error as? ParentalControlError {
        case .invalidFormat:
            return "PIN 4-8 haneli olmalı ve yalnızca rakam içermeli."
        case .wrongPIN:
            return "PIN hatalı."
        case .notConfigured:
            return "Henüz PIN belirlenmemiş."
        case .storageFailure, .none:
            return "İşlem tamamlanamadı."
        }
    }

    // MARK: - Kategori görünürlüğü

    public func isCategoryVisible(_ category: MediaCategory) -> Bool {
        !hiddenCategoryKeys.contains(ParentalFilter.categoryKey(category))
    }

    public func setCategory(_ category: MediaCategory, visible: Bool) async {
        await dependencies.parental.setCategory(category, hidden: !visible)
        hiddenCategoryKeys = await dependencies.parental.hiddenCategoryKeys()
        message = visible ? "Kategori gösteriliyor." : "Kategori gizlendi."
        dependencies.notifyProtectionChanged()
        Haptics.selection()
    }

    public func setAllCategories(kind: MediaCategory.Kind, visible: Bool) async {
        for category in contentCategories where category.kind == kind {
            await dependencies.parental.setCategory(category, hidden: !visible)
        }
        hiddenCategoryKeys = await dependencies.parental.hiddenCategoryKeys()
        dependencies.notifyProtectionChanged()
        Haptics.success()
    }

    private func loadCategories(playlistID: Playlist.ID) async throws -> [MediaCategory] {
        var result: [MediaCategory] = []
        if let channels = dependencies.channels {
            result += try await channels.categories(playlistID: playlistID)
        }
        if let vod = dependencies.vod {
            result += try await vod.categories(playlistID: playlistID)
        }
        if let series = dependencies.series {
            result += try await series.categories(playlistID: playlistID)
        }
        return result.sorted {
            if $0.kind != $1.kind { return $0.kind.rawValue < $1.kind.rawValue }
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
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

    /// Afiş ve logo önbelleğini boşaltır.
    ///
    /// Büyük kataloglarda birkaç yüz MB'a çıkabiliyor; kullanıcı yer
    /// açmak isteyebilir. Veri kaybı yok, görseller yeniden indirilir.
    public func clearImageCache() async {
        await perform("Görsel önbelleği temizlendi") {
            ImageLoading.clearCache()
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
