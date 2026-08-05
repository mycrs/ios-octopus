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

    private let message: String?
    private let contact: ContactChannels
    private let onRetry: () -> Void

    public init(
        message: String?,
        contact: ContactChannels,
        onRetry: @escaping () -> Void
    ) {
        self.message = message
        self.contact = contact
        self.onRetry = onRetry
    }

    public var body: some View {
        ZStack {
            Theme.Palette.background.ignoresSafeArea()

            VStack(spacing: Theme.Spacing.xl) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 48))
                    .foregroundColor(Theme.Palette.warning)

                VStack(spacing: Theme.Spacing.sm) {
                    Text("Kısa bir bakımdayız")
                        .font(Theme.Typography.sectionTitle)
                        .foregroundColor(Theme.Palette.textPrimary)

                    Text(message ?? "Servis kısa süre içinde tekrar açılacak.")
                        .font(Theme.Typography.rowSubtitle)
                        .foregroundColor(Theme.Palette.textSecondary)
                        .multilineTextAlignment(.center)
                }

                Button("Tekrar dene", action: onRetry)
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
