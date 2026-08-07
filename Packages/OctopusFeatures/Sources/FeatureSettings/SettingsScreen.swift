import SwiftUI
import OctopusDomain
import OctopusDesignSystem
import OctopusNavigation

public struct SettingsDependencies {
    public let playlists: PlaylistRepository
    public let sync: ContentSyncing
    public let progress: PlaybackProgressRepository
    public let history: WatchHistoryRepository
    /// Bayinin destek kanalları (panelden gelir).
    public let contact: ContactChannels
    public let parental: ParentalControlling

    public init(
        playlists: PlaylistRepository,
        sync: ContentSyncing,
        progress: PlaybackProgressRepository,
        history: WatchHistoryRepository,
        contact: ContactChannels = .empty,
        parental: ParentalControlling = OpenParentalControl()
    ) {
        self.playlists = playlists
        self.sync = sync
        self.progress = progress
        self.history = history
        self.contact = contact
        self.parental = parental
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

    let contact: ContactChannels
    @State var confirmingAction: DataAction?
    @State var isEnteringPIN = false
    @State var pinInput = ""

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
                        InlineMessageView(text: message, kind: .info)
                    }

                    sourceSection
                    appearanceSection
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
            confirmingAction?.title ?? "",
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
            Text(confirmingAction?.message ?? "")
        }
        .alert(
            viewModel.isParentalEnabled ? "PIN'i gir" : "Yeni PIN belirle",
            isPresented: $isEnteringPIN
        ) {
            // Güvenli alan: PIN ekranda görünmemeli.
            SecureField("4-8 rakam", text: $pinInput)
                .keyboardType(.numberPad)

            Button(viewModel.isParentalEnabled ? "Kilidi kaldır" : "Kur") {
                let pin = pinInput
                pinInput = ""
                Task {
                    if viewModel.isParentalEnabled {
                        await viewModel.disableParental(with: pin)
                    } else {
                        await viewModel.setParentalPIN(pin)
                        // Kilit kurulduysa açık ekranları kapat: yetişkin bir
                        // içeriğin detayı yığında durup geri dönünce açılmasın.
                        if viewModel.isParentalEnabled {
                            router.clearOpenScreens()
                        }
                    }
                }
            }
            Button("Vazgeç", role: .cancel) { pinInput = "" }
        } message: {
            Text(
                viewModel.isParentalEnabled
                    ? "Kilidi kaldırmak için mevcut PIN'i gir."
                    : "Yetişkin içerik listelerden gizlenecek. PIN'i unutursan uygulamayı silip yeniden kurman gerekir."
            )
        }
    }
}
