import SwiftUI
import OctopusDomain
import OctopusDesignSystem
import OctopusNavigation

public struct LiveDependencies {
    public let playlists: PlaylistRepository
    public let channels: ChannelRepository
    public let epg: EPGRepository
    public let favorites: FavoritesRepository
    /// Kilit açıkken yetişkin kanallar listeden gizlenir.
    public let parental: ParentalControlling

    public init(
        playlists: PlaylistRepository,
        channels: ChannelRepository,
        epg: EPGRepository,
        favorites: FavoritesRepository,
        parental: ParentalControlling = OpenParentalControl()
    ) {
        self.playlists = playlists
        self.channels = channels
        self.epg = epg
        self.favorites = favorites
        self.parental = parental
    }
}

/// Canlı TV: kategori şeridi + kanal listesi + arama.
///
/// ⚠️ Bu ekran oynatıcıyı doğrudan **açmaz**; `router.presentPlayer(...)`
/// çağırır. `FeaturePlayer`'ı import etmez, bu yüzden ikisi bağımsız derlenir.
public struct LiveScreen: View {

    @StateObject private var viewModel: LiveChannelsViewModel
    @EnvironmentObject private var router: AppRouter

    public init(dependencies: LiveDependencies) {
        _viewModel = StateObject(wrappedValue: LiveChannelsViewModel(dependencies: dependencies))
    }

    public var body: some View {
        ZStack {
            Theme.Palette.background.ignoresSafeArea()

            VStack(spacing: 0) {
                if !viewModel.categories.isEmpty && !viewModel.isSearching {
                    CategoryStripView(
                        categories: viewModel.categories,
                        selectedID: viewModel.selectedCategoryID,
                        onSelect: viewModel.selectCategory
                    )
                }
                content
            }
        }
        .navigationTitle("Canlı TV")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $viewModel.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Kanal ara"
        )
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            LoadingStateView(message: "Kanallar yükleniyor")

        case .failed(let error):
            ErrorStateView(error: error) {
                Task { await viewModel.load() }
            }

        case .loaded:
            if viewModel.channels.isEmpty {
                emptyState
            } else {
                channelList
            }
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: viewModel.isSearching ? "magnifyingglass" : "tv",
            title: viewModel.isSearching ? "Sonuç yok" : "Kanal yok",
            message: viewModel.isSearching
                ? "Farklı bir arama dene."
                : "Bu kaynakta kanal bulunamadı. Kaynağı güncellemeyi dene.",
            actionTitle: viewModel.isSearching ? nil : "Ayarlar'a git",
            action: viewModel.isSearching ? nil : { router.push(.about) }
        )
    }

    private var channelList: some View {
        ScrollView {
            // LazyVStack: 20.000 kanallı listede yalnızca görünen satırlar
            // oluşturulur.
            LazyVStack(spacing: Theme.Spacing.xs) {
                ForEach(viewModel.channels) { channel in
                    ChannelRowView(
                        channel: channel,
                        program: viewModel.currentProgram(for: channel),
                        clock: viewModel.clock,
                        isFavorite: viewModel.isFavorite(channel),
                        onTap: { router.presentPlayer(.liveChannel(channel.id)) },
                        onToggleFavorite: { Task { await viewModel.toggleFavorite(channel) } },
                        onShowGuide: { router.push(.channelGuide(channel.id)) }
                    )
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
        }
    }
}

/// Yatay kategori şeridi.
///
/// Açılır menü yerine şerit: tek dokunuşla geçiş, mevcut seçim her zaman
/// görünür.
private struct CategoryStripView: View {

    let categories: [MediaCategory]
    let selectedID: MediaCategory.ID?
    let onSelect: (MediaCategory.ID?) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                chip(title: "Tümü", isSelected: selectedID == nil) { onSelect(nil) }

                ForEach(categories) { category in
                    chip(title: category.name, isSelected: selectedID == category.id) {
                        onSelect(category.id)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
        }
    }

    private func chip(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Typography.caption)
                .lineLimit(1)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(isSelected ? Theme.Palette.accentMuted : Theme.Palette.surface)
                .foregroundColor(
                    isSelected ? Theme.Palette.accent : Theme.Palette.textSecondary
                )
                .clipShape(Capsule())
        }
    }
}

/// Tek kanal satırı.
///
/// Referanstaki TV kartının telefon karşılığı: numara, ad, o an yayında
/// olan program ve kalan süre. TV sürümünde bunlar geniş bir yan panelde
/// duruyordu; burada tek satıra sığması gerekiyor.
private struct ChannelRowView: View {

    let channel: Channel
    let program: EPGProgram?
    let clock: Date
    let isFavorite: Bool
    let onTap: () -> Void
    let onToggleFavorite: () -> Void
    let onShowGuide: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Theme.Spacing.md) {
                ChannelLogoView(url: channel.logoURL)

                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    HStack(spacing: Theme.Spacing.sm) {
                        // Kanal numarası her zaman görünür: kullanıcılar
                        // kanalları numarayla hatırlıyor ve yayın akışı
                        // olsun olmasın numara aynı yerde durmalı.
                        if let number = channel.number {
                            Text("\(number)")
                                .font(.system(.caption2, design: .monospaced).weight(.semibold))
                                .foregroundColor(Theme.Palette.textTertiary)
                                .frame(minWidth: 26, alignment: .trailing)
                        }

                        Text(channel.name)
                            .font(Theme.Typography.rowTitle)
                            .foregroundColor(Theme.Palette.textPrimary)
                            .lineLimit(1)
                    }

                    if let program {
                        programLine(program)
                    } else {
                        // ⚠️ Boş bırakmak yerine sebebi yazılıyor: bazı
                        // kanalların rehberi sunucuda gerçekten yok, veri
                        // uydurmak yanıltıcı olur.
                        Text("Yayın akışı yok")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Palette.textTertiary)
                    }
                }

                Spacer(minLength: 0)

                Button(action: onToggleFavorite) {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .foregroundColor(
                            isFavorite ? Theme.Palette.live : Theme.Palette.textTertiary
                        )
                        // Dokunma hedefi ikondan büyük: 17pt'lik bir kalbe
                        // isabet ettirmek zor ve yanlışlıkla satır açılıyordu.
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // Satır tek bir öğe olarak okunuyor; bu düğme onun içinde
                // kaybolmasın diye erişilebilirlikten çıkarılıp aşağıda
                // özel eylem olarak sunuluyor.
                .accessibilityHidden(true)
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        // ⚠️ VoiceOver: satır **tek** öğe olarak okunur (numara, ad, program
        // ardı ardına), favori ve rehber ise özel eylem olarak sunulur.
        // İç içe düğme bırakmak, kullanıcıyı her satırda üç kez durduruyordu.
        .accessibilityElement(children: .combine)
        .accessibilityAction(
            named: isFavorite ? "Favorilerden çıkar" : "Favorilere ekle",
            onToggleFavorite
        )
        .accessibilityAction(named: "Yayın akışı", onShowGuide)
        .contextMenu {
            // Rehber uzun basmada: satırda ikinci bir düğme dokunma
            // hedeflerini daraltıyordu.
            Button(action: onShowGuide) {
                Label("Yayın akışı", systemImage: "calendar")
            }
            Button(action: onToggleFavorite) {
                Label(
                    isFavorite ? "Favorilerden çıkar" : "Favorilere ekle",
                    systemImage: isFavorite ? "heart.slash" : "heart"
                )
            }
        }
    }

    /// O an yayında olan program: ad, kalan süre ve ilerleme.
    private func programLine(_ program: EPGProgram) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            HStack(spacing: Theme.Spacing.sm) {
                Text(program.title)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Palette.textSecondary)
                    .lineLimit(1)

                if let remaining = LiveChannelsViewModel.remainingText(program, at: clock) {
                    Text(remaining)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Palette.accent)
                        .lineLimit(1)
                        // Program adı uzunsa kalan süre kırpılmasın:
                        // asıl bilgi "daha ne kadar var".
                        .layoutPriority(1)
                }
            }

            ProgressView(value: program.progress(at: clock))
                .progressViewStyle(.linear)
                .tint(Theme.Palette.accent)
                .frame(height: 2)
        }
    }

}
