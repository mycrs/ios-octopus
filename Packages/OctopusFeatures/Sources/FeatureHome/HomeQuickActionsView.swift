import SwiftUI
import OctopusDesignSystem

/// İçerik raflarından ayrı duran, liste yönetimine ait hızlı işlemler.
struct HomeQuickActionsView: View {
    let canRefresh: Bool
    let isRefreshing: Bool
    let message: String?
    let messageIsError: Bool
    let onAdd: () -> Void
    let onRefresh: () -> Void

    @Environment(\.brandColor) private var brandColor
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                actionButton(
                    title: "Yeni liste",
                    icon: "plus.rectangle.on.rectangle",
                    isPrimary: true,
                    action: onAdd
                )

                actionButton(
                    title: "Listeyi yenile",
                    icon: "arrow.clockwise",
                    isPrimary: false,
                    showsProgress: isRefreshing,
                    action: onRefresh
                )
                .disabled(!canRefresh)
                .opacity(canRefresh || isRefreshing ? 1 : 0.48)
            }

            if let message {
                InlineMessageView(
                    text: message,
                    kind: messageIsError ? .error : .info
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .animation(.easeInOut(duration: 0.2), value: message)
    }

    private func actionButton(
        title: String,
        icon: String,
        isPrimary: Bool,
        showsProgress: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.light()
            action()
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                if showsProgress {
                    ProgressView()
                        .tint(isPrimary ? .white : brandColor)
                } else {
                    Image(systemName: icon)
                }

                Text(AppLocalization.localized(title, locale: locale))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .font(Theme.Typography.caption.weight(.semibold))
            .foregroundColor(isPrimary ? .white : Theme.Palette.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                isPrimary ? brandColor : Theme.Palette.surface,
                in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .stroke(
                        isPrimary ? Color.white.opacity(0.08) : brandColor.opacity(0.18),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppLocalization.localized(title, locale: locale))
    }
}
