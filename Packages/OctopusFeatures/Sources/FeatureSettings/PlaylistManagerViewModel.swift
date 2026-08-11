import Foundation
import Combine
import OctopusDomain
import OctopusDesignSystem

/// Kayıtlı kaynakların yönetimi: listeleme, etkinleştirme, yenileme, silme.
@MainActor
public final class PlaylistManagerViewModel: ObservableObject {

    /// Bir kaynağın ekranda gösterilecek hâli.
    public struct Row: Identifiable, Equatable {
        public let id: Playlist.ID
        public let name: String
        public let detail: String
        public let isActive: Bool
        public let lastSyncedText: String?
    }

    @Published public private(set) var rows: [Row] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var errorMessage: String?
    /// Yenilenmekte olan kaynak — satırda gösterge için.
    @Published public private(set) var syncingID: Playlist.ID?

    private let dependencies: SettingsDependencies
    private let now: () -> Date

    public init(dependencies: SettingsDependencies, now: @escaping () -> Date = Date.init) {
        self.dependencies = dependencies
        self.now = now
    }

    // MARK: - Yükleme

    public func load() async {
        isLoading = rows.isEmpty
        defer { isLoading = false }

        do {
            let playlists = try await dependencies.playlists.all()
            rows = playlists.map(makeRow)
            errorMessage = nil
        } catch {
            errorMessage = AppError.wrap(error).userMessage
        }
    }

    // MARK: - Eylemler

    public func activate(_ id: Playlist.ID) async {
        do {
            try await dependencies.playlists.setActive(id: id)
            await load()
        } catch {
            errorMessage = AppError.wrap(error).userMessage
        }
    }

    public func resync(_ id: Playlist.ID) async {
        syncingID = id
        defer { syncingID = nil }

        do {
            try await dependencies.sync.sync(playlistID: id)
            await load()
            errorMessage = nil
        } catch {
            errorMessage = AppError.wrap(error).userMessage
        }
    }

    /// Kaynağı ve ona ait tüm içeriği siler.
    ///
    /// Favoriler ve izleme ilerlemesi **korunur**: kullanıcı aynı kaynağı
    /// yeniden eklerse verisi yerinde bulunur.
    public func delete(_ id: Playlist.ID) async {
        do {
            try await dependencies.playlists.delete(id: id)
            await load()

            // Silinen kaynak aktifse, kalanlardan biri etkinleştirilir —
            // aksi halde uygulama içeriksiz bir durumda kalırdı.
            if rows.allSatisfy({ !$0.isActive }), let first = rows.first {
                try await dependencies.playlists.setActive(id: first.id)
                await load()
            }
        } catch {
            errorMessage = AppError.wrap(error).userMessage
        }
    }

    // MARK: - Sunum

    private func makeRow(_ playlist: Playlist) -> Row {
        Row(
            id: playlist.id,
            name: playlist.name,
            detail: Self.detailText(for: playlist.kind),
            isActive: playlist.isActive,
            lastSyncedText: lastSyncedText(playlist.lastSyncedAt)
        )
    }

    static func detailText(for kind: Playlist.Kind) -> String {
        switch kind {
        case .xtream(_, let username):
            return username.isEmpty ? "Hesap bağlantısı" : username
        case .m3u:
            return "M3U listesi"
        case .m3uLocalFile(let fileName):
            return fileName
        case .activationCode:
            return "Aktivasyon kodu"
        }
    }

    /// "3 saat önce güncellendi" gibi kısa bir ifade.
    func lastSyncedText(_ date: Date?) -> String? {
        guard let date else { return "Henüz güncellenmedi" }

        let elapsed = now().timeIntervalSince(date)
        guard elapsed >= 0 else { return "Az önce güncellendi" }

        let minutes = Int(elapsed / 60)
        if minutes < 1 { return "Az önce güncellendi" }
        if minutes < 60 { return "\(minutes) dakika önce güncellendi" }

        let hours = minutes / 60
        if hours < 24 { return "\(hours) saat önce güncellendi" }

        let days = hours / 24
        return "\(days) gün önce güncellendi"
    }
}
