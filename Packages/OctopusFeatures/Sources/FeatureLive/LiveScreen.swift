import SwiftUI
import OctopusDomain
import OctopusDesignSystem
import OctopusNavigation

public struct LiveDependencies {
    public let playlists: PlaylistRepository
    public let channels: ChannelRepository
    public let epg: EPGRepository
    public let favorites: FavoritesRepository

    public init(
        playlists: PlaylistRepository,
        channels: ChannelRepository,
        epg: EPGRepository,
        favorites: FavoritesRepository
    ) {
        self.playlists = playlists
        self.channels = channels
        self.epg = epg
        self.favorites = favorites
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
                : "Bu kaynakta kanal bulunamadı. Ayarlar'dan yenilemeyi dene."
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
                        onToggleFavorite: { Task { await viewModel.toggleFavorite(channel) } }
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
private struct ChannelRowView: View {

    let channel: Channel
    let program: EPGProgram?
    let clock: Date
    let isFavorite: Bool
    let onTap: () -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Theme.Spacing.md) {
                ChannelLogoView(url: channel.logoURL)

                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(channel.name)
                        .font(Theme.Typography.rowTitle)
                        .foregroundColor(Theme.Palette.textPrimary)
                        .lineLimit(1)

                    if let program {
                        // Şu an oynayan program + ne kadarının geçtiği.
                        Text(program.title)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Palette.textSecondary)
                            .lineLimit(1)

                        ProgressView(value: program.progress(at: clock))
                            .progressViewStyle(.linear)
                            .tint(Theme.Palette.accent)
                            .frame(height: 2)
                    } else if let number = channel.number {
                        Text("Kanal \(number)")
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
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isFavorite ? "Favorilerden çıkar" : "Favorilere ekle")
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
