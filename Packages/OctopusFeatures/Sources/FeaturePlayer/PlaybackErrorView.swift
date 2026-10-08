import SwiftUI
import UIKit          // UIPasteboard
import OctopusDomain
import OctopusDesignSystem
import OctopusPlayback

/// Adres üretildi ama yayın açılamadı.
///
/// ## Neden adres burada gösteriliyor?
/// IPTV'de "açılmıyor" şikâyetinin kaynağı ikiye ayrılır: ya bizim
/// tarafımız (yanlış başlık, desteklenmeyen format) ya da kaynağın
/// kendisi (abonelik bitmiş, sunucu kapalı). Kullanıcı adresi kopyalayıp
/// harici bir oynatıcıda deneyince ayrım **tek hamlede** ortaya çıkar.
/// Destek için en değerli tek düğme bu.
///
/// ⚠️ Adres **maskeli** gösterilir: Xtream adresleri kullanıcı adını ve
/// parolayı yol içinde taşır, ekran görüntüsü paylaşan kullanıcı hesabını
/// ele verirdi. Kopyalanan değer tam adrestir.
struct PlaybackErrorView: View {

    let error: AppError
    let item: PlaybackItem
    let failureKind: PlaybackFailureKind?
    let onRetry: () -> Void
    let onClose: () -> Void
    let onPreviousChannel: (() -> Void)?
    let onNextChannel: (() -> Void)?

    @State private var didCopy = false
    @Environment(\.locale) private var locale

    init(
        error: AppError,
        item: PlaybackItem,
        failureKind: PlaybackFailureKind? = nil,
        onRetry: @escaping () -> Void,
        onClose: @escaping () -> Void,
        onPreviousChannel: (() -> Void)? = nil,
        onNextChannel: (() -> Void)? = nil
    ) {
        self.error = error
        self.item = item
        self.failureKind = failureKind
        self.onRetry = onRetry
        self.onClose = onClose
        self.onPreviousChannel = onPreviousChannel
        self.onNextChannel = onNextChannel
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            EmptyStateView(
                icon: "play.slash",
                title: "Yayın açılamadı",
                message: failureMessage,
                actionTitle: "Tekrar dene",
                action: onRetry
            )

            Text(PlayerViewModel.maskedURL(item.url))
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(Theme.Palette.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.md)

            HStack(spacing: Theme.Spacing.md) {
                Button {
                    UIPasteboard.general.string = item.url.absoluteString
                    didCopy = true
                } label: {
                    Label {
                        Text(
                            AppLocalization.localized(
                                didCopy ? "Kopyalandı" : "Adresi kopyala",
                                locale: locale
                            )
                        )
                    } icon: {
                        Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    }
                }

                Button("Kapat", action: onClose)
                    .foregroundColor(Theme.Palette.textSecondary)
            }
            .font(Theme.Typography.caption)

            if let onPreviousChannel, let onNextChannel {
                HStack(spacing: Theme.Spacing.md) {
                    Button(action: onPreviousChannel) {
                        Label("Önceki kanal", systemImage: "backward.end.fill")
                    }
                    Button(action: onNextChannel) {
                        Label("Sonraki kanal", systemImage: "forward.end.fill")
                    }
                }
                .buttonStyle(.bordered)
                .font(Theme.Typography.caption)
            }
        }
        .padding(Theme.Spacing.lg)
    }

    /// Only known local messages are shown; provider error text stays private.
    private var failureMessage: String {
        switch failureKind {
        case .requiresFallbackHeaders, .unsupportedHeaders:
            return "Bu yayının gerekli istek başlıkları sistem oynatıcısı tarafından desteklenmiyor."
        case .unsupportedFormat:
            return "Yayın biçimi sistem oynatıcısı tarafından desteklenmiyor."
        case .videoNotRendered:
            return "Yayından görüntü alınamadı. Oynatıcı tercihlerini kontrol edip tekrar dene."
        case .decoder:
            return "Yayının ses veya görüntüsü çözülemedi. Oynatıcı tercihlerini kontrol edip tekrar dene."
        case .authorization where error != .unauthorized:
            return "Sunucu erişimi reddetti (403). Aboneliğin süresi dolmuş ya da aynı anda izin verilen cihaz sayısı aşılmış olabilir."
        default:
            return error.userMessage
        }
    }
}
