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

    var body: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()

            VStack(spacing: Theme.Spacing.lg) {
                indicator

                Text(title)
                    .font(Theme.Typography.sectionTitle)
                    .foregroundColor(Theme.Palette.textPrimary)
                    .multilineTextAlignment(.center)

                if let detail {
                    Text(detail)
                        .font(Theme.Typography.rowSubtitle)
                        .foregroundColor(Theme.Palette.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(Theme.Spacing.xxl)
            .background(Theme.Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            .padding(Theme.Spacing.xl)
        }
    }

    @ViewBuilder
    private var indicator: some View {
        if let fraction {
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .tint(Theme.Palette.accent)
                .frame(width: 200)
        } else {
            ProgressView()
                .tint(Theme.Palette.accent)
                .scaleEffect(1.4)
        }
    }

    // MARK: - Aşama metinleri

    private var title: String {
        switch step {
        case .searchingServer(let index, let total):
            return "Sunucu aranıyor (\(index)/\(total))"
        case .validating:
            return "Bağlantı sınanıyor"
        case .syncing(let stage):
            return stage.title
        case .form, .done:
            return ""
        }
    }

    private var detail: String? {
        switch step {
        case .searchingServer:
            return "Bayinin sunucuları sırayla deneniyor. Hesabının çalıştığı "
                + "sunucu bulununca kurulum kendiliğinden sürecek."
        case .validating:
            return "Sunucuya erişiliyor ve hesap bilgilerin doğrulanıyor."
        case .syncing:
            return "İlk kurulum biraz sürebilir. Büyük listelerde bu adım uzun olabilir."
        case .form, .done:
            return nil
        }
    }

    private var fraction: Double? {
        guard case .syncing(let stage) = step else { return nil }
        return stage.fraction
    }
}

private extension SyncStage {
    var title: String {
        switch self {
        case .idle: return "Hazırlanıyor"
        case .authenticating: return "Hesap doğrulanıyor"
        case .fetchingCategories: return "Kategoriler alınıyor"
        case .fetchingChannels: return "Kanallar alınıyor"
        case .fetchingMovies: return "Filmler alınıyor"
        case .fetchingSeries: return "Diziler alınıyor"
        case .fetchingEPG: return "Yayın akışı alınıyor"
        case .persisting: return "Cihaza kaydediliyor"
        case .finished: return "Tamamlandı"
        case .failed: return "Bir sorun oluştu"
        }
    }
}
