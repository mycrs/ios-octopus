import SwiftUI
import UIKit          // UIPasteboard
import OctopusDomain
import OctopusDesignSystem

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
    let onRetry: () -> Void
    let onClose: () -> Void

    @State private var didCopy = false

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            EmptyStateView(
                icon: "play.slash",
                title: "Yayın açılamadı",
                message: error.userMessage,
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
                    Label(
                        didCopy ? "Kopyalandı" : "Adresi kopyala",
                        systemImage: didCopy ? "checkmark" : "doc.on.doc"
                    )
                }

                Button("Kapat", action: onClose)
                    .foregroundColor(Theme.Palette.textSecondary)
            }
            .font(Theme.Typography.caption)
        }
        .padding(Theme.Spacing.lg)
    }
}
