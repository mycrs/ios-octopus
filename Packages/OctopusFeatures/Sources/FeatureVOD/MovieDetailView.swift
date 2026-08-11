import SwiftUI
import OctopusDomain
import OctopusDesignSystem
import OctopusNavigation

/// Film detayı: sinematik başlık, künye çipleri, oynat düğmesi, özet.
///
/// Görsel dil dizi detayıyla **aynı** — ikisi de `DetailHeaderView` kullanır.
public struct MovieDetailView: View {

    @StateObject private var viewModel: MovieDetailViewModel
    @EnvironmentObject private var router: AppRouter
    @Environment(\.locale) private var locale

    /// Uzun özetler ekranı doldurmasın; kullanıcı isterse açar.
    @State private var isPlotExpanded = false

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
        // Başlık boş: film adı zaten sinematik başlıkta duruyor, tepede
        // ikinci kez yazmak arka plan görselini gereksiz yere örtüyordu.
        .navigationBarTitleDisplayMode(.inline)
        // ⚠️ Çubuğun opak zemini arka plan görselinin **üst kısmını ve
        // afişin tepesini** örtüyordu: görsel ekranın tepesinden başladığı
        // hâlde ilk ~110pt'si koyu bir bant olarak görünüyor, afiş oradan
        // kesiliyordu. Zemin gizlenince görsel duruma çubuğuna kadar uzanır;
        // geri düğmesinin okunurluğunu `DetailHeaderView`'ın üst perdesi taşır.
        .toolbarBackground(.hidden, for: .navigationBar)
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
                DetailHeaderView(
                    backdropURL: movie.backdropURL,
                    posterURL: movie.posterURL,
                    title: movie.title,
                    chips: viewModel.chips
                ) {
                    actions(movie)
                }

                if viewModel.resumeFraction != nil {
                    resumeBlock
                }

                if let plot = movie.plot, !plot.isEmpty {
                    plotBlock(plot)
                }

                credits(movie)
            }
            // Başlık kendi yatay boşluğunu yönetir; yalnızca alt boşluk burada.
            .padding(.bottom, Theme.Spacing.xl)
        }
        // Arka plan görseli durum çubuğunun altına uzansın.
        .ignoresSafeArea(edges: .top)
    }

    private func actions(_ movie: Movie) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
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

    private var resumeBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            ProgressView(value: viewModel.resumeFraction ?? 0)
                .progressViewStyle(.linear)
                .tint(Theme.Palette.accent)

            Button("Baştan başlat") {
                Task { await viewModel.resetProgress() }
            }
            .font(Theme.Typography.caption)
            .tint(Theme.Palette.textSecondary)
        }
        .padding(.horizontal, Theme.Spacing.md)
    }

    private func plotBlock(_ plot: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(plot)
                .font(Theme.Typography.rowSubtitle)
                .foregroundColor(Theme.Palette.textSecondary)
                .lineLimit(isPlotExpanded ? nil : 4)
                .fixedSize(horizontal: false, vertical: true)

            // Kısa özetlerde düğme gereksiz yer kaplamasın.
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

    @ViewBuilder
    private func credits(_ movie: Movie) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
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
        .padding(.horizontal, Theme.Spacing.md)
    }

    private func creditRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(AppLocalization.localized(title, locale: locale))
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Palette.textTertiary)
            Text(value)
                .font(Theme.Typography.rowSubtitle)
                .foregroundColor(Theme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
