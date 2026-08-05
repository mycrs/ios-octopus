import SwiftUI
import OctopusDomain
import OctopusDesignSystem
import OctopusNavigation

/// Film detayı: arka plan görseli, künye, oynat düğmesi.
public struct MovieDetailView: View {

    @StateObject private var viewModel: MovieDetailViewModel
    @EnvironmentObject private var router: AppRouter

    public init(movieID: Movie.ID, dependencies: VODDependencies) {
        _viewModel = StateObject(
            wrappedValue: MovieDetailViewModel(movieID: movieID, dependencies: dependencies)
        )
    }

    public var body: some View {
        ZStack {
            Theme.Palette.background.ignoresSafeArea()
            content
        }
        .navigationTitle(viewModel.movie?.title ?? "Film")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await viewModel.toggleFavorite() }
                } label: {
                    Image(systemName: viewModel.isFavorite ? "heart.fill" : "heart")
                        .foregroundColor(
                            viewModel.isFavorite ? Theme.Palette.live : Theme.Palette.textSecondary
                        )
                }
                .accessibilityLabel(
                    viewModel.isFavorite ? "Favorilerden çıkar" : "Favorilere ekle"
                )
            }
        }
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            LoadingStateView(message: "Film bilgisi yükleniyor")

        case .failed(let error):
            ErrorStateView(error: error) { Task { await viewModel.load() } }

        case .loaded:
            if let movie = viewModel.movie {
                detail(movie)
            }
        }
    }

    private func detail(_ movie: Movie) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header(movie)

                if let resumeFraction = viewModel.resumeFraction {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        ProgressView(value: resumeFraction)
                            .progressViewStyle(.linear)
                            .tint(Theme.Palette.accent)

                        Button("Baştan başlat") {
                            Task { await viewModel.resetProgress() }
                        }
                        .font(Theme.Typography.caption)
                        .tint(Theme.Palette.textSecondary)
                    }
                }

                if let plot = movie.plot, !plot.isEmpty {
                    Text(plot)
                        .font(Theme.Typography.rowSubtitle)
                        .foregroundColor(Theme.Palette.textSecondary)
                }

                credits(movie)
            }
            .padding(Theme.Spacing.md)
        }
    }

    private func header(_ movie: Movie) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            PosterView(url: movie.posterURL, width: 120)

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(movie.title)
                    .font(Theme.Typography.sectionTitle)
                    .foregroundColor(Theme.Palette.textPrimary)

                if let rating = movie.rating, rating > 0 {
                    Label(String(format: "%.1f", rating), systemImage: "star.fill")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Palette.warning)
                }

                if let metadata = viewModel.metadataLine {
                    Text(metadata)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Palette.textSecondary)
                }

                Button {
                    router.presentPlayer(.movie(movie.id))
                } label: {
                    Label(viewModel.playButtonTitle, systemImage: "play.fill")
                        .font(Theme.Typography.rowTitle)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Palette.accent)
                .padding(.top, Theme.Spacing.xs)
            }
        }
    }

    @ViewBuilder
    private func credits(_ movie: Movie) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if let director = movie.director, !director.isEmpty {
                creditRow(title: "Yönetmen", value: director)
            }
            if !movie.cast.isEmpty {
                creditRow(title: "Oyuncular", value: movie.cast.joined(separator: ", "))
            }
            if !movie.genres.isEmpty {
                creditRow(title: "Tür", value: movie.genres.joined(separator: ", "))
            }
        }
    }

    private func creditRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Palette.textTertiary)
            Text(value)
                .font(Theme.Typography.rowSubtitle)
                .foregroundColor(Theme.Palette.textSecondary)
        }
    }
}
