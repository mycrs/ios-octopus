import SwiftUI
import OctopusDomain
import OctopusDesignSystem

struct OnboardingHeroHeader: View {
    @Environment(\.brandColor) private var brandColor

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(brandColor.opacity(0.16))
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundColor(brandColor)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("GÜVENLİ KURULUM")
                    .font(Theme.Typography.badge)
                    .tracking(1.1)
                    .foregroundColor(brandColor)

                Text("Kaynak ekle")
                    .font(Theme.Typography.screenTitle)
                    .foregroundColor(Theme.Palette.textPrimary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct OnboardingSourcePicker: View {
    let kinds: [AddPlaylistViewModel.SourceKind]
    @Binding var selection: AddPlaylistViewModel.SourceKind
    @Environment(\.brandColor) private var brandColor
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(kinds) { kind in
                let isSelected = selection == kind

                Button {
                    guard selection != kind else { return }
                    Haptics.selection()
                    withAnimation(.easeInOut(duration: 0.22)) {
                        selection = kind
                    }
                } label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: kind.icon)
                            .font(.system(size: 14, weight: .semibold))
                        Text(AppLocalization.localized(kind.title, locale: locale))
                            .font(Theme.Typography.caption.weight(.semibold))
                    }
                    .foregroundColor(isSelected ? Theme.Palette.textPrimary : Theme.Palette.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .background(isSelected ? brandColor.opacity(0.16) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                    .shadow(color: isSelected ? Color.black.opacity(0.24) : .clear, radius: 8, y: 3)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(Theme.Spacing.xs)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        }
    }
}

struct ActivationCodeIntro: View {
    @Environment(\.brandColor) private var brandColor

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle().fill(brandColor.opacity(0.16))
                Image(systemName: "key.horizontal.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(brandColor)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Tek kodla hazır")
                    .font(Theme.Typography.rowTitle)
                    .foregroundColor(Theme.Palette.textPrimary)
                Text("Hesabın güvenli şekilde otomatik olarak hazırlanır.")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct OnboardingSubmitButton: View {
    let title: String
    let isEnabled: Bool
    let action: () -> Void
    @Environment(\.brandColor) private var brandColor
    @Environment(\.locale) private var locale

    var body: some View {
        Button {
            Haptics.light()
            action()
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Text(AppLocalization.localized(title, locale: locale))
                    .font(Theme.Typography.rowTitle)
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 54)
            .foregroundColor(.white)
            .background(
                LinearGradient(
                    colors: [brandColor, brandColor.opacity(0.72)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            .shadow(
                color: isEnabled ? brandColor.opacity(0.28) : .clear,
                radius: 16,
                y: 8
            )
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.42)
        .disabled(!isEnabled)
    }
}

extension AddPlaylistViewModel.SourceKind {
    var icon: String {
        switch self {
        case .activationCode: return "key.fill"
        case .xtream: return "server.rack"
        case .m3u: return "link"
        }
    }
}
