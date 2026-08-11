import SwiftUI
import OctopusDomain
import OctopusDesignSystem

/// Yatay kategori şeridi.
///
/// Açılır menü yerine şerit: tek dokunuşla geçiş, mevcut seçim her zaman
/// görünür.
struct CategoryStripView: View {

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
                .foregroundColor(
                    isSelected ? Theme.Palette.accent : Theme.Palette.textSecondary
                )
                .clipShape(Capsule())
        }
    }
}
