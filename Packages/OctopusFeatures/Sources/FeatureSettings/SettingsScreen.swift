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
public struct SettingsScreen: View {

    @StateObject private var viewModel: SettingsViewModel
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var theme: ThemeController

    private let contact: ContactChannels
    @State private var confirmingAction: DataAction?
    @State private var isEnteringPIN = false
    @State private var pinInput = ""

    private enum DataAction: String, Identifiable {
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

    // MARK: - Bölümler

    private var sourceSection: some View {
        section("Kaynak") {
            SettingsRow(
                icon: "antenna.radiowaves.left.and.right",
                title: viewModel.activePlaylistName ?? "Kaynak seçilmedi",
                detail: viewModel.lastSyncedText
            ) {
                router.push(.playlistManager)
            }

            SettingsRow(icon: "arrow.clockwise", title: "Şimdi güncelle") {
                Task { await viewModel.resyncActivePlaylist() }
            }

            if viewModel.playlistCount > 1 {
                Text("\(viewModel.playlistCount) kaynak kayıtlı")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Palette.textTertiary)
            }
        }
    }

    private var appearanceSection: some View {
        section("Görünüm") {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Vurgu rengi")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Palette.textSecondary)

                HStack(spacing: Theme.Spacing.md) {
                    ForEach(Theme.BrandColor.allCases, id: \.self) { option in
                        Button {
                            theme.select(option)
                        } label: {
                            Circle()
                                .fill(option.color)
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Circle()
                                        .strokeBorder(
                                            theme.selection == option
                                                ? Theme.Palette.textPrimary
                                                : Color.clear,
                                            lineWidth: 2
                                        )
                                )
                        }
                        .accessibilityLabel(option.rawValue)
                    }
                }

                // Bayi markası varsa "Varsayılan" onun rengini kullanır.
                if let resellerName = theme.resellerName {
                    Text("Varsayılan renk \(resellerName) tarafından belirleniyor.")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Palette.textTertiary)
                }
            }
        }
    }

    private var startupSection: some View {
        section("Açılış") {
            // Menü seçici: dört başlık segment'e sığmıyor, dar ekranda
            // "Ana Say…" gibi kırpılıyordu.
            Picker(selection: $router.startupTab) {
                ForEach(AppTab.startupOptions) { tab in
                    Label(tab.title, systemImage: tab.icon).tag(tab)
                }
            } label: {
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "arrow.right.to.line")
                        .foregroundColor(Theme.Palette.accent)
                        .frame(width: 24)
                    Text("Açılış ekranı")
                        .font(Theme.Typography.rowTitle)
                        .foregroundColor(Theme.Palette.textPrimary)
                }
            }
            .pickerStyle(.menu)
            .padding(Theme.Spacing.md)
            .background(Theme.Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        }
    }

    private var parentalSection: some View {
        section("Ebeveyn kilidi") {
            SettingsRow(
                icon: viewModel.isParentalEnabled ? "lock.fill" : "lock.open",
                title: viewModel.isParentalEnabled ? "Kilidi kaldır" : "Kilit kur",
                detail: viewModel.isParentalEnabled
                    ? "Yetişkin içerik listelerde gizleniyor"
                    : "PIN belirleyerek yetişkin içeriği gizle"
            ) {
                isEnteringPIN = true
            }
        }
    }

    private var dataSection: some View {
        section("Veriler") {
            SettingsRow(icon: "clock.arrow.circlepath", title: "İzleme geçmişini sil") {
                confirmingAction = .history
            }
            SettingsRow(icon: "play.slash", title: "Kaldığın yer bilgilerini sil") {
                confirmingAction = .progress
            }
            // Onay istemiyor: veri kaybı yok, görseller yeniden indirilir.
            SettingsRow(
                icon: "photo.on.rectangle",
                title: "Görsel önbelleğini temizle",
                detail: "Afiş ve logolar yeniden indirilir"
            ) {
                Task { await viewModel.clearImageCache() }
            }
        }
    }

    private var supportSection: some View {
        section("Destek") {
            ContactLinksView(contact: contact)
        }
    }

    private var aboutSection: some View {
        section("Uygulama") {
            HStack {
                Text("Sürüm")
                    .font(Theme.Typography.rowSubtitle)
                    .foregroundColor(Theme.Palette.textSecondary)
                Spacer()
                Text(viewModel.appVersion)
                    .font(Theme.Typography.rowSubtitle)
                    .foregroundColor(Theme.Palette.textTertiary)
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        }
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Typography.sectionTitle)
                .foregroundColor(Theme.Palette.textPrimary)
            content()
        }
    }
}

private struct SettingsRow: View {

    let icon: String
    let title: String
    var detail: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: icon)
                    .foregroundColor(Theme.Palette.accent)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(title)
                        .font(Theme.Typography.rowTitle)
                        .foregroundColor(Theme.Palette.textPrimary)
                        .multilineTextAlignment(.leading)

                    if let detail {
                        Text(detail)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Palette.textTertiary)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Palette.textTertiary)
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
