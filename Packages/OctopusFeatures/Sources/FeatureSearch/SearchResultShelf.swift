import SwiftUI
import OctopusDesignSystem

struct SearchResultShelf<Content: View>: View {

    let title: String
    let icon: String
    let count: Int
    private let content: Content

    @Environment(\.brandColor) private var brandColor
    @Environment(\.locale) private var locale

    init(
        title: String,
        icon: String,
        count: Int,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.count = count
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            header

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: Theme.Spacing.md) {
                    content
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.sm)
            }
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(brandColor.opacity(0.14))
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(brandColor)
            }
            .frame(width: 30, height: 30)

            Text(AppLocalization.localized(title, locale: locale))
                .font(Theme.Typography.sectionTitle)
                .foregroundColor(Theme.Palette.textPrimary)

            Text("\(count)")
                .font(Theme.Typography.badge)
                .foregroundColor(brandColor)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.xxs)
                .background(brandColor.opacity(0.12), in: Capsule())

            Spacer(minLength: 0)

            if count > 2 {
                HStack(spacing: Theme.Spacing.xs) {
                    Text("Kaydır")
                    Image(systemName: "chevron.right")
                }
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Palette.textTertiary)
                .accessibilityLabel("Daha fazla içerik için sağa kaydır")
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
    }
}
