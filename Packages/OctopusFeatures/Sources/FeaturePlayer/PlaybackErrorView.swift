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
    let onPreviousChannel: (() -> Void)?
    let onNextChannel: (() -> Void)?

    @State private var didCopy = false

    init(
        error: AppError,
        item: PlaybackItem,
        onRetry: @escaping () -> Void,
        onClose: @escaping () -> Void,
        onPreviousChannel: (() -> Void)? = nil,
        onNextChannel: (() -> Void)? = nil
    ) {
        self.error = error
        self.item = item
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
}
