import SwiftUI
import OctopusDomain
import OctopusDesignSystem

/// Dizi ızgarasındaki tekil afiş.
struct SeriesPosterCell: View {

    let series: Series
    let isFavorite: Bool
    let onTap: () -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                GridPosterView(url: series.posterURL)
                    .overlay(alignment: .topTrailing) {
                        if isFavorite {
                            Image(systemName: "heart.fill")
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Palette.live)
                                .padding(Theme.Spacing.xs)
                                .background(.ultraThinMaterial, in: Circle())
                                .padding(Theme.Spacing.xs)
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        RatingBadge(rating: series.rating)
                            .padding(Theme.Spacing.xs)
                    }

                Text(series.title)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Palette.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    // Hücre genişliğini doldur; sabit genişlik iPad'de
                    // başlıkları afişten dar bırakıyordu.
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        // Hücre tek öğe olarak okunur; favori özel eylem.
        .accessibilityElement(children: .combine)
        .accessibilityAction(
            named: isFavorite ? "Favorilerden çıkar" : "Favorilere ekle",
            onToggleFavorite
        )
        .contextMenu {
            Button {
                onToggleFavorite()
            } label: {
                Label(
                    isFavorite ? "Favorilerden çıkar" : "Favorilere ekle",
                    systemImage: isFavorite ? "heart.slash" : "heart"
                )
            }
        }
    }
}

/// Dizi ekranının kategori şeridi.
///
/// `FeatureVOD`'daki şeritle aynı görünür ama feature'lar birbirini import
/// edemez. Ortak bir bileşen `OctopusDesignSystem`'e taşınabilirdi; şimdilik
/// iki küçük kopya, modül sınırını delmekten daha ucuz.
struct SeriesCategoryStrip: View {

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
            Group {
                if title == "Tümü" {
                    Text("Tümü")
                } else {
                    Text(title)
                }
            }
                .font(Theme.Typography.caption)
                .lineLimit(1)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(isSelected ? Theme.Palette.accentMuted : Theme.Palette.surface)
                .foregroundColor(isSelected ? Theme.Palette.accent : Theme.Palette.textSecondary)
                .clipShape(Capsule())
        }
    }
}
