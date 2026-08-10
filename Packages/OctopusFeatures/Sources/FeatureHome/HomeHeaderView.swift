import SwiftUI
import OctopusDesignSystem

/// Ana sayfanın sinematik karşılama alanı.
/// Teknik kaynak bilgileri yerine kullanıcının yapmak istediği iki ana işi öne çıkarır.
struct HomeHeaderView: View {
    let account: HomeAccount?
    let greeting: String
    let onWatchLive: () -> Void
    let onExplore: () -> Void

    @Environment(\.brandColor) private var brandColor

    var body: some View {
        ZStack(alignment: .topLeading) {
            background
            decoration

            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                topRow
                greetingBlock
                actions
                statusLine
            }
            .padding(Theme.Spacing.xl)
        }
        .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: brandColor.opacity(0.14), radius: 28, y: 14)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.sm)
    }

    private var topRow: some View {
        HStack {
            Label("SANA ÖZEL", systemImage: "sparkles")
                .font(Theme.Typography.badge)
                .tracking(1)
                .foregroundColor(brandColor)
                .padding(.horizontal, Theme.Spacing.md)
                .frame(minHeight: 32)
                .background(Color.black.opacity(0.16), in: Capsule())

            Spacer(minLength: Theme.Spacing.sm)
            clock
        }
    }

    private var clock: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "clock")
                Text(context.date, format: .dateTime.hour().minute())
                    .monospacedDigit()
            }
            .font(Theme.Typography.caption.weight(.semibold))
            .foregroundColor(Theme.Palette.textPrimary)
            .padding(.horizontal, Theme.Spacing.md)
            .frame(minHeight: 32)
            .background(Color.black.opacity(0.16), in: Capsule())
        }
        .accessibilityLabel("Saat")
    }

    private var greetingBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(greeting)
                .font(Theme.Typography.screenTitle)
                .foregroundColor(Theme.Palette.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.78)

            Text("Bugün ne izlemek istersin?")
                .font(Theme.Typography.rowSubtitle)
                .foregroundColor(Theme.Palette.textSecondary)
        }
    }

    private var actions: some View {
        HStack(spacing: Theme.Spacing.sm) {
            heroButton(
                title: "Canlı TV",
                icon: "play.fill",
                isPrimary: true,
                action: onWatchLive
            )
            heroButton(
                title: "Filmleri keşfet",
                icon: "film.fill",
                isPrimary: false,
                action: onExplore
            )
        }
    }

    private func heroButton(
        title: String,
        icon: String,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.light()
            action()
        } label: {
            Label(title, systemImage: icon)
                .font(Theme.Typography.caption.weight(.semibold))
                .foregroundColor(isPrimary ? .white : Theme.Palette.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(isPrimary ? brandColor : Color.white.opacity(0.09))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .stroke(Color.white.opacity(isPrimary ? 0.08 : 0.12), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private var statusLine: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: statusIcon)
                .foregroundColor(statusColor)

            Text(statusText)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Palette.textSecondary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.top, Theme.Spacing.xs)
        .accessibilityElement(children: .combine)
    }

    private var statusText: String {
        guard let account else { return "İçeriklerin hazır" }
        switch account.urgency {
        case .normal: return account.expiryText.map { "Aboneliğin aktif · \($0)" } ?? "İçeriklerin güncel"
        case .soon, .expired: return account.expiryText ?? "Abonelik bilgini kontrol et"
        }
    }

    private var statusIcon: String {
        guard let account else { return "checkmark.seal.fill" }
        return account.urgency == .normal ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
    }

    private var statusColor: Color {
        guard let account else { return Theme.Palette.success }
        switch account.urgency {
        case .normal: return Theme.Palette.success
        case .soon: return Theme.Palette.warning
        case .expired: return Theme.Palette.error
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [
                brandColor.opacity(0.34),
                Theme.Palette.surfaceElevated,
                Theme.Palette.surface
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var decoration: some View {
        ZStack {
            Circle()
                .fill(brandColor.opacity(0.18))
                .frame(width: 220, height: 220)
                .blur(radius: 16)
                .offset(x: 250, y: -90)

            Circle()
                .stroke(Color.white.opacity(0.05), lineWidth: 26)
                .frame(width: 170, height: 170)
                .offset(x: 290, y: 180)
        }
        .allowsHitTesting(false)
    }
}
