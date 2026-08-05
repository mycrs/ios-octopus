import SwiftUI
import OctopusDomain
import OctopusDesignSystem
import OctopusNavigation

/// Dizi detayı: künye, sezon seçici, bölüm listesi.
public struct SeriesDetailView: View {

    @StateObject private var viewModel: SeriesDetailViewModel
    @EnvironmentObject private var router: AppRouter

    /// Uzun özetler ekranı doldurmasın; kullanıcı isterse açar.
    @State private var isPlotExpanded = false

    public init(seriesID: Series.ID, dependencies: SeriesDependencies) {
        _viewModel = StateObject(
            wrappedValue: SeriesDetailViewModel(seriesID: seriesID, dependencies: dependencies)
        )
    }

    public var body: some View {
        ZStack {
            Theme.Palette.background.ignoresSafeArea()
            content
        }
        // Başlık boş: dizi adı sinematik başlıkta duruyor, tepede ikinci
        // kez yazmak arka plan görselini gereksiz yere örtüyordu.
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.refresh() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            LoadingStateView(message: "Bölümler yükleniyor")

        case .failed(let error):
            ErrorStateView(error: error) { Task { await viewModel.load() } }

        case .loaded:
            if viewModel.seasons.isEmpty {
                EmptyStateView(
                    icon: "rectangle.stack.badge.minus",
                    title: "Bölüm bulunamadı",
                    message: "Bu dizi için sağlayıcıda bölüm bilgisi yok.",
                    actionTitle: "Yeniden dene",
                    action: { Task { await viewModel.refresh() } }
                )
            } else {
                list
            }
        }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                if let series = viewModel.series {
                    header(series)
                }

                if let plot = viewModel.series?.plot, !plot.isEmpty {
                    plotBlock(plot)
                }

                if viewModel.seasons.count > 1 {
                    SeasonPickerView(
                        seasons: viewModel.seasons,
                        selectedNumber: viewModel.selectedSeasonNumber,
                        onSelect: { number in Task { await viewModel.selectSeason(number) } }
                    )
                    .padding(.horizontal, Theme.Spacing.md)
                }

                LazyVStack(spacing: Theme.Spacing.sm) {
                    ForEach(viewModel.episodes) { episode in
                        EpisodeRowView(
                            episode: episode,
                            isWatched: viewModel.isWatched(episode),
                            progress: viewModel.progress(for: episode),
                            onTap: { router.presentPlayer(.episode(episode.id)) }
                        )
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
            }
            .padding(.bottom, Theme.Spacing.xl)
        }
        // Arka plan görseli durum çubuğunun altına uzansın.
        .ignoresSafeArea(edges: .top)
    }

    private func header(_ series: Series) -> some View {
        DetailHeaderView(
            backdropURL: series.backdropURL,
            posterURL: series.posterURL,
            title: series.title,
            subtitle: viewModel.seasonSummary,
            chips: viewModel.chips
        ) {
            actions
        }
    }

    private var actions: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Button {
                if let episode = viewModel.resumeEpisode {
                    router.presentPlayer(.episode(episode.id))
                }
            } label: {
                Label(viewModel.playButtonTitle, systemImage: "play.fill")
                    .font(Theme.Typography.rowTitle)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.sm)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.Palette.accent)
            .disabled(viewModel.resumeEpisode == nil)

            Button {
                Task { await viewModel.toggleFavorite() }
            } label: {
                Image(systemName: viewModel.isFavorite ? "heart.fill" : "heart")
                    .font(Theme.Typography.rowTitle)
                    .frame(width: 44)
                    .padding(.vertical, Theme.Spacing.sm)
            }
            .buttonStyle(.bordered)
            .tint(viewModel.isFavorite ? Theme.Palette.live : Theme.Palette.textSecondary)
            .accessibilityLabel(viewModel.isFavorite ? "Favorilerden çıkar" : "Favorilere ekle")
        }
    }

    private func plotBlock(_ plot: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(plot)
                .font(Theme.Typography.rowSubtitle)
                .foregroundColor(Theme.Palette.textSecondary)
                .lineLimit(isPlotExpanded ? nil : 4)
                .fixedSize(horizontal: false, vertical: true)

            if plot.count > 180 {
                Button(isPlotExpanded ? "Daha az" : "Devamını oku") {
                    withAnimation(.easeInOut(duration: 0.2)) { isPlotExpanded.toggle() }
                }
                .font(Theme.Typography.caption)
                .tint(Theme.Palette.accent)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
    }
}

/// Sezon seçici. Tek sezonlu dizilerde hiç gösterilmez.
private struct SeasonPickerView: View {

    let seasons: [Season]
    let selectedNumber: Int?
    let onSelect: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(seasons) { season in
                    Button {
                        onSelect(season.number)
                    } label: {
                        Text(season.name ?? "\(season.number). Sezon")
                            .font(Theme.Typography.caption)
                            .lineLimit(1)
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.sm)
                            .background(
                                selectedNumber == season.number
                                    ? Theme.Palette.accentMuted
                                    : Theme.Palette.surface
                            )
                            .foregroundColor(
                                selectedNumber == season.number
                                    ? Theme.Palette.accent
                                    : Theme.Palette.textSecondary
                            )
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }
}

/// Bölüm satırı: kapak, başlık, izlendi işareti veya kaldığı yer çubuğu.
private struct EpisodeRowView: View {

    let episode: Episode
    let isWatched: Bool
    let progress: Double?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Theme.Spacing.md) {
                ZStack {
                    RemoteImageView(url: episode.stillURL, contentMode: .fill, targetWidth: 96) {
                        ZStack {
                            Theme.Palette.surfaceElevated
                            Image(systemName: "play.rectangle")
                                .foregroundColor(Theme.Palette.textTertiary)
                        }
                    }
                    .frame(width: 96, height: 54)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))

                    if isWatched {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Theme.Palette.success)
                            .background(Circle().fill(.black.opacity(0.4)))
                    }
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text("\(episode.number). \(episode.title)")
                        .font(Theme.Typography.rowTitle)
                        .foregroundColor(
                            isWatched ? Theme.Palette.textSecondary : Theme.Palette.textPrimary
                        )
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if let durationSeconds = episode.durationSeconds, durationSeconds > 0 {
                        Text("\(durationSeconds / 60) dk")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Palette.textTertiary)
                    }

                    if let progress {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .tint(Theme.Palette.accent)
                            .frame(height: 2)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(Theme.Spacing.sm)
            .background(Theme.Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
