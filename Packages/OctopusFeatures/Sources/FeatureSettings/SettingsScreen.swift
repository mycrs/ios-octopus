import SwiftUI
import OctopusDomain
import OctopusDesignSystem
import OctopusNavigation
import OctopusPlayback

public struct SettingsDependencies {
    public let playlists: PlaylistRepository
    public let sync: ContentSyncing
    public let progress: PlaybackProgressRepository
    public let history: WatchHistoryRepository
    /// Bayinin destek kanalları (panelden gelir).
    public let contact: ContactChannels
    public let parental: ParentalControlling
    /// Kategori görünürlük yönetimi için katalog depoları.
    public let channels: ChannelRepository?
    public let vod: VODRepository?
    public let series: SeriesRepository?
    public let playlistAccess: PlaylistAccessControlling
    public let activatePlaylist: @MainActor (Playlist.ID, String?) async throws -> Bool
    public let removePlaylistLock: @MainActor (Playlist.ID) async -> Void
    public let notifyPlaylistChanged: @MainActor () async -> Void
    /// Kilit durumu değişince açık katalog ekranlarını güvenle yeniler.
    public let notifyProtectionChanged: @MainActor () -> Void

    public init(
        playlists: PlaylistRepository,
        sync: ContentSyncing,
        progress: PlaybackProgressRepository,
        history: WatchHistoryRepository,
        contact: ContactChannels = .empty,
        parental: ParentalControlling = OpenParentalControl(),
        channels: ChannelRepository? = nil,
        vod: VODRepository? = nil,
        series: SeriesRepository? = nil,
        playlistAccess: PlaylistAccessControlling = OpenPlaylistAccessControl(),
        activatePlaylist: (@MainActor (Playlist.ID, String?) async throws -> Bool)? = nil,
        removePlaylistLock: @escaping @MainActor (Playlist.ID) async -> Void = { _ in },
        notifyPlaylistChanged: @escaping @MainActor () async -> Void = {},
        notifyProtectionChanged: @escaping @MainActor () -> Void = {}
    ) {
        self.playlists = playlists
        self.sync = sync
        self.progress = progress
        self.history = history
        self.contact = contact
        self.parental = parental
        self.channels = channels
        self.vod = vod
        self.series = series
        self.playlistAccess = playlistAccess
        self.activatePlaylist = activatePlaylist ?? { id, pin in
            if await playlistAccess.isProtected(id),
               !(await playlistAccess.isUnlocked(id)) {
                guard let pin, await playlistAccess.unlock(id, with: pin) else {
                    return false
                }
            }
            try await playlists.setActive(id: id)
            return true
        }
        self.removePlaylistLock = removePlaylistLock
        self.notifyPlaylistChanged = notifyPlaylistChanged
        self.notifyProtectionChanged = notifyProtectionChanged
    }
}

/// Ayarlar: kaynak, görünüm, veri ve künye.
///
/// Bölümler (`sourceSection`, `appearanceSection`, …) `SettingsSections.swift`
/// içinde bir `extension` olarak tanımlı, `SettingsRow` ise `SettingsRow.swift`
/// içinde — bu yüzden aşağıdaki depolama özellikleri `private` değil,
/// aynı modüldeki o dosyalar da erişebilsin diye modül-içi (varsayılan) erişimde.
public struct SettingsScreen: View {

    @StateObject var viewModel: SettingsViewModel
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var theme: ThemeController
    @EnvironmentObject var language: LanguageController
    @Environment(\.brandColor) var brandColor
    /// Oynatma tercihleri — `ThemeController` ile aynı desen: tek örnek,
    /// ortamdan geliyor, değişince oynatıcı bir sonraki yayında uyguluyor.
    @EnvironmentObject var playback: PlaybackPreferences

    let contact: ContactChannels
    @State var confirmingAction: DataAction?
    @State var isEnteringPIN = false
    @State var pinInput = ""
    @State var isChangingPIN = false
    @State var currentPINInput = ""
    @State var newPINInput = ""
    @State var confirmPINInput = ""
    @State var isManagingCategories = false
    @State var opensCategoriesAfterUnlock = false

    enum DataAction: String, Identifiable {
        case history
        case progress

        var id: String { rawValue }

        var title: String {
            switch self {
            case .history: return "İzleme geçmişi silinsin mi?"
            case .progress: return "Kaldığın yer bilgileri silinsin mi?"
            }
        }

        var message: String {
            switch self {
            case .history: return "Son izlenen kanallar listesi temizlenir."
            case .progress: return "Yarım bıraktığın film ve bölümler baştan başlar."
            }
        }
    }

    public init(dependencies: SettingsDependencies) {
        _viewModel = StateObject(wrappedValue: SettingsViewModel(dependencies: dependencies))
        self.contact = dependencies.contact
    }

    public var body: some View {
        ZStack {
            Theme.Palette.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    if let message = viewModel.message {
                        InlineMessageView(text: language.localized(message), kind: .info)
                    }

                    sourceSection
                    appearanceSection
                    languageSection
                    playbackSection
                    startupSection
                    parentalSection
                    dataSection
                    if contact.hasAny { supportSection }
                    aboutSection
                }
                .padding(Theme.Spacing.md)
            }
            .disabled(viewModel.isBusy)

            if viewModel.isBusy {
                LoadingStateView()
                    .background(.ultraThinMaterial)
            }
        }
        .navigationTitle("Ayarlar")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .confirmationDialog(
            language.localized(confirmingAction?.title ?? ""),
            isPresented: .init(
                get: { confirmingAction != nil },
                set: { if !$0 { confirmingAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Sil", role: .destructive) {
                let action = confirmingAction
                confirmingAction = nil
                Task {
                    switch action {
                    case .history: await viewModel.clearWatchHistory()
                    case .progress: await viewModel.clearPlaybackProgress()
                    case nil: break
                    }
                }
            }
            Button("Vazgeç", role: .cancel) { confirmingAction = nil }
        } message: {
            Text(language.localized(confirmingAction?.message ?? ""))
        }
        .alert(
            language.localized("PIN'i gir"),
            isPresented: $isEnteringPIN
        ) {
            // Güvenli alan: PIN ekranda görünmemeli.
            SecureField("4-8 rakam", text: $pinInput)
                .keyboardType(.numberPad)

            Button(language.localized("Aç")) {
                let pin = pinInput
                pinInput = ""
                Task {
                    let didUnlock = await viewModel.unlockProtectedContent(with: pin)
                    if didUnlock && opensCategoriesAfterUnlock {
                        opensCategoriesAfterUnlock = false
                        isManagingCategories = true
                    }
                }
            }
            Button("Vazgeç", role: .cancel) {
                pinInput = ""
                opensCategoriesAfterUnlock = false
            }
        } message: {
            Text(
                language.localized(
                    "Hassas içerikleri bu oturumda göstermek için PIN'ini gir."
                )
            )
        }
        .alert("PIN'i değiştir", isPresented: $isChangingPIN) {
            SecureField("Mevcut PIN", text: $currentPINInput)
                .keyboardType(.numberPad)
            SecureField("Yeni PIN", text: $newPINInput)
                .keyboardType(.numberPad)
            SecureField("Yeni PIN tekrar", text: $confirmPINInput)
                .keyboardType(.numberPad)

            Button("Kaydet") {
                let current = currentPINInput
                let new = newPINInput
                let confirmation = confirmPINInput
                clearPINChangeInputs()
                Task {
                    await viewModel.changeParentalPIN(
                        currentPIN: current,
                        newPIN: new,
                        confirmation: confirmation
                    )
                }
            }
            Button("Vazgeç", role: .cancel) { clearPINChangeInputs() }
        } message: {
            Text("İlk kullanımda mevcut PIN 0000'dır.")
        }
        .sheet(isPresented: $isManagingCategories) {
            CategoryVisibilitySheet(viewModel: viewModel)
                .environmentObject(language)
        }
    }

    private func clearPINChangeInputs() {
        currentPINInput = ""
        newPINInput = ""
        confirmPINInput = ""
    }
}
