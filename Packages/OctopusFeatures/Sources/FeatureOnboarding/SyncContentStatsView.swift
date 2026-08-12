import SwiftUI
import OctopusDomain
import OctopusDesignSystem

enum SyncCatalogKind: CaseIterable, Hashable {
    case channels
    case movies
    case series

    var title: String {
        switch self {
        case .channels: return "Kanallar"
        case .movies: return "Filmler"
        case .series: return "Diziler"
        }
    }

    var icon: String {
        switch self {
        case .channels: return "tv.fill"
        case .movies: return "film.fill"
        case .series: return "rectangle.stack.fill"
        }
    }
}

/// İlk kurulumda katalogların gerçek adetlerini canlı gösteren üçlü özet.
struct SyncContentStatsView: View {
    let counts: SyncContentCounts
    let activeKind: SyncCatalogKind?
    let isFinished: Bool

    @Environment(\.brandColor) private var brandColor
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(SyncCatalogKind.allCases, id: \.self) { kind in
                statCard(kind)
            }
        }
        .animation(.easeOut(duration: 0.75), value: counts)
    }

    private func statCard(_ kind: SyncCatalogKind) -> some View {
        let count = count(for: kind)
        let isActive = activeKind == kind && count == nil

        return VStack(spacing: Theme.Spacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(cardTint(kind).opacity(0.13))

                if isActive {
                    ProgressView()
                        .tint(cardTint(kind))
                } else {
                    Image(systemName: count != nil ? "checkmark" : kind.icon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(cardTint(kind))
                }
            }
            .frame(width: 34, height: 34)

            ZStack {
                AnimatedCountText(value: count ?? 0, locale: locale)
                    .opacity(count == nil ? 0 : 1)

                if count == nil && !isActive {
                    Text("—")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundColor(Theme.Palette.textTertiary)
                }
            }
            .frame(height: 25)

            Text(AppLocalization.localized(kind.title, locale: locale))
                .font(Theme.Typography.badge)
                .foregroundColor(Theme.Palette.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.md)
        .background(Color.black.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .stroke(
                    isActive ? brandColor.opacity(0.65) : Color.white.opacity(0.07),
                    lineWidth: isActive ? 1.5 : 1
                )
        }
        .scaleEffect(isActive ? 1.025 : 1)
        .animation(.easeInOut(duration: 0.25), value: isActive)
        .accessibilityElement(children: .combine)
    }

    private func count(for kind: SyncCatalogKind) -> Int? {
        switch kind {
        case .channels: return counts.channels
        case .movies: return counts.movies
        case .series: return counts.series
        }
    }

    private func cardTint(_ kind: SyncCatalogKind) -> Color {
        guard !isFinished else { return Theme.Palette.success }
        return activeKind == kind ? brandColor : Theme.Palette.textSecondary
    }
}

private struct AnimatedCountText: View, Animatable {
    var animatedValue: Double
    let locale: Locale

    init(value: Int, locale: Locale) {
        self.animatedValue = Double(value)
        self.locale = locale
    }

    var animatableData: Double {
        get { animatedValue }
        set { animatedValue = newValue }
    }

    var body: some View {
        Text(Int(animatedValue.rounded()), format: .number.locale(locale))
            .font(.system(.headline, design: .rounded).weight(.bold))
            .foregroundColor(Theme.Palette.textPrimary)
            .monospacedDigit()
            .minimumScaleFactor(0.68)
            .lineLimit(1)
    }
}
