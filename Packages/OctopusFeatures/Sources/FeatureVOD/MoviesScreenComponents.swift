import SwiftUI
import OctopusDomain
import OctopusDesignSystem

/// Film ızgarasındaki tekil afiş.
struct MoviePosterCell: View {

    let movie: Movie
    let isFavorite: Bool
    let onTap: () -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                GridPosterView(url: movie.posterURL)
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
                        RatingBadge(rating: movie.rating)
                            .padding(Theme.Spacing.xs)
                    }

                Text(movie.title)
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
        // Afiş, kalp ve puan ayrı ayrı okunursa ızgarada gezinmek işkence
        // olur; hücre tek öğe, favori ise özel eylem.
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

/// Film ve dizi ekranlarında ortak kategori şeridi.
struct MediaCategoryStrip: View {

    let categories: [MediaCategory]
    let selectedID: MediaCategory.ID?
    let onSelect: (MediaCategory.ID?) -> Void

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
            // ⚠️ Seçili çip görünmüyorsa kullanıcı hangi kategoride
            // olduğunu bilemiyor: uzun listelerde şerit başa sarılı
            // kalıyor ama içerik 20. kategoriye ait oluyordu.
            .onChange(of: selectedID) { newValue in
                withAnimation(.easeInOut(duration: 0.25)) {
                    // ⚠️ Kimlikler **aynı tipte** olmalı: `MediaCategory.ID`
                    // ile `String` karıştırılınca `scrollTo` hiçbir şey
                    // bulamaz (derleyici de kabul etmiyor). Hepsi String.
                    proxy.scrollTo(newValue?.value ?? allChipID, anchor: .center)
                }
            }
        }
    }

    /// "Tümü" çipinin kimliği — `MediaCategory.ID` olmadığı için ayrı.
    private var allChipID: String { "__all__" }

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
                // Seçim rengi anında değil, yumuşak geçsin: kategori
                // değiştirmek ekranın en sık yapılan hareketi.
                .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}
