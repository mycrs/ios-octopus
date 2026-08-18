import SwiftUI
import OctopusDomain
import OctopusDesignSystem

/// Doğrulama ve ilk senkronizasyon sırasında gösterilen katman.
///
/// Referans dersi: kullanıcı kanal açılmasını beklerken hiçbir geri bildirim
/// göremediğinde uygulamanın donduğunu sanıyor. Burada her aşama adıyla
/// bildirilir; ilerleme oranı bilinmiyorsa belirsiz gösterge kullanılır.
struct SyncOverlayView: View {

    let step: AddPlaylistViewModel.Step
    let counts: SyncContentCounts
    let brandName: String
    let logoURL: URL?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.brandColor) private var brandColor
    @Environment(\.locale) private var locale
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.66).ignoresSafeArea()
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .opacity(0.16)

            VStack(spacing: Theme.Spacing.xl) {
                SyncProgressIndicator(
                    fraction: fraction,
                    isFinished: isFinished,
                    isPulsing: isPulsing,
                    reduceMotion: reduceMotion,
                    logoURL: logoURL
                )

                Text(brandName)
                    .font(Theme.Typography.rowTitle.weight(.semibold))
                    .foregroundColor(Theme.Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                VStack(spacing: Theme.Spacing.sm) {
                    Text(AppLocalization.localized(eyebrow, locale: locale))
                        .font(Theme.Typography.badge)
                        .tracking(1.2)
                        .foregroundColor(brandColor)

                    Text(AppLocalization.localized(title, locale: locale))
                        .font(Theme.Typography.sectionTitle)
                        .foregroundColor(Theme.Palette.textPrimary)
                        .multilineTextAlignment(.center)

                    if let detail {
                        Text(AppLocalization.localized(detail, locale: locale))
                            .font(Theme.Typography.rowSubtitle)
                            .foregroundColor(Theme.Palette.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if showsContentStats {
                    SyncContentStatsView(
                        counts: counts,
                        activeKind: activeCatalog,
                        isFinished: isFinished
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                progressTrack
            }
            .padding(Theme.Spacing.xxl)
            .frame(maxWidth: 380)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(.regularMaterial)
                    LinearGradient(
                        colors: [brandColor.opacity(0.14), .clear, brandColor.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .environment(\.colorScheme, .dark)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.42), radius: 32, y: 18)
            .padding(Theme.Spacing.xl)
        }
        .transition(.opacity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(AppLocalization.localized(title, locale: locale)). "
                + AppLocalization.localized(detail ?? "", locale: locale)
        )
        .onAppear { isPulsing = true }
    }

    private var progressTrack: some View {
        VStack(spacing: Theme.Spacing.sm) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Palette.separator)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [brandColor, Theme.Palette.success],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: proxy.size.width * trackFraction)
                }
            }
            .frame(height: 5)

            HStack {
                Text("BAĞLAN")
                Spacer()
                Text("AKTAR")
                Spacer()
                Text("HAZIR")
            }
            .font(Theme.Typography.badge)
            .foregroundColor(Theme.Palette.textTertiary)
        }
    }

    // MARK: - Aşama metinleri

    private var title: String {
        switch step {
        case .searchingServer:
            return "Bağlantı hazırlanıyor"
        case .validating:
            return "Bağlantı sınanıyor"
        case .syncing(let stage):
            return isFinished ? "Kütüphanen hazır" : stage.title
        case .form, .done:
            return ""
        }
    }

    private var eyebrow: String {
        switch step {
        case .searchingServer, .validating: return "BAĞLANTI KURULUYOR"
        case .syncing: return isFinished ? "HAZIR" : "İÇERİKLER HAZIRLANIYOR"
        case .form, .done: return "KURULUM"
        }
    }

    private var detail: String? {
        switch step {
        case .searchingServer:
            return "Bilgilerin kontrol ediliyor. Bu işlem biraz sürebilir."
        case .validating:
            return "Bilgilerin güvenli şekilde doğrulanıyor."
        case .syncing:
            return isFinished
                ? "İçeriklerin hazır. İzlemeye başlayabilirsin."
                : "İlk kurulum biraz sürebilir. Büyük listelerde bu adım uzun olabilir."
        case .form, .done:
            return nil
        }
    }

    private var fraction: Double? {
        guard case .syncing(let stage) = step else { return nil }
        return stage.fraction
    }

    private var trackFraction: Double {
        switch step {
        case .searchingServer(let index, let total):
            guard total > 0 else { return 0.10 }
            return min(0.25, 0.08 + (Double(index) / Double(total)) * 0.17)
        case .validating: return 0.28
        case .syncing(.finished): return 1
        case .syncing(let stage):
            return 0.28 + (stage.fraction ?? stage.fallbackFraction) * 0.68
        case .form: return 0
        case .done: return 1
        }
    }

    private var activeCatalog: SyncCatalogKind? {
        guard case .syncing(let stage) = step else { return nil }
        return stage.catalogKind
    }

    private var showsContentStats: Bool {
        guard case .syncing = step else { return false }
        return true
    }

    private var isFinished: Bool {
        guard case .syncing(.finished) = step else { return false }
        return true
    }
}
