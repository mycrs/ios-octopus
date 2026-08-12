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

    private var allChipID: String { "__live_all__" }

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
