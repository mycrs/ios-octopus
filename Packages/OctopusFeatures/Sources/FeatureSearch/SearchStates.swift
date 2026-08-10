import SwiftUI
import OctopusDesignSystem

struct SearchWelcomeState: View {

    @Environment(\.brandColor) private var brandColor

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            ZStack {
                Circle()
                    .fill(brandColor.opacity(0.08))
                    .frame(width: 138, height: 138)

                Circle()
                    .fill(brandColor.opacity(0.14))
                    .frame(width: 98, height: 98)

                Image(systemName: "magnifyingglass")
                    .font(.system(size: 38, weight: .medium))
                    .foregroundColor(brandColor)
            }

            VStack(spacing: Theme.Spacing.sm) {
                Text("Her şey tek aramada")
                    .font(Theme.Typography.sectionTitle)
                    .foregroundColor(Theme.Palette.textPrimary)

                Text("Canlı yayın, film ve dizileri aynı anda keşfet.")
                    .font(Theme.Typography.rowSubtitle)
                    .foregroundColor(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: Theme.Spacing.sm) {
                mediaChip("tv.fill", "Canlı TV")
                mediaChip("film.fill", "Film")
                mediaChip("rectangle.stack.fill", "Dizi")
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func mediaChip(_ icon: String, _ title: String) -> some View {
        Label(title, systemImage: icon)
            .font(Theme.Typography.caption.weight(.semibold))
            .foregroundColor(Theme.Palette.textSecondary)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Theme.Palette.surface, in: Capsule())
            .overlay {
                Capsule().stroke(Color.white.opacity(0.06), lineWidth: 1)
            }
    }
}

struct SearchNoResultsState: View {

    let query: String
    let onClear: () -> Void
    @Environment(\.brandColor) private var brandColor

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32, weight: .medium))
                .foregroundColor(brandColor)
                .frame(width: 74, height: 74)
                .background(brandColor.opacity(0.12), in: Circle())

            VStack(spacing: Theme.Spacing.xs) {
                Text("“\(query)” için sonuç yok")
                    .font(Theme.Typography.sectionTitle)
                    .foregroundColor(Theme.Palette.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Yazımı kontrol et veya daha kısa bir arama dene.")
                    .font(Theme.Typography.rowSubtitle)
                    .foregroundColor(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Button("Aramayı temizle", action: onClear)
                .buttonStyle(.bordered)
                .tint(brandColor)
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SearchShelvesSkeleton: View {

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                shelf(cardWidth: 184, cardHeight: 138)
                shelf(cardWidth: 132, cardHeight: 198)
            }
            .padding(.vertical, Theme.Spacing.md)
        }
        .accessibilityElement()
        .accessibilityLabel("Arama sonuçları yükleniyor")
    }

    private func shelf(cardWidth: CGFloat, cardHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SkeletonBox(cornerRadius: Theme.Radius.sm)
                .frame(width: 150, height: 24)
                .padding(.horizontal, Theme.Spacing.md)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.md) {
                    ForEach(0..<3, id: \.self) { _ in
                        SkeletonBox(cornerRadius: Theme.Radius.lg)
                            .frame(width: cardWidth, height: cardHeight)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
            }
        }
    }
}
