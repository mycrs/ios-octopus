import SwiftUI
import OctopusDomain
import OctopusDesignSystem

/// Panelden gelen duyuru şeridi.
///
/// Aynı duyuru her açılışta tekrar gösterilmez: kullanıcı kapattığında
/// duyurunun kimliği saklanır. Panel yeni metin yayınlarsa kimlik değişir
/// ve duyuru yeniden görünür.
public struct AnnouncementBanner: View {

    private let announcement: Announcement
    private let onDismiss: () -> Void

    public init(announcement: Announcement, onDismiss: @escaping () -> Void) {
        self.announcement = announcement
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: "megaphone.fill")
                .foregroundColor(Theme.Palette.accent)

            Text(announcement.message)
                .font(Theme.Typography.rowSubtitle)
                .foregroundColor(Theme.Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Palette.textSecondary)
            }
            .accessibilityLabel("Duyuruyu kapat")
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Palette.accentMuted)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
    }
}

/// Panel bakım moduna aldığında gösterilen tam ekran kapı.
///
/// Sunucu tarafı bir sorun sırasında kullanıcının "uygulama bozuk" sanmasını
/// önler; sorunun geçici olduğunu ve nereye başvuracağını söyler.
public struct MaintenanceGateView: View {

    private let gate: ServiceGate
    private let contact: ContactChannels
    private let onRetry: () -> Void

    /// ⚠️ Mesaj yerine **kapının kendisi** alınıyor: iki farklı engel var
    /// ve ikisi kullanıcıdan farklı şey istiyor. Bakım geçicidir
    /// ("biraz sonra tekrar dene"); platform kapalıysa beklemenin faydası
    /// yok, bayiye başvurmak gerekir. Aynı ekranı göstermek kullanıcıyı
    /// saatlerce uygulamayı açıp kapamaya iterdi.
    public init(
        gate: ServiceGate,
        contact: ContactChannels,
        onRetry: @escaping () -> Void
    ) {
        self.gate = gate
        self.contact = contact
        self.onRetry = onRetry
    }

    private var iconName: String {
        switch gate {
        case .platformUnavailable: return "iphone.slash"
        case .maintenance, .open: return "wrench.and.screwdriver.fill"
        }
    }

    private var title: String {
        switch gate {
        case .platformUnavailable: return "iPhone sürümü henüz açık değil"
        case .maintenance, .open: return "Kısa bir bakımdayız"
        }
    }

    private var detail: String {
        switch gate {
        case .platformUnavailable:
            return "Bayin bu uygulamayı iOS için henüz etkinleştirmedi. "
                + "Etkinleştirildiğinde buradan girebileceksin."
        case .maintenance(let message):
            return message ?? "Servis kısa süre içinde tekrar açılacak."
        case .open:
            return ""
        }
    }

    /// Platform kapalıyken de bir düğme var ama sözü farklı: "tekrar dene"
    /// bir şeyin düzelmesini beklemek demek, oysa burada bayinin ayar
    /// değiştirmesi bekleniyor.
    private var retryTitle: String {
        switch gate {
        case .platformUnavailable: return "Yeniden kontrol et"
        case .maintenance, .open: return "Tekrar dene"
        }
    }

    public var body: some View {
        ZStack {
            Theme.Palette.background.ignoresSafeArea()

            VStack(spacing: Theme.Spacing.xl) {
                Image(systemName: iconName)
                    .font(.system(size: 48))
                    .foregroundColor(Theme.Palette.warning)

                VStack(spacing: Theme.Spacing.sm) {
                    Text(title)
                        .font(Theme.Typography.sectionTitle)
                        .foregroundColor(Theme.Palette.textPrimary)

                    Text(detail)
                        .font(Theme.Typography.rowSubtitle)
                        .foregroundColor(Theme.Palette.textSecondary)
                        .multilineTextAlignment(.center)
                }

                Button(retryTitle, action: onRetry)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.Palette.accent)

                if contact.hasAny {
                    ContactLinksView(contact: contact)
                }
            }
            .padding(Theme.Spacing.xl)
        }
    }
}

/// Bayinin destek kanalları.
public struct ContactLinksView: View {

    private let contact: ContactChannels

    public init(contact: ContactChannels) {
        self.contact = contact
    }

    public var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Text("Destek")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Palette.textTertiary)

            HStack(spacing: Theme.Spacing.lg) {
                if let url = contact.whatsAppURL {
                    Link(destination: url) {
                        Label("WhatsApp", systemImage: "message.fill")
                    }
                }
                if let url = contact.telegramURL {
                    Link(destination: url) {
                        Label("Telegram", systemImage: "paperplane.fill")
                    }
                }
                if let url = contact.websiteURL {
                    Link(destination: url) {
                        Label("Site", systemImage: "globe")
                    }
                }
            }
            .font(Theme.Typography.caption)
            .tint(Theme.Palette.accent)
        }
    }
}
