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
                GridPosterView(url: series.posterURL, fallbackTitle: series.title)
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
    @Environment(\.brandColor) private var brandColor

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    chip(title: "Tümü", isSelected: selectedID == nil) { onSelect(nil) }
                        .id(allChipID)

                    ForEach(categories) { category in
                        chip(title: category.name, isSelected: selectedID == category.id) {
                            onSelect(category.id)
                        }
                        .id(category.id.value)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
            }
            .onChange(of: selectedID) { newValue in
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(newValue?.value ?? allChipID, anchor: .center)
                }
            }
        }
    }

    private var allChipID: String { "__series_all__" }

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
                .background(isSelected ? brandColor.opacity(0.18) : Theme.Palette.surface)
                .foregroundColor(isSelected ? brandColor : Theme.Palette.textSecondary)
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(isSelected ? brandColor.opacity(0.35) : .clear, lineWidth: 1)
                }
                .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}
